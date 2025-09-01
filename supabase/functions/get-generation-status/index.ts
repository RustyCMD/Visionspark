import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

const DEFAULT_FREE_GENERATION_LIMIT = 3;
const DEFAULT_FREE_ENHANCEMENT_LIMIT = 4;
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
function shouldResetEnhancements(profile: any, now: Date, userTimezone: string): boolean {
  if (!profile.last_enhancement_at) {
    return true; // First time, reset needed
  }

  const lastEnhancementDateUtc = new Date(profile.last_enhancement_at);
  const nowDayStrUserTz = getDateStringInTimezone(now, userTimezone);
  const lastEnhancementDayStrUserTz = getDateStringInTimezone(lastEnhancementDateUtc, userTimezone);

  return nowDayStrUserTz > lastEnhancementDayStrUserTz;
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
      .select('generations_today, last_generation_at, enhancements_today, last_enhancement_at, timezone, generation_limit, enhancement_limit, current_subscription_tier, subscription_active, subscription_expires_at, subscription_cycle_start_date')
      .eq('id', user.id)
      .single();

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
    let currentEnhancementLimit = profile.enhancement_limit ?? DEFAULT_FREE_ENHANCEMENT_LIMIT;
    let generationUsageInCurrentPeriod = profile.generations_today ?? 0; // Default to 0 if null
    let enhancementUsageInCurrentPeriod = profile.enhancements_today ?? 0; // Default to 0 if null
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
      if (profile.current_subscription_tier === 'monthly_unlimited' || profile.current_subscription_tier === 'monthly_unlimited_generations') {
        currentGenerationLimit = -1; // -1 for unlimited
        currentEnhancementLimit = -1; // -1 for unlimited
        generationUsageInCurrentPeriod = 0; // Not tracked or always 0 for unlimited
        enhancementUsageInCurrentPeriod = 0; // Not tracked or always 0 for unlimited
        nextResetDateIso = new Date(profile.subscription_expires_at).toISOString();
      } else {
        activeSubscriptionTier = null; // Treat as free if tier is unknown but active
        currentGenerationLimit = profile.generation_limit ?? DEFAULT_FREE_GENERATION_LIMIT; // Respect user's specific limit or default
        currentEnhancementLimit = profile.enhancement_limit ?? DEFAULT_FREE_ENHANCEMENT_LIMIT;
        activeSubscriptionTier = null; // Not a recognized paid tier or subscription expired

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
      currentEnhancementLimit = profile.enhancement_limit ?? DEFAULT_FREE_ENHANCEMENT_LIMIT;
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

    return new Response(JSON.stringify({
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