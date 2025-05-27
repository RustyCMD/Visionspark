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
      const newLastGenerationAt = new Date().toISOString(); // Reset time to now
      const { error: resetError } = await supabaseClient
        .from("profiles")
        .update({ generations_today: 0, last_generation_at: newLastGenerationAt })
        .eq("id", user.id);
      
      if (resetError) {
        console.error(`Error resetting generation count for user ${user.id}:`, resetError);
        // Non-fatal for this operation, proceed with current count but log it.
        // The limit check below will use the potentially stale generations_today.
      } else {
        // Successfully reset, so update local last_generation_at if it's used later
        last_generation_at = newLastGenerationAt;
        console.log(`Successfully reset generations_today to 0 and updated last_generation_at for user ${user.id}`);
      }
    }

    if (generations_today >= DAILY_LIMIT) {
      // Calculate next reset time based on user's timezone if available, otherwise UTC
      // let nextResetDate; // This was unused, removed
      // const currentHour = parseInt(now.toLocaleTimeString('en-GB', { timeZone: userTimezone, hour: '2-digit', hour12: false }), 10); // Unused
      // const currentMinute = parseInt(now.toLocaleTimeString('en-GB', { timeZone: userTimezone, minute: '2-digit'}), 10); // Unused
      
      // Create a date object for today in the user's timezone - These were unused
      // const year = parseInt(now.toLocaleDateString('en-CA', { timeZone: userTimezone, year: 'numeric' }));
      // const month = parseInt(now.toLocaleDateString('en-CA', { timeZone: userTimezone, month: '2-digit' })) -1; // Month is 0-indexed
      // const day = parseInt(now.toLocaleDateString('en-CA', { timeZone: userTimezone, day: '2-digit' }));

      // This is a bit tricky due to JS Date handling of timezones.
      // The goal is midnight *in the user's timezone*, then convert that to a UTC ISO string.
      // For simplicity here, we'll stick to UTC midnight for the 'resets_at_utc_iso' field.
      // The client-side display should use the 'get-generation-status' logic.
      const nextUTCMidnight = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1));
      
      console.log(`Daily limit reached for user ${user.id}. Generations: ${generations_today}`);
      return new Response(
        JSON.stringify({ 
            error: "Daily generation limit reached.",
            // Kept nextUTCMidnight as the primary reset indicator for consistency with previous versions.
            // The client should rely on 'get-generation-status' for precise user-timezone reset display.
            resets_at_utc_iso: nextUTCMidnight.toISOString(),
            timezone_used: userTimezone // Inform client which timezone was considered
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 429 }
      );
    }

    // Proceed with generation
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
        console.error("OpenAI API key not set in Edge Function secrets for generate-image-proxy.");
        return new Response(JSON.stringify({ error: "OpenAI API key not configured." }), {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
            status: 500,
        });
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
      return new Response(JSON.stringify(openaiData), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: openaiResponse.status,
      });
    }

    // If successful, update the user's profile
    const newGenerationCount = generations_today + 1;
    const newLastGenAt = new Date().toISOString();

    const { error: updateError } = await supabaseClient
      .from("profiles")
      .update({ 
        generations_today: newGenerationCount, 
        last_generation_at: newLastGenAt
      })
      .eq("id", user.id);

    if (updateError) {
      console.error(`Error updating profile for user ${user.id} after generation:`, updateError);
      // Log error, but still return image to user as generation was successful
    } else {
      console.log(`Successfully updated profile for user ${user.id}. New count: ${newGenerationCount}, Last gen: ${newLastGenAt}`);
    }

    return new Response(JSON.stringify(openaiData), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });

  } catch (e) {
    console.error("General error in generate-image-proxy:", e.message, e.stack ? e.stack : '');
    return new Response(JSON.stringify({ error: e.message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
}); 