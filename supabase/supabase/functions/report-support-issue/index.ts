import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
// import { corsHeaders } from "../_shared/cors.ts"; // Removed

// Inlined corsHeaders
const corsHeaders = {
  "Access-Control-Allow-Origin": "*", 
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const RATE_LIMIT_SECONDS = 30; // Allow one request per 30 seconds
const WEBHOOK_IDENTIFIER = "discord_support_webhook";

async function sendToDiscord(webhookUrl: string, embed: any) {
  const payload = { embeds: [embed] };
  const res = await fetch(webhookUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  return res.ok;
}

function buildEmbed({ title, content, email }: { title: string, content: string, email: string }) {
  return {
    title: `🛠️ ${title}`,
    description: content,
    color: 0xC8A2C8, // Lilac purple
    fields: [
      { name: "User Email", value: email, inline: false }
    ],
    footer: { text: "Visionspark Support" },
    timestamp: new Date().toISOString(),
  };
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Initialize Supabase client with service role for DB operations
  // Ensure SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are set in Edge Function environment variables
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !supabaseServiceRoleKey) {
    console.error("SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY not set.");
    return new Response(JSON.stringify({ error: "Server configuration error." }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const supabaseAdminClient: SupabaseClient = createClient(supabaseUrl, supabaseServiceRoleKey);

  try {
    // Auth check (using the request's Authorization header for the user)
    const authHeader = req.headers.get("authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Unauthorized: Missing or invalid token" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    // We don't need to validate the user token here if the primary goal is just to get an email.
    // The main rate limiting is not per-user but global for the webhook.

    const discordWebhookUrl = Deno.env.get("DISCORD_WEBHOOK");
    if (!discordWebhookUrl) {
      console.error("DISCORD_WEBHOOK environment variable not set.");
      return new Response(JSON.stringify({ error: "Discord webhook not configured" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Check rate limit
    const { data: rateLimitData, error: rateLimitError } = await supabaseAdminClient
      .from("webhook_rate_limits")
      .select("last_sent_at")
      .eq("webhook_identifier", WEBHOOK_IDENTIFIER)
      .single();

    if (rateLimitError && rateLimitError.code !== 'PGRST116') { // PGRST116: 'exact-single-row' error when no row found
      console.error("Error fetching rate limit:", rateLimitError);
      // Allow proceeding if error is just "not found", otherwise block
        return new Response(JSON.stringify({ error: "Error checking rate limit status." }), {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
    }
    
    if (rateLimitData && rateLimitData.last_sent_at) {
      const lastSentTime = new Date(rateLimitData.last_sent_at).getTime();
      const now = Date.now();
      const secondsSinceLastSent = (now - lastSentTime) / 1000;

      if (secondsSinceLastSent < RATE_LIMIT_SECONDS) {
        console.warn(`Rate limit hit for ${WEBHOOK_IDENTIFIER}. Last sent ${secondsSinceLastSent.toFixed(1)}s ago.`);
        return new Response(
          JSON.stringify({ error: `Too many requests. Please try again in ${Math.ceil(RATE_LIMIT_SECONDS - secondsSinceLastSent)} seconds.` }),
          { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    // Parse body
    const body = await req.json();
    const { title, content, email } = body;
    if (!title || !content || !email) {
      return new Response(JSON.stringify({ error: "Missing title, content, or email" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const embed = buildEmbed({ title, content, email });
    let discordSuccess = false;

    try {
      console.log(`Attempting to send to Discord for ${WEBHOOK_IDENTIFIER}`);
      discordSuccess = await sendToDiscord(discordWebhookUrl, embed);
    } catch (discordError) {
      console.error(`Error sending to Discord for ${WEBHOOK_IDENTIFIER}:`, discordError);
      // Still update rate limit even if Discord send fails, to prevent spamming a broken webhook
    } finally {
      // Update last_sent_at timestamp regardless of Discord send success/failure
      const { error: upsertError } = await supabaseAdminClient
        .from("webhook_rate_limits")
        .upsert({
          webhook_identifier: WEBHOOK_IDENTIFIER,
          last_sent_at: new Date().toISOString(),
        }, { onConflict: 'webhook_identifier' });

      if (upsertError) {
        console.error("CRITICAL: Failed to update rate limit timestamp for ", WEBHOOK_IDENTIFIER, upsertError);
        // This is a server-side issue, but the user's request might have gone through or not.
      } else {
        console.log(`Rate limit timestamp updated for ${WEBHOOK_IDENTIFIER}.`);
      }
    }

    if (discordSuccess) {
      return new Response(JSON.stringify({ success: true, message: "Report submitted." }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    } else {
      return new Response(JSON.stringify({ error: "Failed to send report to Discord. Please try again later." }), {
        status: 502, // Bad Gateway, as our server failed to communicate with Discord
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

  } catch (e) {
    console.error("General error in report-support-issue:", e.message, e.stack ? e.stack : '');
    return new Response(JSON.stringify({ error: e.message || "Unknown server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});