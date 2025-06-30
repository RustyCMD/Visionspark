import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

const DEFAULT_FREE_LIMIT = 3;
const GRACE_PERIOD_MILLISECONDS = 3 * 24 * 60 * 60 * 1000; // 3 days

// Helper functions (copied from generate-image-proxy.ts for daily reset logic consistency)
function getUserTimezone(user: any, profile: any): string { // user param might not be needed if only profile.timezone is primary
  if (profile?.timezone) { // Prioritize profile.timezone if available directly
    try {
      new Date().toLocaleString('en-US', { timeZone: profile.timezone });
      return profile.timezone;
    } catch (e) {
      console.warn(`Invalid timezone in profile.timezone: ${profile.timezone}. Falling back.`);
    }
  }
  if (user?.user_metadata?.timezone) {
    try {
      new Date().toLocaleString('en-US', { timeZone: user.user_metadata.timezone });
      return user.user_metadata.timezone;
    } catch (e) {
      console.warn(`Invalid timezone in user.user_metadata.timezone: ${user.user_metadata.timezone}. Falling back.`);
    }
  }
  console.warn(`No valid timezone found for user ${user?.id}, defaulting to UTC.`);
  return "UTC";
}

function getDateStringInTimezone(date: Date, timeZone: string): string {
  return date.toLocaleDateString('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' });
}

function getNextUTCMidnightISO(): string {
  const nowUtc = new Date();
  const nextUTCMidnight = new Date(Date.UTC(nowUtc.getUTCFullYear(), nowUtc.getUTCMonth(), nowUtc.getUTCDate() + 1, 0, 0, 0, 0));
  return nextUTCMidnight.toISOString();
}


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
      // Select timezone, last_generation_at. Remove resets_at_utc_iso.
      .select('generations_today, last_generation_at, timezone, generation_limit, current_subscription_tier, subscription_active, subscription_expires_at, subscription_cycle_start_date')
      .eq('id', user.id)
      .single();

    if (profileError || !profile) {
      console.error('Error fetching profile or profile not found for user:', user.id, profileError);
      // Fallback to default free limits if profile doesn't exist yet or error
      const tomorrow = getNextUTCMidnightISO(); // Use helper for consistency

      return new Response(JSON.stringify({
        limit: DEFAULT_FREE_LIMIT,
        generations_today: 0,
        remaining: DEFAULT_FREE_LIMIT,
        resets_at_utc_iso: tomorrow, // This is for client display of daily reset
        active_subscription_type: null,
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      });
    }

    // Subscription Check
    // Use nullish coalescing for currentLimit to respect 0
    let currentLimit = profile.generation_limit ?? DEFAULT_FREE_LIMIT;
    let usageInCurrentPeriod = profile.generations_today ?? 0; // Default to 0 if null
    let nextResetDateIso: string; // Will be determined by logic below
    let activeSubscriptionTier = profile.current_subscription_tier;
    let needsProfileUpdate = false; // For monthly cycle start/reset updates by this function
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
        currentLimit = profile.generation_limit ?? DEFAULT_FREE_LIMIT; // Respect user's specific limit or default
        activeSubscriptionTier = null; // Not a recognized paid tier or subscription expired

        // Daily Reset Logic (reflects generate-image-proxy logic, doesn't write daily reset here)
        const userTimezone = getUserTimezone(user, profile);
        let performDailyResetCheck = false;
        if (profile.last_generation_at) {
          const lastGenDateUtc = new Date(profile.last_generation_at);
          const nowDayStrUserTz = getDateStringInTimezone(now, userTimezone);
          const lastGenDayStrUserTz = getDateStringInTimezone(lastGenDateUtc, userTimezone);
          if (nowDayStrUserTz > lastGenDayStrUserTz) {
            performDailyResetCheck = true;
          }
        } else {
          performDailyResetCheck = true; // No last generation, so it's effectively a new day for generation
        }

        if (performDailyResetCheck) {
          usageInCurrentPeriod = 0;
          // This function does not update profile.generations_today or profile.last_generation_at for daily resets.
          // That is handled by generate-image-proxy before actual generation.
          // We only reflect what the count *would be*.
        }
        nextResetDateIso = getNextUTCMidnightISO(); // Daily resets are at UTC midnight on the next day
      }
    } else {
      // Subscription not effectively active, apply daily free tier logic
      currentLimit = profile.generation_limit ?? DEFAULT_FREE_LIMIT;
      activeSubscriptionTier = null;

      const userTimezone = getUserTimezone(user, profile);
      let performDailyResetCheck = false;
      if (profile.last_generation_at) {
        const lastGenDateUtc = new Date(profile.last_generation_at);
        const nowDayStrUserTz = getDateStringInTimezone(now, userTimezone);
        const lastGenDayStrUserTz = getDateStringInTimezone(lastGenDateUtc, userTimezone);
        if (nowDayStrUserTz > lastGenDayStrUserTz) {
          performDailyResetCheck = true;
        }
      } else {
        performDailyResetCheck = true;
      }

      if (performDailyResetCheck) {
        usageInCurrentPeriod = 0;
      }
      nextResetDateIso = getNextUTCMidnightISO();
    }

    // This function only updates the profile for monthly subscription cycle changes
    if (needsProfileUpdate && activeSubscriptionTier === 'monthly_30' && Object.keys(profileUpdates).length > 0) {
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