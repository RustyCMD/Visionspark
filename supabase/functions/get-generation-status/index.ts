import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
// import { corsHeaders } from '../_shared/cors.ts'; // Removed

// Inlined CORS Headers
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const DEFAULT_FREE_LIMIT = 3;

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: req.headers.get('Authorization')! } } }
    );

    const { data: { user } } = await supabaseClient.auth.getUser();
    if (!user) {
      return new Response(JSON.stringify({ error: 'User not authenticated.' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 401,
      });
    }

    const { data: profile, error: profileError } = await supabaseClient
      .from('profiles')
      .select('generations_today, last_generation_at, generation_limit, resets_at_utc_iso, current_subscription_tier, subscription_active, subscription_expires_at')
      .eq('id', user.id)
      .single();

    if (profileError || !profile) {
      console.error('Error fetching profile or profile not found:', profileError);
      // Fallback to default free limits if profile doesn't exist yet or error
      const now = new Date();
      const tomorrow = new Date(now);
      tomorrow.setUTCDate(now.getUTCDate() + 1);
      tomorrow.setUTCHours(0, 0, 0, 0);

      return new Response(JSON.stringify({
        limit: DEFAULT_FREE_LIMIT,
        generations_today: 0,
        remaining: DEFAULT_FREE_LIMIT,
        resets_at_utc_iso: tomorrow.toISOString(),
        subscription_tier: null,
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      });
    }

    // Subscription Check
    let currentLimit = profile.generation_limit || DEFAULT_FREE_LIMIT;
    let generationsToday = profile.generations_today || 0;
    let resetsAtUtcIso = profile.resets_at_utc_iso;
    let subscriptionTier = profile.current_subscription_tier;

    const now = new Date();
    if (profile.subscription_active && profile.subscription_expires_at && new Date(profile.subscription_expires_at) > now) {
      // Active subscription
      if (profile.current_subscription_tier === 'monthly_unlimited') {
        currentLimit = 999999; // Effectively unlimited
        generationsToday = 0; // Or don't track for unlimited
         // For unlimited, reset time is less critical, or set to subscription expiry
        resetsAtUtcIso = new Date(profile.subscription_expires_at).toISOString();
      } else if (profile.current_subscription_tier === 'monthly_30') {
        currentLimit = 30;
        // IMPORTANT: Current logic still assumes daily reset for generations_today.
        // A true monthly count for the 30-tier would need `monthly_generations_used`
        // and a `monthly_cycle_resets_at` in the profiles table, and more complex reset logic here.
        // For now, it's 30 gens per day if this sub is active.
        // The daily reset logic below will still apply.
      }
    } else {
        // Subscription expired or not active, revert to default/free tier values if they were different
        currentLimit = profile.generation_limit || DEFAULT_FREE_LIMIT; // Re-evaluate default based on profile or absolute default
        subscriptionTier = null; // Clear tier if subscription is not active
    }


    // Daily Reset Logic (applies to free tier and, for now, the 30-gen tier)
    let lastGenDate = profile.last_generation_at ? new Date(profile.last_generation_at) : new Date(0); // Epoch if null
    let resetsAtDate = resetsAtUtcIso ? new Date(resetsAtUtcIso) : new Date(0);

    if (now >= resetsAtDate) {
      generationsToday = 0;
      const tomorrow = new Date(now);
      tomorrow.setUTCDate(now.getUTCDate() + 1);
      tomorrow.setUTCHours(0, 0, 0, 0);
      resetsAtUtcIso = tomorrow.toISOString();

      // Update the profile with the new reset time and cleared generations_today
      // This happens regardless of subscription if it's a daily reset mechanism
      const { error: updateError } = await supabaseClient
        .from('profiles')
        .update({ generations_today: 0, resets_at_utc_iso: resetsAtUtcIso })
        .eq('id', user.id);
      if (updateError) {
          console.error("Failed to update profile on reset:", updateError.message);
          // Non-fatal, proceed with calculated values but log error
      }
    }
    
    const remaining = Math.max(0, currentLimit - generationsToday);

    return new Response(JSON.stringify({
      limit: currentLimit,
      generations_today: generationsToday,
      remaining: remaining,
      resets_at_utc_iso: resetsAtUtcIso,
      active_subscription_type: subscriptionTier,
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    });

  } catch (error) {
    console.error('Error in get-generation-status:', error);
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 500,
    });
  }
}); 