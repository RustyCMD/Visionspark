import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
// import { corsHeaders } from "../_shared/cors.ts"; // Removed import

// Inlined corsHeaders
const corsHeaders = {
  "Access-Control-Allow-Origin": "*", 
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const DEFAULT_FREE_LIMIT = 3;

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
    let needsDBUpdateBeforeDebit = false;
    let derivedGenerationLimit = profile.generation_limit || DEFAULT_FREE_LIMIT; // Start with default or profile's base limit
    let nextResetForClientIso = getNextUTCMidnightISO(); // Default daily UTC reset
    let isMonthlyTier = false;

    // Subscription and Reset Logic
    if (profile.subscription_active && profile.subscription_expires_at && new Date(profile.subscription_expires_at) > now) {
      if (profile.current_subscription_tier === 'monthly_unlimited') {
        derivedGenerationLimit = -1; // Unlimited
        lt_generations_today = 0; // Not strictly tracked against limit
        nextResetForClientIso = new Date(profile.subscription_expires_at).toISOString();
        isMonthlyTier = true; // Considers unlimited as a type of monthly plan for skipping daily reset
      } else if (profile.current_subscription_tier === 'monthly_30') {
        isMonthlyTier = true;
        derivedGenerationLimit = 30;
        let currentCycleStartDate = profile.subscription_cycle_start_date ? new Date(profile.subscription_cycle_start_date) : null;

        if (!currentCycleStartDate) {
          currentCycleStartDate = new Date(now); // Start cycle now
          lt_generations_today = 0;
          profileUpdates.subscription_cycle_start_date = currentCycleStartDate.toISOString();
          profileUpdates.generations_today = 0;
          needsDBUpdateBeforeDebit = true;
        }

        const nextMonthlyResetDate = new Date(currentCycleStartDate);
        nextMonthlyResetDate.setUTCMonth(currentCycleStartDate.getUTCMonth() + 1); // Go to next month
        // Preserve day of month from cycle start, handle month rollovers carefully if needed, e.g. Jan 31 -> Feb 28/29
        // For simplicity, using setUTCMonth, then setUTCDate to ensure it lands on the same day if possible, or last day of month.
        // A more robust way might be to add a fixed number of days (e.g. 30) or use a library.
        // For now, simple month increment.
        // Reset to the beginning of that day for consistency
        nextMonthlyResetDate.setUTCHours(0,0,0,0);

        if (now >= nextMonthlyResetDate) { // Monthly reset needed
          lt_generations_today = 0;
          currentCycleStartDate = new Date(now); // New cycle starts now
          profileUpdates.generations_today = 0;
          profileUpdates.subscription_cycle_start_date = currentCycleStartDate.toISOString();
          needsDBUpdateBeforeDebit = true;
        }
        // For client response, calculate the *actual* next reset after this potential update
        const finalCycleStartDateForNextReset = new Date(profileUpdates.subscription_cycle_start_date || currentCycleStartDate.toISOString());
        const actualNextMonthlyReset = new Date(finalCycleStartDateForNextReset);
        actualNextMonthlyReset.setUTCMonth(finalCycleStartDateForNextReset.getUTCMonth() + 1);
        actualNextMonthlyReset.setUTCHours(0,0,0,0);
        nextResetForClientIso = actualNextMonthlyReset.toISOString();
      }
    }
    
    // Daily Reset Logic (Only if not a monthly tier handled above)
    if (!isMonthlyTier) {
      derivedGenerationLimit = profile.generation_limit || DEFAULT_FREE_LIMIT; // Fallback to profile limit or default
      let performDailyReset = false;
      if (profile.last_generation_at) {
        const lastGenDateUtc = new Date(profile.last_generation_at);
        const nowDayStrUserTz = getDateStringInTimezone(now, userTimezone);
        const lastGenDayStrUserTz = getDateStringInTimezone(lastGenDateUtc, userTimezone);
        if (nowDayStrUserTz > lastGenDayStrUserTz) {
          performDailyReset = true;
        }
      } else {
        performDailyReset = true; // First generation or no last_generation_at
      }

      if (performDailyReset) {
        lt_generations_today = 0;
        profileUpdates.generations_today = 0;
        // For daily reset, we also update last_generation_at to mark the reset point for *this* logic
        // However, the main last_generation_at will be updated upon successful generation later.
        // Using a different field like 'daily_reset_marker_at' might be cleaner if needed.
        // For now, this update effectively resets the count for the new day.
        // profileUpdates.last_generation_at = now.toISOString(); // Let main debit handle last_generation_at
        needsDBUpdateBeforeDebit = true;
      }
      nextResetForClientIso = getNextUTCMidnightISO(); // Daily reset is next UTC midnight
    }

    // Perform DB Update if resets occurred
    if (needsDBUpdateBeforeDebit && Object.keys(profileUpdates).length > 0) {
      console.log(`User ${user.id}: Performing pre-debit profile update for cycle/daily reset:`, profileUpdates);
      const { error: resetUpdateError } = await supabaseClient
        .from("profiles")
        .update(profileUpdates)
        .eq("id", user.id);
      if (resetUpdateError) {
        console.error(`User ${user.id}: Failed to update profile on cycle/daily reset:`, resetUpdateError.message);
        // Non-fatal, proceed with locally reset counts, but log.
      }
    }

    // Limit Check (using lt_generations_today which reflects count after any resets)
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

    // --- Start of critical section: Debit, then attempt generation ---
    const generationsCountForDBDebit = lt_generations_today + 1;
    const timestampForThisAttempt = new Date().toISOString(); 

    console.log(`User ${user.id}: Attempting to debit generation. Current usage this period: ${lt_generations_today}, New count to set: ${generationsCountForDBDebit}`);
    const { data: debitedProfile, error: debitError } = await supabaseClient
      .from("profiles")
      .update({
        generations_today: generationsCountForDBDebit,
        last_generation_at: timestampForThisAttempt, 
      })
      .eq("id", user.id)
      .select('generations_today') // Select to confirm the update
      .single();

    if (debitError || !debitedProfile) {
      console.error(`Failed to debit generation count for user ${user.id}:`, debitError);
      return new Response(JSON.stringify({ error: "Failed to update generation credits. Please try again." }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 500,
      });
    }
    console.log(`User ${user.id}: Successfully debited. DB generations_today is now: ${debitedProfile.generations_today}. Last gen at: ${timestampForThisAttempt}`);
    const currentUsageAfterDebit = debitedProfile.generations_today;

    try {
      const body = await req.json();
      const { prompt, n = 1, size = "1024x1024" } = body;

      if (!prompt) {
        throw new Error("Prompt is required"); 
      }
      
      const openaiApiKey = Deno.env.get("OPENAI_API_KEY");
      if (!openaiApiKey) {
          console.error("OpenAI API key not set for generate-image-proxy.");
          throw new Error("OpenAI API key not configured.");
      }

      console.log(`User ${user.id} generating image with prompt (first 50 chars): ${prompt.substring(0,50)}`);
      const openaiResponse = await fetch("https://api.openai.com/v1/images/generations", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${openaiApiKey}`,
        },
        body: JSON.stringify({ model: "dall-e-3", prompt, n, size }),
      });

      const openaiData = await openaiResponse.json();

      if (!openaiResponse.ok) {
        console.error(`OpenAI API Error for user ${user.id}:`, openaiData);
        const openaiError = new Error(openaiData.error?.message || "OpenAI API request failed");
        (openaiError as any).openaiData = openaiData; 
        (openaiError as any).openaiStatus = openaiResponse.status;
        throw openaiError; // Re-throw to be caught by outer catch to trigger revert
      }
      
      // Generation successful
      return new Response(JSON.stringify(openaiData), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      });

    } catch (generationError) {
      // This catch is for errors during OpenAI call or if prompt was missing *after* debit
      console.error(`User ${user.id}: Error during/after OpenAI call (attempting to revert debit):`, generationError.message);
      
      // Revert the generation count
      const { error: revertError } = await supabaseClient
        .from("profiles")
        .update({ generations_today: lt_generations_today }) // Revert to count *before* this attempt's debit
        .eq("id", user.id);

      if (revertError) {
        console.error(`User ${user.id}: CRITICAL - Failed to revert generation count after OpenAI error:`, revertError.message);
        // The count is now wrong. This is a bad state.
      } else {
        console.log(`User ${user.id}: Successfully reverted generation count to ${lt_generations_today} after OpenAI error.`);
      }
      
      // Return the original generation error to the client
      const statusCode = generationError.openaiStatus || 500;
      return new Response(JSON.stringify({ error: generationError.message, details: generationError.openaiData }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: statusCode,
      });
    }

  } catch (error) {
    // This is for broader errors like auth, profile fetch, or unexpected issues
    console.error('General error in generate-image-proxy:', error);
    return new Response(JSON.stringify({ error: error.message || "An unexpected server error occurred." }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
}); 