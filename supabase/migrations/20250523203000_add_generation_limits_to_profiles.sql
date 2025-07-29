ALTER TABLE public.profiles
ADD COLUMN last_generation_at TIMESTAMPTZ NULL,
ADD COLUMN generations_today INT NOT NULL DEFAULT 0,
ADD COLUMN last_enhancement_at TIMESTAMPTZ NULL,
ADD COLUMN enhancements_today INT NOT NULL DEFAULT 0,
ADD COLUMN timezone TEXT NULL;

COMMENT ON COLUMN public.profiles.last_generation_at IS 'Timestamp of the last image generation for daily limit tracking.';
COMMENT ON COLUMN public.profiles.generations_today IS 'Count of images generated today for daily limit tracking.';
COMMENT ON COLUMN public.profiles.last_enhancement_at IS 'Timestamp of the last image enhancement for daily limit tracking.';
COMMENT ON COLUMN public.profiles.enhancements_today IS 'Count of images enhanced today for daily limit tracking.';
COMMENT ON COLUMN public.profiles.timezone IS 'User IANA timezone for calculating daily reset (e.g., America/New_York).';