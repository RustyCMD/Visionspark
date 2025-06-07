ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS subscription_cycle_start_date TIMESTAMPTZ;

COMMENT ON COLUMN public.profiles.subscription_cycle_start_date
IS 'Stores the start date of the current monthly subscription cycle for tiered plans, to track monthly generation limits.'; 