import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

const DEFAULT_FREE_LIMIT = 3;
const GRACE_PERIOD_MILLISECONDS = 3 * 24 * 60 * 60 * 1000; // 3 days

// Helper function to safely get the user's timezone
function getUserTimezone(user: any, profile: any): string {
  if (user?.user_metadata?.timezone) {
    try {
      // Validate if it's a real IANA timezone
      new Date().toLocaleString('en-US', { timeZone: user.user_metadata.timezone });
      return user.user_metadata.timezone;
    } catch (e) {
      console.warn(`Invalid timezone in user.user_metadata.timezone: ${user.user_metadata.timezone}. Falling back.`);
    }
  }
  if (profile?.timezone) {
     try {
      new Date().toLocaleString('en-US', { timeZone: profile.timezone });
      return profile.timezone;
    } catch (e) {
      console.warn(`Invalid timezone in profile.timezone: ${profile.timezone}. Falling back.`);
    }
  }
  console.warn(`No valid timezone found for user ${user?.id}, defaulting to UTC.`);
  return "UTC";
}

// Helper function to get YYYY-MM-DD in a specific timezone
function getDateStringInTimezone(date: Date, timeZone: string): string {
  return date.toLocaleDateString('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' });
}

// Helper function to get the start of the next day in a specific timezone, then convert to UTC ISO string
function getNextUTCMidnightISO(): string {
  const nowUtc = new Date();
  const nextUTCMidnight = new Date(Date.UTC(nowUtc.getUTCFullYear(), nowUtc.getUTCMonth(), nowUtc.getUTCDate() + 1, 0, 0, 0, 0));
  return nextUTCMidnight.toISOString();
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: req.headers.get("Authorization")! } } }
    );

    const { data: { user }, error: userError } = await supabaseClient.auth.getUser();
    if (userError || !user) {
      console.error("User auth error:", userError);
      return new Response(JSON.stringify({ error: "User not authenticated" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 401,
      });
    }

    const { data: profile, error: profileError } = await supabaseClient
      .from("profiles")
      .select("last_generation_at, generations_today, timezone, current_subscription_tier, subscription_active, subscription_expires_at, subscription_cycle_start_date, generation_limit")
      .eq("id", user.id)
      .single();

    if (profileError || !profile) {
       console.error(`Profile not found or error for user ID: ${user?.id}. Profile query error:`, profileError, "for user ID:", user.id);
      return new Response(JSON.stringify({ error: "Profile not found" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 404,
      });
    }

    let lt_generations_today = typeof profile.generations_today === 'number' ? profile.generations_today : 0;
    const userTimezone = getUserTimezone(user, profile);
    const now = new Date();
    const profileUpdates: Record<string, any> = {};
    let needsDBUpdateBeforeGenerationAttempt = false; // Renamed for clarity
    let derivedGenerationLimit = profile.generation_limit || DEFAULT_FREE_LIMIT;
    let nextResetForClientIso = getNextUTCMidnightISO();
    let isMonthlyTier = false;

    // Subscription and Reset Logic
    const isSubscriptionEffectivelyActive = 
        profile.subscription_active && 
        profile.subscription_expires_at && 
        (new Date(profile.subscription_expires_at).getTime() + GRACE_PERIOD_MILLISECONDS) > now.getTime();

    if (isSubscriptionEffectivelyActive) {
      if (profile.current_subscription_tier === 'monthly_unlimited') {
        derivedGenerationLimit = -1; // Unlimited
        lt_generations_today = 0; 
        nextResetForClientIso = new Date(profile.subscription_expires_at).toISOString();
        isMonthlyTier = true; 
      } else if (profile.current_subscription_tier === 'monthly_30') {
        isMonthlyTier = true;
        derivedGenerationLimit = 30;
        let currentCycleStartDate = profile.subscription_cycle_start_date ? new Date(profile.subscription_cycle_start_date) : null;

        if (!currentCycleStartDate) {
          currentCycleStartDate = new Date(now); 
          lt_generations_today = 0;
          profileUpdates.subscription_cycle_start_date = currentCycleStartDate.toISOString();
          profileUpdates.generations_today = 0;
          needsDBUpdateBeforeGenerationAttempt = true;
        }

        const nextMonthlyResetDate = new Date(currentCycleStartDate);
        nextMonthlyResetDate.setUTCMonth(currentCycleStartDate.getUTCMonth() + 1);
        nextMonthlyResetDate.setUTCHours(0,0,0,0);

        if (now >= nextMonthlyResetDate) { 
          lt_generations_today = 0;
          currentCycleStartDate = new Date(now); 
          profileUpdates.generations_today = 0;
          profileUpdates.subscription_cycle_start_date = currentCycleStartDate.toISOString();
          needsDBUpdateBeforeGenerationAttempt = true;
        }
        const finalCycleStartDateForNextReset = new Date(profileUpdates.subscription_cycle_start_date || currentCycleStartDate.toISOString());
        const actualNextMonthlyReset = new Date(finalCycleStartDateForNextReset);
        actualNextMonthlyReset.setUTCMonth(finalCycleStartDateForNextReset.getUTCMonth() + 1);
        actualNextMonthlyReset.setUTCHours(0,0,0,0);
        nextResetForClientIso = actualNextMonthlyReset.toISOString();
      }
    }
    
    if (!isMonthlyTier) {
      derivedGenerationLimit = profile.generation_limit || DEFAULT_FREE_LIMIT;
      let performDailyReset = false;
      if (profile.last_generation_at) {
        const lastGenDateUtc = new Date(profile.last_generation_at);
        const nowDayStrUserTz = getDateStringInTimezone(now, userTimezone);
        const lastGenDayStrUserTz = getDateStringInTimezone(lastGenDateUtc, userTimezone);
        if (nowDayStrUserTz > lastGenDayStrUserTz) {
          performDailyReset = true;
        }
      } else {
        performDailyReset = true; 
      }

      if (performDailyReset) {
        lt_generations_today = 0;
        profileUpdates.generations_today = 0;
        needsDBUpdateBeforeGenerationAttempt = true;
      }
      nextResetForClientIso = getNextUTCMidnightISO();
    }

    if (needsDBUpdateBeforeGenerationAttempt && Object.keys(profileUpdates).length > 0) {
      console.log(`User ${user.id}: Performing pre-generation profile update for cycle/daily reset:`, profileUpdates);
      const { error: resetUpdateError } = await supabaseClient
        .from("profiles")
        .update(profileUpdates)
        .eq("id", user.id);
      if (resetUpdateError) {
        console.error(`User ${user.id}: Failed to update profile on cycle/daily reset:`, resetUpdateError.message);
      }
    }

    if (derivedGenerationLimit !== -1 && lt_generations_today >= derivedGenerationLimit) {
      console.log(`Limit (${derivedGenerationLimit}) reached for user ${user.id}. Generations this period: ${lt_generations_today}. Resets at: ${nextResetForClientIso}`);
      return new Response(
        JSON.stringify({ 
            error: `Generation limit of ${derivedGenerationLimit} reached for the current period.`,
            resets_at_utc_iso: nextResetForClientIso,
            limit_details: {
              current_limit: derivedGenerationLimit,
              generations_used_this_period: lt_generations_today,
              active_subscription: profile.current_subscription_tier
            }
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 429 }
      );
    }

    // --- Attempt OpenAI Generation First ---
    const body = await req.json();
    const { prompt, n = 1, size = "1024x1024" } = body;

    if (!prompt) {
      return new Response(JSON.stringify({ error: "Prompt is required" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }
    
    const openaiApiKey = Deno.env.get("OPENAI_API_KEY");
    if (!openaiApiKey) {
        console.error("OpenAI API key not set for generate-image-proxy.");
        return new Response(JSON.stringify({ error: "Image generation service not configured." }), {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
            status: 503, 
        });
    }

    let openaiDataResponse: any;

    try {
      console.log(`User ${user.id} generating image with prompt (first 50 chars): ${prompt.substring(0,50)}...`);
      const openaiResponse = await fetch("https://api.openai.com/v1/images/generations", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${openaiApiKey}`,
        },
        body: JSON.stringify({ model: "dall-e-3", prompt, n, size }),
      });

      openaiDataResponse = await openaiResponse.json();

      if (!openaiResponse.ok) {
        console.error(`OpenAI API Error for user ${user.id} (Status: ${openaiResponse.status}):`, openaiDataResponse);
        return new Response(JSON.stringify({ 
            error: openaiDataResponse.error?.message || "OpenAI API request failed", 
            details: openaiDataResponse.error 
        }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: openaiResponse.status, // Propagate OpenAI's error status
        });
      }
      
      // --- OpenAI Call Successful: Now Debit Generation ---
      const generationsCountForDBDebit = lt_generations_today + 1;
      const timestampForThisAttempt = new Date().toISOString(); 

      console.log(`User ${user.id}: OpenAI success. Debiting generation. Current (before this): ${lt_generations_today}, New DB count: ${generationsCountForDBDebit}`);
      const { data: debitedProfile, error: debitError } = await supabaseClient
        .from("profiles")
        .update({
          generations_today: generationsCountForDBDebit,
          last_generation_at: timestampForThisAttempt, 
        })
        .eq("id", user.id)
        .select('generations_today, last_generation_at')
        .single();

      if (debitError || !debitedProfile) {
        console.error(`User ${user.id}: CRITICAL - OpenAI call SUCCEEDED but FAILED to debit generation count:`, debitError?.message);
        return new Response(JSON.stringify({
          ...openaiDataResponse,
          warning: "Image generated, but an issue occurred while updating your credits. Please check your balance or contact support if discrepancies continue.",
          generation_status: { 
            generations_used_this_period: lt_generations_today, // Show pre-attempt status
            limit: derivedGenerationLimit,
            next_reset_utc_iso: nextResetForClientIso,
            debit_error: true
          }
        }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 200, // Still 200 as image was generated
        });
      }
      
      console.log(`User ${user.id}: Successfully debited. DB generations_today: ${debitedProfile.generations_today}. Last gen_at: ${debitedProfile.last_generation_at}`);
      
      return new Response(JSON.stringify({
        ...openaiDataResponse,
        generation_status: {
            generations_used_this_period: debitedProfile.generations_today,
            limit: derivedGenerationLimit,
            next_reset_utc_iso: nextResetForClientIso
          }
      }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      });

    } catch (generationApiError) {
      // Catches errors from the fetch call itself (network, DNS) or JSON parsing of OpenAI response
      console.error(`User ${user.id}: Network or parsing error during OpenAI interaction:`, generationApiError.message);
      return new Response(JSON.stringify({ error: "Image generation service currently unavailable. Please try again later." , details: generationApiError.message }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 503, // Service Unavailable
      });
    }

  } catch (error) {
    console.error('General error in generate-image-proxy:', error.message, error.stack);
    return new Response(JSON.stringify({ error: error.message || "An unexpected server error occurred." }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
}); 