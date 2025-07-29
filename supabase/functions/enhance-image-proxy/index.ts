import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.5.0";
import { corsHeaders } from "../_shared/cors.ts";

const DEFAULT_FREE_ENHANCEMENT_LIMIT = 4;
const GRACE_PERIOD_MILLISECONDS = 3 * 24 * 60 * 60 * 1000; // 3 days

function getUserTimezone(user: any, profile: any): string {
  return profile?.timezone || user?.user_metadata?.timezone || 'UTC';
}

function getDateStringInTimezone(date: Date, timezone: string): string {
  try {
    return date.toLocaleDateString('en-CA', { timeZone: timezone });
  } catch {
    return date.toLocaleDateString('en-CA', { timeZone: 'UTC' });
  }
}

function getNextUTCMidnightISO(): string {
  const tomorrow = new Date();
  tomorrow.setUTCDate(tomorrow.getUTCDate() + 1);
  tomorrow.setUTCHours(0, 0, 0, 0);
  return tomorrow.toISOString();
}

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

    // Check user's enhancement status and limits
    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .select('enhancement_limit, enhancements_today, last_enhancement_at, timezone, current_subscription_tier, subscription_active, subscription_expires_at')
      .eq('id', user.id)
      .single();

    if (profileError) {
      console.error(`User ${user.id}: Profile fetch error:`, profileError.message);
      return new Response(
        JSON.stringify({ error: 'Failed to fetch user profile' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    let lt_enhancements_today = typeof profile.enhancements_today === 'number' ? profile.enhancements_today : 0;
    const userTimezone = getUserTimezone(user, profile);
    const now = new Date();
    const profileUpdates: Record<string, any> = {};
    let needsDBUpdateBeforeEnhancement = false;
    let derivedEnhancementLimit = profile.enhancement_limit ?? DEFAULT_FREE_ENHANCEMENT_LIMIT;
    let nextResetForClientIso = getNextUTCMidnightISO();

    // Check subscription status
    const isSubscriptionEffectivelyActive =
        profile.subscription_active &&
        profile.subscription_expires_at &&
        (new Date(profile.subscription_expires_at).getTime() + GRACE_PERIOD_MILLISECONDS) > now.getTime();

    if (isSubscriptionEffectivelyActive) {
      if (profile.current_subscription_tier === 'monthly_unlimited') {
        derivedEnhancementLimit = -1; // Unlimited
        lt_enhancements_today = 0;
        nextResetForClientIso = new Date(profile.subscription_expires_at).toISOString();
      }
    } else {
      // Daily reset logic for free users
      derivedEnhancementLimit = profile.enhancement_limit || DEFAULT_FREE_ENHANCEMENT_LIMIT;
      let performDailyReset = false;
      if (profile.last_enhancement_at) {
        const lastEnhancementDateUtc = new Date(profile.last_enhancement_at);
        const nowDayStrUserTz = getDateStringInTimezone(now, userTimezone);
        const lastEnhancementDayStrUserTz = getDateStringInTimezone(lastEnhancementDateUtc, userTimezone);
        if (nowDayStrUserTz > lastEnhancementDayStrUserTz) {
          performDailyReset = true;
        }
      } else {
        performDailyReset = true;
      }

      if (performDailyReset) {
        lt_enhancements_today = 0;
        profileUpdates.enhancements_today = 0;
        needsDBUpdateBeforeEnhancement = true;
      }
      nextResetForClientIso = getNextUTCMidnightISO();
    }

    if (needsDBUpdateBeforeEnhancement && Object.keys(profileUpdates).length > 0) {
      console.log(`User ${user.id}: Performing pre-enhancement profile update for daily reset:`, profileUpdates);
      const { error: resetUpdateError } = await supabase
        .from("profiles")
        .update(profileUpdates)
        .eq("id", user.id);
      if (resetUpdateError) {
        console.error(`User ${user.id}: Failed to update profile on daily reset:`, resetUpdateError.message);
      }
    }

    // Check if user has reached their enhancement limit
    if (derivedEnhancementLimit !== -1 && lt_enhancements_today >= derivedEnhancementLimit) {
      console.log(`Enhancement limit (${derivedEnhancementLimit}) reached for user ${user.id}. Enhancements today: ${lt_enhancements_today}. Resets at: ${nextResetForClientIso}`);
      return new Response(
        JSON.stringify({
          error: `Enhancement limit of ${derivedEnhancementLimit} reached for today.`,
          resets_at_utc_iso: nextResetForClientIso,
          limit_details: {
            current_limit: derivedEnhancementLimit,
            enhancements_used_today: lt_enhancements_today,
            active_subscription: profile.current_subscription_tier
          }
        }),
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

    // Detect the image format by magic bytes and set appropriate MIME type
    let mimeType = 'image/png'; // Default to PNG

    // Check for PNG magic bytes
    if (imageBuffer.length >= 8 &&
        imageBuffer[0] === 0x89 && imageBuffer[1] === 0x50 &&
        imageBuffer[2] === 0x4E && imageBuffer[3] === 0x47) {
      mimeType = 'image/png';
    }
    // Check for JPEG magic bytes
    else if (imageBuffer.length >= 3 &&
             imageBuffer[0] === 0xFF && imageBuffer[1] === 0xD8 && imageBuffer[2] === 0xFF) {
      mimeType = 'image/jpeg';
    }

    const imageBlob = new Blob([imageBuffer], { type: mimeType });

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
        // Note: OpenAI's edit endpoint requires PNG format and is quite strict
        // For better compatibility, we'll use variations endpoint for most cases
        openaiEndpoint = 'https://api.openai.com/v1/images/variations';
        formData.delete('prompt'); // Variations don't support prompts
        break;
      case 'variation':
        openaiEndpoint = 'https://api.openai.com/v1/images/variations';
        // Remove prompt for variations as it's not supported
        formData.delete('prompt');
        break;
      case 'enhance':
      default:
        // For enhance mode, use variations endpoint for better results and format compatibility
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

    // Update user's enhancement count
    const enhancementsCountForDBDebit = lt_enhancements_today + 1;
    const timestampForThisAttempt = new Date().toISOString();

    console.log(`User ${user.id}: OpenAI success. Debiting enhancement. Current (before this): ${lt_enhancements_today}, New DB count: ${enhancementsCountForDBDebit}`);
    const { data: debitedProfile, error: debitError } = await supabase
      .from("profiles")
      .update({
        enhancements_today: enhancementsCountForDBDebit,
        last_enhancement_at: timestampForThisAttempt,
      })
      .eq("id", user.id)
      .select('enhancements_today, last_enhancement_at')
      .single();

    if (debitError || !debitedProfile) {
      console.error(`User ${user.id}: CRITICAL - OpenAI call SUCCEEDED but FAILED to debit enhancement count:`, debitError?.message);
      // Don't fail the request if count update fails, but log the error
    } else {
      console.log(`User ${user.id}: Successfully debited enhancement count. New count: ${debitedProfile.enhancements_today}`);
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