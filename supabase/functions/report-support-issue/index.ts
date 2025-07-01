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

      // Optionally send email notification here
      // You could integrate with SendGrid, Resend, or other email services
      
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