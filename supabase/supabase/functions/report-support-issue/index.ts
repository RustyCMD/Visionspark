import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { corsHeaders } from "../_shared/cors.ts";

// In-memory queue and timer (stateless, resets on function restart)
let queue: any[] = [];
let isSending = false;
let lastSentAt = 0;

async function sendToDiscord(webhook: string, embed: any) {
  const payload = {
    embeds: [embed],
  };
  const res = await fetch(webhook, {
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

async function processQueue(webhook: string) {
  if (isSending || queue.length === 0) return;
  isSending = true;
  while (queue.length > 0) {
    const now = Date.now();
    const sinceLast = now - lastSentAt;
    if (sinceLast < 30000) {
      await new Promise((r) => setTimeout(r, 30000 - sinceLast));
    }
    const { embed, resolve, reject } = queue.shift();
    try {
      const ok = await sendToDiscord(webhook, embed);
      lastSentAt = Date.now();
      if (ok) resolve();
      else reject("Failed to send to Discord");
    } catch (e) {
      reject("Error sending to Discord: " + e);
    }
  }
  isSending = false;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Auth check
    const authHeader = req.headers.get("authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Get Discord webhook from secrets
    const webhook = Deno.env.get("DISCORD_WEBHOOK");
    if (!webhook) {
      return new Response(JSON.stringify({ error: "Discord webhook not configured" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
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

    // Queue limit (max 10)
    if (queue.length >= 10) {
      return new Response(JSON.stringify({ error: "Support queue is full, please try again in a few minutes." }), {
        status: 429,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Build embed
    const embed = buildEmbed({ title, content, email });

    // Queue the message and return a promise
    const promise = new Promise<void>((resolve, reject) => {
      queue.push({ embed, resolve, reject });
    });

    // Start processing if not already
    processQueue(webhook);

    // Wait for the message to be sent (or fail)
    await promise;

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: e.message || "Unknown error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});