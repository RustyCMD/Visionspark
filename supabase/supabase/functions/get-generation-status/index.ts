import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Inlined corsHeaders
const corsHeaders = {
  "Access-Control-Allow-Origin": "*", 
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const DAILY_LIMIT = 3;

// Helper function to safely get the user's timezone
function getUserTimezone(user: any, profile: any): string {
  if (user?.user_metadata?.timezone) {
    try {
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

    let { last_generation_at, generations_today } = profile; // timezone from helper
    const userTimezone = getUserTimezone(user, profile);

    const now = new Date();
    // let lastGenerationDate = null; // This variable is not used later
    
    if (typeof generations_today !== 'number') {
        console.warn(`Generations_today was not a number for user ${user.id}, defaulting to 0. Value: ${generations_today}`);
        generations_today = 0;
    }

    if (last_generation_at) {
        const lastGenDateUtc = new Date(last_generation_at); // This is already UTC

        const nowDayStrUserTz = getDateStringInTimezone(now, userTimezone);
        const lastGenDayStrUserTz = getDateStringInTimezone(lastGenDateUtc, userTimezone);
        
        if (nowDayStrUserTz > lastGenDayStrUserTz) {
            console.log(`User ${user.id} (get-status): Day has passed. Now_UserTz: ${nowDayStrUserTz}, LastGen_UserTz: ${lastGenDayStrUserTz}. Resetting count for status.`);
            generations_today = 0;
        }
    } else {
        // No previous generation, so it's effectively a reset for status purposes
        console.log(`User ${user.id} (get-status): No last_generation_at. Resetting count for status.`);
        generations_today = 0;
    }
    
    const remaining = DAILY_LIMIT - generations_today;
    const resetsAtIso = getNextDayStartUTCISO(userTimezone);

    const responsePayload = {
      remaining: Math.max(0, remaining),
      generations_today: generations_today,
      limit: DAILY_LIMIT,
      resets_at_utc_iso: resetsAtIso,
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