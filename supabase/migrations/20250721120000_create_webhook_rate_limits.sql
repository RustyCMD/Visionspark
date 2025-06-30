-- supabase/migrations/20250721120000_create_webhook_rate_limits.sql

CREATE TABLE public.webhook_rate_limits (
  webhook_identifier TEXT NOT NULL PRIMARY KEY,
  last_sent_at TIMESTAMPTZ NOT NULL
);

COMMENT ON TABLE public.webhook_rate_limits IS 'Stores the last sent timestamp for specific webhooks to enforce rate limiting.';
COMMENT ON COLUMN public.webhook_rate_limits.webhook_identifier IS 'A unique identifier for the webhook being rate-limited (e.g., discord_support_webhook).';
COMMENT ON COLUMN public.webhook_rate_limits.last_sent_at IS 'The timestamp when the last request was successfully sent or attempted for this webhook.';

-- Enable RLS for the webhook_rate_limits table
ALTER TABLE public.webhook_rate_limits ENABLE ROW LEVEL SECURITY;

-- Allow service_role to perform all operations on the table
-- Edge functions will use the service_role key to interact with this table.
CREATE POLICY "Allow service_role full access to webhook_rate_limits" 
ON public.webhook_rate_limits
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- Grant usage on schema public to supabase_functions_admin if not already granted (common setup)
-- This might already be in place in your project.
-- GRANT USAGE ON SCHEMA public TO supabase_functions_admin;

-- Grant all privileges on the table to supabase_functions_admin (role for functions)
-- GRANT ALL ON public.webhook_rate_limits TO supabase_functions_admin; 