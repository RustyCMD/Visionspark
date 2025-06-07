import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
// import { corsHeaders } from '../_shared/cors.ts'; // Removed

// Inlined CORS Headers
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '', // Use anon key for invoking as user
      { global: { headers: { Authorization: req.headers.get('Authorization')! } } }
    );

    const { productId } = await req.json();
    if (!productId) {
      throw new Error('Product ID is required.');
    }

    const { data: { user } } = await supabaseClient.auth.getUser();
    if (!user) {
      return new Response(JSON.stringify({ error: 'User not authenticated.' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 401,
      });
    }

    let tier = null;
    let isActive = false;
    let expiresAt = null;
    const now = new Date();
    const futureDate = new Date(now);
    futureDate.setDate(now.getDate() + 30); // Expires in 30 days

    if (productId === 'monthly_30_generations') {
      tier = 'monthly_30';
      isActive = true;
      expiresAt = futureDate.toISOString();
    } else if (productId === 'monthly_unlimited_generations') {
      tier = 'monthly_unlimited';
      isActive = true;
      expiresAt = futureDate.toISOString();
    } else {
      return new Response(JSON.stringify({ error: 'Invalid product ID.' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      });
    }

    // SIMULATED: In a real scenario, validate purchase with Google Play Billing API here.
    // If validation fails, return an error.

    const { error: updateError } = await supabaseClient
      .from('profiles')
      .update({
        current_subscription_tier: tier,
        subscription_active: isActive,
        subscription_expires_at: expiresAt,
      })
      .eq('id', user.id);

    if (updateError) {
      console.error('Error updating profile with subscription:', updateError);
      throw new Error(`Failed to update profile: ${updateError.message}`);
    }

    return new Response(JSON.stringify({ success: true, message: 'Subscription activated and profile updated.' }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    });
  } catch (error) {
    console.error('Error in validate-purchase function:', error);
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 500,
    });
  }
}); 