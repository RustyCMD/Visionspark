import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

const DEFAULT_FREE_GENERATION_LIMIT = 3;
const DEFAULT_FREE_ENHANCEMENT_LIMIT = 4;
const GRACE_PERIOD_MILLISECONDS = 3 * 24 * 60 * 60 * 1000; // 3 days
const GRACE_PERIOD_FREE_TIER_LIMIT = 5; // During grace period, limit to 5 generations (more than free but not unlimited)

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

// Helper function to check if daily reset is needed for generations
function shouldResetGenerations(profile: any, now: Date, userTimezone: string): boolean {
  if (!profile.last_generation_at) {
    return true; // First time, reset needed
  }

  const lastGenDateUtc = new Date(profile.last_generation_at);
  const nowDayStrUserTz = getDateStringInTimezone(now, userTimezone);
  const lastGenDayStrUserTz = getDateStringInTimezone(lastGenDateUtc, userTimezone);

  return nowDayStrUserTz > lastGenDayStrUserTz;
}

// Helper function to check if daily reset is needed for enhancements
// Note: Enhancement tracking columns don't exist yet, so always reset for now
function shouldResetEnhancements(profile: any, now: Date, userTimezone: string): boolean {
  // Since last_enhancement_at column doesn't exist yet, always return true for reset
  // This will be updated when enhancement tracking is fully implemented
  return true;
}

