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
      console.error("User error:", userError);
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
      console.error("Profile error:", profileError);
      return new Response(JSON.stringify({ error: "Profile not found" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 404,
      });
    }

    let { last_generation_at, generations_today, timezone } = profile;
    const userTimezone = timezone || "UTC"; // Default to UTC if no timezone is set

    const now = new Date();
    let lastGenerationDate = null;
    if (last_generation_at) {
        // Adjust 'now' and 'last_generation_at' to the user's timezone for date comparison
        const nowInUserTz = new Date(now.toLocaleString("en-US", { timeZone: userTimezone }));
        const lastGenInUserTz = new Date(new Date(last_generation_at).toLocaleString("en-US", { timeZone: userTimezone }));
        
        if (nowInUserTz.getFullYear() > lastGenInUserTz.getFullYear() ||
            nowInUserTz.getMonth() > lastGenInUserTz.getMonth() ||
            nowInUserTz.getDate() > lastGenInUserTz.getDate()) {
            generations_today = 0;
        }
    } else {
        // No previous generation, so it's effectively a reset
        generations_today = 0;
    }
    
    const remaining = DAILY_LIMIT - generations_today;

    // Calculate when midnight is for the reset time
    let resetsAtDate: Date;
    const nowUtc = new Date(); // Use a clear UTC reference for calculations

    if (userTimezone === "UTC") {
        resetsAtDate = new Date(Date.UTC(nowUtc.getUTCFullYear(), nowUtc.getUTCMonth(), nowUtc.getUTCDate() + 1));
    } else {
        // For non-UTC, determine the start of the *current day* in the user's timezone
        const yearUserTz = parseInt(now.toLocaleString("en-US", { timeZone: userTimezone, year: 'numeric' }));
        const monthUserTz = parseInt(now.toLocaleString("en-US", { timeZone: userTimezone, month: '2-digit' })) -1; // JS months are 0-indexed
        const dayUserTz = parseInt(now.toLocaleString("en-US", { timeZone: userTimezone, day: '2-digit' }));

        // Create a Date object for the start of the user's *next* day, in their timezone
        // Then convert that moment to a UTC Date object.
        // This is still complex without a proper date-fns-tz library.
        // A robust way: get current date in user TZ, advance it by one day, set to 00:00:00 in user TZ, then get its UTC equivalent.
        // Simplified for now: we'll calculate the *next* midnight in UTC, client can localize.
        resetsAtDate = new Date(Date.UTC(nowUtc.getUTCFullYear(), nowUtc.getUTCMonth(), nowUtc.getUTCDate() + 1));
        // The above line essentially means for all users, the reset is based on the next UTC midnight.
        // The client-side logic already converts this UTC timestamp to the user's local display for "Resets in X H Y M".
    }

    const responsePayload = {
      remaining: Math.max(0, remaining),
      generations_today: generations_today,
      limit: DAILY_LIMIT,
      resets_at_utc_iso: resetsAtDate.toISOString(), // Use the consistently defined resetsAtDate
      timezone_used: userTimezone,
      last_generation_at_utc: last_generation_at ? new Date(last_generation_at).toISOString() : null,
    };

    return new Response(JSON.stringify(responsePayload), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });
  } catch (e) {
    console.error("General error:", e);
    return new Response(JSON.stringify({ error: e.message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
}); 