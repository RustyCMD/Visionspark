-- supabase/migrations/20250523203100_add_subscription_fields_to_profiles.sql

ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS current_subscription_tier TEXT NULL,
ADD COLUMN IF NOT EXISTS subscription_active BOOLEAN NOT NULL DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS subscription_expires_at TIMESTAMPTZ NULL,
ADD COLUMN IF NOT EXISTS generation_limit INT NULL;

COMMENT ON COLUMN public.profiles.current_subscription_tier IS 'Active subscription tier, e.g., monthly_30, monthly_unlimited. Set by validation function.';
COMMENT ON COLUMN public.profiles.subscription_active IS 'True if the user has an active subscription. Set by validation function.';
COMMENT ON COLUMN public.profiles.subscription_expires_at IS 'The actual expiry date of the current subscription from the store. Set by validation function.';
COMMENT ON COLUMN public.profiles.generation_limit IS 'User-specific base daily generation limit if not subscribed, or a custom limit. Can be overridden by active subscription tier benefits.';