// Helper function to perform daily reset logic for both generations and enhancements
function performDailyResetChecks(
  profile: any,
  now: Date,
  userTimezone: string,
  currentGenerationUsage: number,
  currentEnhancementUsage: number
): { generationUsage: number; enhancementUsage: number } {
  let generationUsage = currentGenerationUsage;
  let enhancementUsage = currentEnhancementUsage;

  // Check and reset generations if needed
  if (shouldResetGenerations(profile, now, userTimezone)) {
    generationUsage = 0;
  }

  // Check and reset enhancements if needed
  if (shouldResetEnhancements(profile, now, userTimezone)) {
    enhancementUsage = 0;
  }

  return { generationUsage, enhancementUsage };
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
      .select('generations_today, last_generation_at, timezone, generation_limit, current_subscription_tier, subscription_active, subscription_expires_at, subscription_cycle_start_date')
      .eq('id', user.id)
      .single();

    // Debug logging for subscription verification issues
    console.log('🔍 Profile query result for user:', user.id);
    console.log('🔍 Profile data:', JSON.stringify(profile, null, 2));
    console.log('🔍 Profile error:', profileError);

    if (profileError || !profile) {
      console.error('Error fetching profile or profile not found for user:', user.id, profileError);
      // Fallback to default free limits if profile doesn't exist yet or error
      const tomorrow = getNextUTCMidnightISO(); // Use helper for consistency

      return new Response(JSON.stringify({
        generation_limit: DEFAULT_FREE_GENERATION_LIMIT,
        generations_today: 0,
        generations_remaining: DEFAULT_FREE_GENERATION_LIMIT,
        enhancement_limit: DEFAULT_FREE_ENHANCEMENT_LIMIT,
        enhancements_today: 0,
        enhancements_remaining: DEFAULT_FREE_ENHANCEMENT_LIMIT,
        resets_at_utc_iso: tomorrow, // This is for client display of daily reset
        active_subscription_type: null,
        // Legacy fields for backward compatibility
        limit: DEFAULT_FREE_GENERATION_LIMIT,
        remaining: DEFAULT_FREE_GENERATION_LIMIT,
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      });
    }

    // Subscription Check
    // Use nullish coalescing for limits to respect 0
    let currentGenerationLimit = profile.generation_limit ?? DEFAULT_FREE_GENERATION_LIMIT;
    let currentEnhancementLimit = DEFAULT_FREE_ENHANCEMENT_LIMIT; // Use default since column doesn't exist yet
    let generationUsageInCurrentPeriod = profile.generations_today ?? 0; // Default to 0 if null
    let enhancementUsageInCurrentPeriod = 0; // Default to 0 since column doesn't exist yet
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

    // Check if we're in the grace period (expired but within grace window)
    const isInGracePeriod =
        profile.subscription_active &&
        profile.subscription_expires_at &&
        new Date(profile.subscription_expires_at).getTime() < now.getTime() && // Expired
        (new Date(profile.subscription_expires_at).getTime() + GRACE_PERIOD_MILLISECONDS) > now.getTime(); // But within grace

    // Debug logging for subscription status determination
    console.log('🔍 Subscription status check:');
    console.log('  - subscription_active:', profile.subscription_active);
    console.log('  - subscription_expires_at:', profile.subscription_expires_at);
    console.log('  - current_subscription_tier:', profile.current_subscription_tier);
    console.log('  - now:', now.toISOString());
    console.log('  - expires_at_time:', profile.subscription_expires_at ? new Date(profile.subscription_expires_at).getTime() : 'null');
    console.log('  - grace_period_ms:', GRACE_PERIOD_MILLISECONDS);
    console.log('  - isSubscriptionEffectivelyActive:', isSubscriptionEffectivelyActive);
    console.log('  - isInGracePeriod:', isInGracePeriod);

    if (isSubscriptionEffectivelyActive) {
      // Check if we're in grace period (expired but within grace window)
      if (isInGracePeriod) {
        // During grace period: Limited generations to prevent abuse
        console.log('⚠️ Subscription in grace period - applying limited access');
        currentGenerationLimit = GRACE_PERIOD_FREE_TIER_LIMIT; // Limited during grace period
        currentEnhancementLimit = GRACE_PERIOD_FREE_TIER_LIMIT;
        activeSubscriptionTier = `${profile.current_subscription_tier} (Grace Period)`;

        // Apply daily reset logic during grace period
        const userTimezone = getUserTimezone(user, profile);
        const resetResult = performDailyResetChecks(
          profile,
          now,
          userTimezone,
          generationUsageInCurrentPeriod,
          enhancementUsageInCurrentPeriod
        );
        generationUsageInCurrentPeriod = resetResult.generationUsage;
        enhancementUsageInCurrentPeriod = resetResult.enhancementUsage;

        nextResetDateIso = getNextUTCMidnightISO();
      } else if (profile.current_subscription_tier === 'monthly_unlimited' || profile.current_subscription_tier === 'monthly_unlimited_generations') {
        // Fully active subscription - unlimited access
        currentGenerationLimit = -1; // -1 for unlimited
        currentEnhancementLimit = -1; // -1 for unlimited
        generationUsageInCurrentPeriod = 0; // Not tracked or always 0 for unlimited
        enhancementUsageInCurrentPeriod = 0; // Not tracked or always 0 for unlimited
        nextResetDateIso = new Date(profile.subscription_expires_at).toISOString();
      } else {
        // Keep the original tier even if it's not recognized, but treat limits as free
        console.log(`⚠️ Active subscription with unrecognized tier: ${profile.current_subscription_tier}`);
        currentGenerationLimit = profile.generation_limit ?? DEFAULT_FREE_GENERATION_LIMIT; // Respect user's specific limit or default
        currentEnhancementLimit = DEFAULT_FREE_ENHANCEMENT_LIMIT; // Use default since column doesn't exist yet

        // Daily Reset Logic for both generations and enhancements (using helper function)
        const userTimezone = getUserTimezone(user, profile);
        const resetResult = performDailyResetChecks(
          profile,
          now,
          userTimezone,
          generationUsageInCurrentPeriod,
          enhancementUsageInCurrentPeriod
        );
        generationUsageInCurrentPeriod = resetResult.generationUsage;
        enhancementUsageInCurrentPeriod = resetResult.enhancementUsage;

        nextResetDateIso = getNextUTCMidnightISO(); // Daily resets are at UTC midnight on the next day
      }
    } else {
      // Subscription not effectively active, apply daily free tier logic
      currentGenerationLimit = profile.generation_limit ?? DEFAULT_FREE_GENERATION_LIMIT;
      currentEnhancementLimit = DEFAULT_FREE_ENHANCEMENT_LIMIT; // Use default since column doesn't exist yet
      activeSubscriptionTier = null;

      // Daily Reset Logic for both generations and enhancements (using helper function)
      const userTimezone = getUserTimezone(user, profile);
      const resetResult = performDailyResetChecks(
        profile,
        now,
        userTimezone,
        generationUsageInCurrentPeriod,
        enhancementUsageInCurrentPeriod
      );
      generationUsageInCurrentPeriod = resetResult.generationUsage;
      enhancementUsageInCurrentPeriod = resetResult.enhancementUsage;

      nextResetDateIso = getNextUTCMidnightISO();
    }

    // This function no longer needs to update profiles for monthly cycles since we removed monthly_30

    const generationsRemaining = currentGenerationLimit === -1 ? -1 : Math.max(0, currentGenerationLimit - generationUsageInCurrentPeriod);
    const enhancementsRemaining = currentEnhancementLimit === -1 ? -1 : Math.max(0, currentEnhancementLimit - enhancementUsageInCurrentPeriod);

    const responseData = {
      generation_limit: currentGenerationLimit,
      generations_today: generationUsageInCurrentPeriod,
      generations_remaining: generationsRemaining,
      enhancement_limit: currentEnhancementLimit,
      enhancements_today: enhancementUsageInCurrentPeriod,
      enhancements_remaining: enhancementsRemaining,
      resets_at_utc_iso: nextResetDateIso,
      active_subscription_type: activeSubscriptionTier,
      // Legacy fields for backward compatibility
      limit: currentGenerationLimit,
      remaining: generationsRemaining,
    };

    // Debug logging for final response
    console.log('🔍 Final response active_subscription_type:', activeSubscriptionTier);
    console.log('🔍 Final response data:', JSON.stringify(responseData, null, 2));

    return new Response(JSON.stringify(responseData), {
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