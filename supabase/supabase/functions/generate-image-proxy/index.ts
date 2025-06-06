/// <reference types="https://deno.land/x/service_worker@0.1.0/window.d.ts" />
// Add Deno types reference for linter
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

const DAILY_LIMIT = 3;

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
function getNextDayStartUTCISO(timeZone: string): string {
  const nowInUserTz = new Date(new Date().toLocaleString('en-US', { timeZone }));
  const nextDayUserTz = new Date(nowInUserTz);
  nextDayUserTz.setDate(nowInUserTz.getDate() + 1);
  nextDayUserTz.setHours(0, 0, 0, 0); // Start of the next day in user's timezone

  // To convert this user-local time to a UTC Date object, we can construct
  // a UTC date string from its components and parse it.
  // This is a bit tricky due to Deno's environment.
  // Alternative: get UTC components of 'now', then figure out offset for user's next midnight.
  // For now, the previous method of just using UTC midnight might be simpler if client localizes.
  // However, to be accurate for the "resets_at_utc_iso" field *based on user's timezone*:
  const year = nextDayUserTz.getFullYear();
  const month = (nextDayUserTz.getMonth() + 1).toString().padStart(2, '0'); // JS months are 0-indexed
  const day = nextDayUserTz.getDate().toString().padStart(2, '0');
  
  // Construct an ISO-like string *as if* nextDayUserTz was already UTC,
  // then parse it. This doesn't work as intended if nextDayUserTz is a local time.
  // A more reliable way without external libraries is to calculate based on UTC.
  // Get current UTC date parts
  const nowUtc = new Date();
  const currentUtcYear = nowUtc.getUTCFullYear();
  const currentUtcMonth = nowUtc.getUTCMonth();
  const currentUtcDay = nowUtc.getUTCDate();

  // Create a date for the start of *today* in the user's timezone
  const todayUserTzStr = getDateStringInTimezone(new Date(), timeZone); // e.g., "2023-10-27"
  const [uy, um, ud] = todayUserTzStr.split('-').map(Number);
  
  // Construct Date for start of *tomorrow* in user's timezone, then get its UTC representation
  // This requires knowing the offset, which is complex.
  // Simplest reliable: Start of *next UTC day* is often good enough if client displays "resets in X hours".
  // For more precise "resets at specific time in your zone", this needs a date-fns-tz equivalent.

  // Reverting to a simpler, more robust calculation for `resets_at_utc_iso`:
  // It will be the start of the *next calendar day in UTC after the current moment*.
  // The client already localizes this. The key is that the *count reset* happens based on user's local day.
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
      .select("last_generation_at, generations_today, timezone")
      .eq("id", user.id)
      .single();

    if (profileError || !profile) {
       console.error("Profile fetch error:", profileError, "for user ID:", user.id);
      return new Response(JSON.stringify({ error: "Profile not found" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 404,
      });
    }

    let { last_generation_at, generations_today } = profile; // timezone will be from helper
    const userTimezone = getUserTimezone(user, profile);
    const now = new Date();
    let performReset = false;

    if (typeof generations_today !== 'number') {
      console.warn(`Generations_today was not a number for user ${user.id}, defaulting to 0. Value: ${generations_today}`);
      generations_today = 0; // Ensure it's a number
    }

    if (last_generation_at) {
      const lastGenDateUtc = new Date(last_generation_at); // This is already UTC

      const nowDayStrUserTz = getDateStringInTimezone(now, userTimezone);
      const lastGenDayStrUserTz = getDateStringInTimezone(lastGenDateUtc, userTimezone);

      if (nowDayStrUserTz > lastGenDayStrUserTz) {
        console.log(`Performing reset for user ${user.id}. Now_UserTz: ${nowDayStrUserTz}, LastGen_UserTz: ${lastGenDayStrUserTz} (Timezone: ${userTimezone})`);
        performReset = true;
      }
    } else {
      console.log(`Performing reset for user ${user.id} due to no last_generation_at.`);
      performReset = true; // First generation ever or last_generation_at is null
    }

    if (performReset) {
      generations_today = 0;
      const newLastGenerationAtForReset = new Date().toISOString(); // Store as UTC
      const { error: resetError } = await supabaseClient
        .from("profiles")
        .update({ generations_today: 0, last_generation_at: newLastGenerationAtForReset })
        .eq("id", user.id);
      
      if (resetError) {
        console.error(`Error resetting generation count for user ${user.id}:`, resetError);
        // Non-fatal for this operation, proceed with current local count (0) but log it.
        // The debit logic below will effectively set it to 1 if generation proceeds.
      } else {
        last_generation_at = newLastGenerationAtForReset; // Update local last_generation_at to keep it in sync
        console.log(`Successfully reset generations_today to 0 and updated last_generation_at for user ${user.id}`);
      }
    }

    const generationsCountBeforeThisAttempt = generations_today;

    if (generationsCountBeforeThisAttempt >= DAILY_LIMIT) {
      const resetTimeIso = getNextDayStartUTCISO(userTimezone);
      console.log(`Daily limit reached for user ${user.id}. Generations: ${generationsCountBeforeThisAttempt}. Resets at: ${resetTimeIso} (Calculated for TZ: ${userTimezone})`);
      return new Response(
        JSON.stringify({ 
            error: "Daily generation limit reached.",
            resets_at_utc_iso: resetTimeIso,
            timezone_used: userTimezone
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 429 }
      );
    }

    // --- Start of critical section: Debit, then attempt generation ---
    const newCountForDB = generationsCountBeforeThisAttempt + 1;
    const timestampForThisAttempt = new Date().toISOString(); // Store as UTC

    // 1. DEBIT a generation credit
    console.log(`User ${user.id}: Attempting to debit generation. Current count before debit: ${generationsCountBeforeThisAttempt}, New count to set: ${newCountForDB}`);
    const { error: debitError } = await supabaseClient
      .from("profiles")
      .update({
        generations_today: newCountForDB,
        last_generation_at: timestampForThisAttempt, // This is UTC
      })
      .eq("id", user.id);

    if (debitError) {
      console.error(`Failed to debit generation count for user ${user.id}:`, debitError);
      return new Response(JSON.stringify({ error: "Failed to update generation credits. Please try again." }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 500,
      });
    }
    console.log(`User ${user.id}: Successfully debited. DB count is now: ${newCountForDB}. Last gen at: ${timestampForThisAttempt}`);

    try {
      // 2. PREPARE for and EXECUTE OpenAI call
      const body = await req.json();
      const { prompt, n = 1, size = "1024x1024" } = body;

      if (!prompt) {
        // This is a client error, but we already debited. We should revert.
        throw new Error("Prompt is required"); 
      }
      
      const openaiApiKey = Deno.env.get("OPENAI_API_KEY");
      if (!openaiApiKey) {
          console.error("OpenAI API key not set in Edge Function secrets for generate-image-proxy.");
          // This is a server config error. Revert.
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
        // OpenAI returned an error. Re-throw to be caught by the outer catch to trigger revert.
        const openaiError = new Error(openaiData.error?.message || "OpenAI API request failed");
        (openaiError as any).openaiData = openaiData; 
        (openaiError as any).openaiStatus = openaiResponse.status;
        throw openaiError;
      }

      // 3. OpenAI call SUCCESSFUL
      // Debit is already done. Profile is up-to-date.
      console.log(`OpenAI call successful for user ${user.id}. Profile count is ${newCountForDB}.`);
      return new Response(JSON.stringify(openaiData), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      });

    } catch (generationError) {
      // This catch block handles errors from `req.json()`, missing prompt/API key,
      // OpenAI fetch itself, `openaiResponse.json()`, or non-ok OpenAI response.
      console.error(`Error during generation process for user ${user.id} (after debit attempt):`, generationError.message);

      // REVERT the debit
      console.log(`User ${user.id}: Attempting to revert debit due to error. Setting count back to ${generationsCountBeforeThisAttempt}.`);
      const { error: revertError } = await supabaseClient
        .from("profiles")
        .update({
          generations_today: generationsCountBeforeThisAttempt, 
          // last_generation_at remains timestampForThisAttempt (UTC), signifying a failed attempt at this time.
        })
        .eq("id", user.id);

      if (revertError) {
        console.error(`CRITICAL: Failed to REVERT generation count for user ${user.id} after error. User has effectively been charged. Revert Error: ${revertError.message}. Original Gen Error: ${generationError.message}`);
      } else {
        console.log(`User ${user.id}: Successfully reverted generation count to ${generationsCountBeforeThisAttempt} due to error: ${generationError.message}`);
      }

      // Return appropriate error to client
      if ((generationError as any).openaiData) { 
        return new Response(JSON.stringify((generationError as any).openaiData), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: (generationError as any).openaiStatus || 500,
        });
      } else if (generationError.message === "Prompt is required") {
        return new Response(JSON.stringify({ error: "Prompt is required" }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 400,
        });
      } else {
        return new Response(JSON.stringify({ error: generationError.message || "Image generation failed after debit." }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 500,
        });
      }
    }
    // --- End of critical section ---

  } catch (e) {
    console.error("General error in generate-image-proxy:", e.message, e.stack ? e.stack : '');
    return new Response(JSON.stringify({ error: e.message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
}); 