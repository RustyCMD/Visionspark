import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
// import { corsHeaders } from '../_shared/cors.ts'; // Removed

// Inlined CORS Headers
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const DEFAULT_FREE_LIMIT = 3;
const GRACE_PERIOD_MILLISECONDS = 3 * 24 * 60 * 60 * 1000; // 3 days

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
      .select('generations_today, last_generation_at, generation_limit, resets_at_utc_iso, current_subscription_tier, subscription_active, subscription_expires_at, subscription_cycle_start_date')
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
        active_subscription_type: null,
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      });
    }

    // Subscription Check
    let currentLimit = profile.generation_limit || DEFAULT_FREE_LIMIT;
    let usageInCurrentPeriod = profile.generations_today || 0;
    let nextResetDateIso = profile.resets_at_utc_iso;
    let activeSubscriptionTier = profile.current_subscription_tier;
    let needsProfileUpdate = false;
    const profileUpdates: Record<string, any> = {};

    const now = new Date();
    // Check if subscription is active, considering the grace period
    const isSubscriptionEffectivelyActive = 
        profile.subscription_active && 
        profile.subscription_expires_at && 
        (new Date(profile.subscription_expires_at).getTime() + GRACE_PERIOD_MILLISECONDS) > now.getTime();

    if (isSubscriptionEffectivelyActive) {
      // Active subscription
      if (profile.current_subscription_tier === 'monthly_unlimited') {
        currentLimit = -1; // -1 for unlimited
        usageInCurrentPeriod = 0; // Not tracked or always 0 for unlimited
        nextResetDateIso = new Date(profile.subscription_expires_at).toISOString();
      } else if (profile.current_subscription_tier === 'monthly_30') {
        currentLimit = 30;
        let cycleStartDate = profile.subscription_cycle_start_date ? new Date(profile.subscription_cycle_start_date) : null;
        
        if (!cycleStartDate) { // First time seeing this user with the new field, or it was null
          cycleStartDate = new Date(now); // Start their cycle now
          usageInCurrentPeriod = 0;
          profileUpdates.subscription_cycle_start_date = cycleStartDate.toISOString();
          profileUpdates.generations_today = 0; // Reset usage for the new cycle
          needsProfileUpdate = true;
        }

        const nextMonthlyReset = new Date(cycleStartDate);
        nextMonthlyReset.setMonth(nextMonthlyReset.getMonth() + 1);
        nextMonthlyReset.setUTCDate(cycleStartDate.getUTCDate()); // Preserve the day of the month
        nextMonthlyReset.setUTCHours(0,0,0,0); // Prefer start of day for cycle resets

        if (now >= nextMonthlyReset) { // Time for monthly reset
          usageInCurrentPeriod = 0;
          profileUpdates.generations_today = 0;
          profileUpdates.subscription_cycle_start_date = now.toISOString(); // Start new cycle from now
          needsProfileUpdate = true;
          // Calculate the next reset after this one
          const newCycleStartDateForNext = new Date(now);
          const nextNextMonthlyReset = new Date(newCycleStartDateForNext);
          nextNextMonthlyReset.setMonth(nextNextMonthlyReset.getMonth() + 1);
          nextNextMonthlyReset.setUTCDate(newCycleStartDateForNext.getUTCDate());
          nextNextMonthlyReset.setUTCHours(0,0,0,0);
          nextResetDateIso = nextNextMonthlyReset.toISOString();
        } else {
          // Still within the current monthly cycle
          nextResetDateIso = nextMonthlyReset.toISOString();
        }
      } else {
        activeSubscriptionTier = null; // Treat as free if tier is unknown but active
        currentLimit = DEFAULT_FREE_LIMIT;
        // Apply daily reset logic for free/unknown active tier
        const dailyResetDate = profile.resets_at_utc_iso ? new Date(profile.resets_at_utc_iso) : new Date(0);
        if (now >= dailyResetDate) {
          usageInCurrentPeriod = 0;
          profileUpdates.generations_today = 0;
          const tomorrow = new Date(now);
          tomorrow.setUTCDate(now.getUTCDate() + 1);
          tomorrow.setUTCHours(0, 0, 0, 0);
          profileUpdates.resets_at_utc_iso = tomorrow.toISOString();
          needsProfileUpdate = true;
          nextResetDateIso = tomorrow.toISOString();
        } else {
          nextResetDateIso = dailyResetDate.toISOString();
        }
      }
    } else {
      // Subscription expired or not active, revert to default/free tier values
      activeSubscriptionTier = null;
      currentLimit = DEFAULT_FREE_LIMIT; // Use absolute default for free tier
      
      // Daily Reset Logic for Free Tier
      const dailyResetDate = profile.resets_at_utc_iso ? new Date(profile.resets_at_utc_iso) : new Date(0); // Use existing or epoch
      if (now >= dailyResetDate) {
        usageInCurrentPeriod = 0;
        profileUpdates.generations_today = 0;
        const tomorrow = new Date(now);
        tomorrow.setUTCDate(now.getUTCDate() + 1);
        tomorrow.setUTCHours(0, 0, 0, 0);
        profileUpdates.resets_at_utc_iso = tomorrow.toISOString();
        needsProfileUpdate = true;
        nextResetDateIso = tomorrow.toISOString();
      } else {
        nextResetDateIso = dailyResetDate.toISOString();
      }
    }

    if (needsProfileUpdate && Object.keys(profileUpdates).length > 0) {
      const { error: updateError } = await supabaseClient
        .from('profiles')
        .update(profileUpdates)
        .eq('id', user.id);
      if (updateError) {
        console.error("Failed to update profile for cycle/daily reset:", updateError.message);
        // Non-fatal, proceed with calculated values but log error
      }
    }
    
    const remaining = currentLimit === -1 ? -1 : Math.max(0, currentLimit - usageInCurrentPeriod);

    return new Response(JSON.stringify({
      limit: currentLimit,
      generations_today: usageInCurrentPeriod,
      remaining: remaining,
      resets_at_utc_iso: nextResetDateIso,
      active_subscription_type: activeSubscriptionTier,
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