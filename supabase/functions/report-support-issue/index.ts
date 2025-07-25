import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

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

    const body = await req.json();
    const { title, content, email } = body;

    // Validate inputs
    if (!title || typeof title !== 'string' || title.trim().length === 0) {
      return new Response(JSON.stringify({ error: "Title is required and must be a non-empty string." }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }

    if (!content || typeof content !== 'string' || content.trim().length < 10) {
      return new Response(JSON.stringify({ error: "Content is required and must be at least 10 characters." }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }

    if (!email || typeof email !== 'string' || !email.includes('@')) {
      return new Response(JSON.stringify({ error: "Valid email is required." }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }

    if (title.length > 200) {
      return new Response(JSON.stringify({ error: "Title must be 200 characters or less." }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }

    if (content.length > 5000) {
      return new Response(JSON.stringify({ error: "Content must be 5000 characters or less." }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }

    try {
      // Create a service role client to insert support tickets
      const serviceRoleClient = createClient(
        Deno.env.get("SUPABASE_URL") ?? "",
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
      );

      // Insert support ticket into database
      const { error: insertError } = await serviceRoleClient
        .from('support_tickets')
        .insert({
          user_id: user.id,
          user_email: email.trim(),
          title: title.trim(),
          content: content.trim(),
          status: 'open',
          created_at: new Date().toISOString()
        });

      if (insertError) {
        console.error(`Failed to insert support ticket for user ${user.id}:`, insertError);
        
        // If table doesn't exist, log to console as fallback
        if (insertError.code === '42P01') { // Table doesn't exist
          console.log(`SUPPORT TICKET (Table not found - logging to console):
User ID: ${user.id}
Email: ${email}
Title: ${title}
Content: ${content}
Timestamp: ${new Date().toISOString()}`);

          // Still try to send Discord notification even if database fails
          await sendDiscordNotification(serviceRoleClient, user.id, email, title, content);

          return new Response(JSON.stringify({
            success: true,
            message: "Support ticket submitted successfully."
          }), {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
            status: 200,
          });
        } else {
          throw new Error(`Database error: ${insertError.message}`);
        }
      }

      console.log(`Support ticket created for user ${user.id}, title: ${title.substring(0, 50)}...`);

      // Send Discord notification if webhook URL is configured
      await sendDiscordNotification(serviceRoleClient, user.id, email, title, content);

      return new Response(JSON.stringify({
        success: true,
        message: "Support ticket submitted successfully. Our team will review it shortly."
      }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      });

    } catch (dbError) {
      console.error(`User ${user.id}: Database error during support ticket creation:`, dbError.message);

      // Fallback: Log to console if database fails
      console.log(`SUPPORT TICKET (Database failed - logging to console):
User ID: ${user.id}
Email: ${email}
Title: ${title}
Content: ${content}
Timestamp: ${new Date().toISOString()}
Error: ${dbError.message}`);

      // Still try to send Discord notification even if database fails
      try {
        const fallbackClient = createClient(
          Deno.env.get("SUPABASE_URL") ?? "",
          Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
        );
        await sendDiscordNotification(fallbackClient, user.id, email, title, content);
      } catch (discordError) {
        console.error("Failed to send Discord notification in fallback:", discordError.message);
      }

      return new Response(JSON.stringify({
        success: true,
        message: "Support ticket submitted successfully."
      }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      });
    }

  } catch (error) {
    console.error('General error in report-support-issue:', error.message, error.stack);
    return new Response(JSON.stringify({
      error: error.message || "An unexpected server error occurred."
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
});

async function sendDiscordNotification(supabaseClient: any, userId: string, email: string, title: string, content: string) {
  const discordWebhookUrl = Deno.env.get("DISCORD_WEBHOOK");

  if (!discordWebhookUrl) {
    console.log("Discord webhook URL not configured, skipping Discord notification");
    return;
  }

  try {
    // Check rate limiting (max 1 notification per minute for support tickets)
    const webhookId = "discord_support_webhook";
    const now = new Date();
    const oneMinuteAgo = new Date(now.getTime() - 60 * 1000);

    const { data: rateLimitData } = await supabaseClient
      .from('webhook_rate_limits')
      .select('last_sent_at')
      .eq('webhook_identifier', webhookId)
      .single();

    if (rateLimitData && new Date(rateLimitData.last_sent_at) > oneMinuteAgo) {
      console.log("Discord webhook rate limited, skipping notification");
      return;
    }

    // Create Discord embed
    const embed = {
      title: "🎫 New Support Ticket",
      color: 0x3498db, // Blue color
      fields: [
        {
          name: "📧 User Email",
          value: email,
          inline: true
        },
        {
          name: "🆔 User ID",
          value: userId,
          inline: true
        },
        {
          name: "📝 Subject",
          value: title.length > 256 ? title.substring(0, 253) + "..." : title,
          inline: false
        },
        {
          name: "💬 Message",
          value: content.length > 1024 ? content.substring(0, 1021) + "..." : content,
          inline: false
        }
      ],
      timestamp: now.toISOString(),
      footer: {
        text: "VisionSpark Support System"
      }
    };

    const discordPayload = {
      embeds: [embed]
    };

    // Send to Discord
    const discordResponse = await fetch(discordWebhookUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(discordPayload),
    });

    if (discordResponse.ok) {
      console.log("Discord notification sent successfully");

      // Update rate limit record
      await supabaseClient
        .from('webhook_rate_limits')
        .upsert({
          webhook_identifier: webhookId,
          last_sent_at: now.toISOString()
        });
    } else {
      const errorText = await discordResponse.text();
      console.error("Failed to send Discord notification:", discordResponse.status, errorText);
    }
  } catch (error) {
    console.error("Error sending Discord notification:", error.message);
  }
}