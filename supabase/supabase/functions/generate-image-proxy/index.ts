import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

const DAILY_LIMIT = 3;

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

    let { last_generation_at, generations_today, timezone } = profile;
    const userTimezone = timezone || "UTC"; // Default to UTC if no timezone is set
    const now = new Date();
    let performReset = false;

    if (typeof generations_today !== 'number') {
      console.warn(`Generations_today was not a number for user ${user.id}, defaulting to 0. Value: ${generations_today}`);
      generations_today = 0; // Ensure it's a number
    }

    if (last_generation_at) {
      const lastGenDate = new Date(last_generation_at);

      // Get YYYY-MM-DD string for 'now' in user's timezone. 'en-CA' gives 'YYYY-MM-DD'.
      const nowDayStr = now.toLocaleDateString('en-CA', { timeZone: userTimezone, year: 'numeric', month: '2-digit', day: '2-digit' });
      
      // Get YYYY-MM-DD string for 'last_generation_at' in user's timezone.
      const lastGenDayStr = lastGenDate.toLocaleDateString('en-CA', { timeZone: userTimezone, year: 'numeric', month: '2-digit', day: '2-digit' });

      if (nowDayStr > lastGenDayStr) {
        console.log(`Performing reset for user ${user.id}. Now: ${nowDayStr} (${userTimezone}), Last Gen: ${lastGenDayStr} (${userTimezone})`);
            performReset = true;
        }
    } else {
      console.log(`Performing reset for user ${user.id} due to no last_generation_at.`);
      performReset = true; // First generation ever or last_generation_at is null
    }

    if (performReset) {
      generations_today = 0;
      const newLastGenerationAtForReset = new Date().toISOString();
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
      const nextUTCMidnight = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1));
      console.log(`Daily limit reached for user ${user.id}. Generations: ${generationsCountBeforeThisAttempt}`);
      return new Response(
        JSON.stringify({ 
            error: "Daily generation limit reached.",
            resets_at_utc_iso: nextUTCMidnight.toISOString(),
            timezone_used: userTimezone
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 429 }
      );
    }

    // --- Start of critical section: Debit, then attempt generation ---
    const newCountForDB = generationsCountBeforeThisAttempt + 1;
    const timestampForThisAttempt = new Date().toISOString();

    // 1. DEBIT a generation credit
    console.log(`User ${user.id}: Attempting to debit generation. Current count before debit: ${generationsCountBeforeThisAttempt}, New count to set: ${newCountForDB}`);
    const { error: debitError } = await supabaseClient
      .from("profiles")
      .update({
        generations_today: newCountForDB,
        last_generation_at: timestampForThisAttempt,
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
          // last_generation_at remains timestampForThisAttempt, signifying a failed attempt at this time.
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