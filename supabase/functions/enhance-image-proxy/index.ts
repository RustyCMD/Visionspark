import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.5.0";
import { corsHeaders } from "../_shared/cors.ts";

interface EnhanceImageRequest {
  image: string;  // base64 encoded image
  prompt: string;
  mode?: 'enhance' | 'edit' | 'variation';
  strength?: number;  // 0.1 to 1.0
}

interface OpenAIImageEditResponse {
  data: Array<{
    url: string;
  }>;
}

serve(async (req: Request) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Get the authorization header
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing Authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Initialize Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Verify the JWT token and get user
    const jwt = authHeader.replace('Bearer ', '');
    const { data: { user }, error: authError } = await supabase.auth.getUser(jwt);

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid or expired token' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Check user's generation status and limits
    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .select('generation_limit, generations_today, cycle_start_date')
      .eq('id', user.id)
      .single();

    if (profileError) {
      return new Response(
        JSON.stringify({ error: 'Failed to fetch user profile' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Check if user has reached their limit
    if (profile.generation_limit !== -1 && profile.generations_today >= profile.generation_limit) {
      return new Response(
        JSON.stringify({ error: 'Generation limit reached for today' }),
        { status: 429, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Parse request body
    const body: EnhanceImageRequest = await req.json();
    
    // Validate required fields
    if (!body.image || !body.prompt) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields: image and prompt' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Validate prompt length
    if (body.prompt.length > 1000) {
      return new Response(
        JSON.stringify({ error: 'Prompt too long (max 1000 characters)' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Set defaults
    const mode = body.mode || 'enhance';
    const strength = body.strength || 0.7;

    // Validate strength parameter
    if (strength < 0.1 || strength > 1.0) {
      return new Response(
        JSON.stringify({ error: 'Strength must be between 0.1 and 1.0' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Get OpenAI API key
    const openaiApiKey = Deno.env.get('OPENAI_API_KEY');
    if (!openaiApiKey) {
      return new Response(
        JSON.stringify({ error: 'OpenAI API key not configured' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Convert base64 to blob for OpenAI API
    const imageBuffer = Uint8Array.from(atob(body.image), c => c.charCodeAt(0));
    const imageBlob = new Blob([imageBuffer], { type: 'image/png' });

    // Prepare form data for OpenAI API
    const formData = new FormData();
    formData.append('image', imageBlob, 'image.png');
    formData.append('prompt', body.prompt);
    formData.append('n', '1');
    formData.append('size', '1024x1024');
    
    // For DALL-E 2, we use different endpoints based on mode
    let openaiEndpoint = '';

    switch (mode) {
      case 'edit':
        openaiEndpoint = 'https://api.openai.com/v1/images/edits';
        // Create a proper mask (white image with same dimensions for full image editing)
        const canvas = new OffscreenCanvas(1024, 1024);
        const ctx = canvas.getContext('2d');
        if (ctx) {
          ctx.fillStyle = 'white';
          ctx.fillRect(0, 0, 1024, 1024);
        }
        const maskBlob = await canvas.convertToBlob({ type: 'image/png' });
        formData.append('mask', maskBlob, 'mask.png');
        break;
      case 'variation':
        openaiEndpoint = 'https://api.openai.com/v1/images/variations';
        // Remove prompt for variations as it's not supported
        formData.delete('prompt');
        break;
      case 'enhance':
      default:
        // For enhance mode, use variations endpoint for better results
        openaiEndpoint = 'https://api.openai.com/v1/images/variations';
        // Remove prompt for variations as it's not supported
        formData.delete('prompt');
        break;
    }

    // Make request to OpenAI API
    const openaiResponse = await fetch(openaiEndpoint, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openaiApiKey}`,
      },
      body: formData,
    });

    if (!openaiResponse.ok) {
      const errorData = await openaiResponse.text();
      console.error('OpenAI API error:', errorData);
      
      // Parse error for user-friendly message
      let errorMessage = 'Image enhancement failed';
      try {
        const parsedError = JSON.parse(errorData);
        if (parsedError.error?.message) {
          errorMessage = parsedError.error.message;
        }
      } catch {
        // Use default message if parsing fails
      }

      return new Response(
        JSON.stringify({ error: errorMessage }),
        { 
          status: openaiResponse.status, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      );
    }

    const openaiData: OpenAIImageEditResponse = await openaiResponse.json();

    // Update user's generation count
    const { error: updateError } = await supabase
      .from('profiles')
      .update({ generations_today: profile.generations_today + 1 })
      .eq('id', user.id);

    if (updateError) {
      console.error('Failed to update generation count:', updateError);
      // Don't fail the request if count update fails
    }

    // Return the enhanced image URL
    return new Response(
      JSON.stringify({ data: openaiData.data }),
      { 
        status: 200, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    );

  } catch (error) {
    console.error('Error in enhance-image-proxy:', error);
    
    return new Response(
      JSON.stringify({ 
        error: 'An unexpected error occurred during image enhancement',
        details: error.message 
      }),
      { 
        status: 500, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    );
  }
});