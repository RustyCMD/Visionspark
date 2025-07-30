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
    const { prompt } = body;

    // Validate prompt
    if (!prompt || typeof prompt !== 'string' || prompt.trim().length === 0) {
      return new Response(JSON.stringify({ error: "Prompt is required and must be a non-empty string." }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }

    if (prompt.length > 2000) {
      return new Response(JSON.stringify({ error: "Prompt is too long. Maximum 2000 characters allowed." }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }

    const openaiApiKey = Deno.env.get("OPENAI_API_KEY");
    if (!openaiApiKey) {
      console.error("OpenAI API key not set for improve-prompt-proxy.");
      return new Response(JSON.stringify({ error: "Prompt improvement service not configured." }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 503,
      });
    }

    try {
      console.log(`User ${user.id} improving prompt (first 50 chars): ${prompt.substring(0, 50)}...`);
      
      const openaiResponse = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${openaiApiKey}`,
        },
        body: JSON.stringify({
          model: "gpt-4o-mini",
          messages: [
            {
              role: "system",
              content: "You are an expert at improving image generation prompts for DALL-E 3. Take the user's prompt and enhance it to be more descriptive, artistic, and likely to produce a high-quality image. Keep the core idea but add artistic details, style descriptions, lighting, composition, and other elements that make for better AI-generated images. It is crucial that you preserve any specific names, brands, or explicit details mentioned by the user in the original prompt. Be concise but descriptive. Return only the improved prompt without any explanations or quotes."
            },
            {
              role: "user",
              content: prompt.trim()
            }
          ],
          max_tokens: 500,
          temperature: 0.7,
        }),
      });

      const openaiData = await openaiResponse.json();

      if (!openaiResponse.ok) {
        console.error(`OpenAI API Error for user ${user.id} (Status: ${openaiResponse.status}):`, openaiData);
        return new Response(JSON.stringify({ 
          error: openaiData.error?.message || "Failed to improve prompt", 
          details: openaiData.error 
        }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: openaiResponse.status,
        });
      }

      const improvedPrompt = openaiData.choices?.[0]?.message?.content?.trim();
      
      if (!improvedPrompt) {
        console.error(`No improved prompt returned from OpenAI for user ${user.id}`);
        return new Response(JSON.stringify({ error: "Failed to generate improved prompt" }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 500,
        });
      }

      console.log(`User ${user.id}: Successfully improved prompt`);
      
      return new Response(JSON.stringify({
        improved_prompt: improvedPrompt
      }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      });

    } catch (apiError) {
      console.error(`User ${user.id}: Network or parsing error during OpenAI interaction:`, apiError.message);
      return new Response(JSON.stringify({ 
        error: "Prompt improvement service currently unavailable. Please try again later.",
        details: apiError.message 
      }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 503,
      });
    }

  } catch (error) {
    console.error('General error in improve-prompt-proxy:', error.message, error.stack);
    return new Response(JSON.stringify({ error: error.message || "An unexpected server error occurred." }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
});