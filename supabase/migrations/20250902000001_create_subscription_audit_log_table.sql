-- Create subscription_audit_log table for comprehensive tracking of subscription changes
-- This table provides a complete audit trail for all subscription-related operations

CREATE TABLE public.subscription_audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL CHECK (event_type IN (
        'purchase_initiated',
        'purchase_validated', 
        'purchase_failed',
        'profile_updated',
        'profile_update_failed',
        'subscription_activated',
        'subscription_expired',
        'subscription_cancelled',
        'acknowledgment_sent',
        'acknowledgment_failed',
        'sync_attempted',
        'sync_completed',
        'sync_failed'
    )),
    product_id TEXT,
    purchase_token TEXT,
    subscription_tier TEXT,
    subscription_status TEXT,
    expiry_date TIMESTAMPTZ,
    cycle_start_date TIMESTAMPTZ,
    previous_values JSONB,
    new_values JSONB,
    error_details JSONB,
    metadata JSONB,
    source TEXT NOT NULL DEFAULT 'unknown' CHECK (source IN (
        'mobile_app',
        'validate_purchase_function',
        'generation_status_function',
        'manual_admin',
        'system_trigger',
        'unknown'
    )),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    created_by TEXT
);

-- Add comments to the table and columns
COMMENT ON TABLE public.subscription_audit_log IS 'Comprehensive audit trail for all subscription-related changes and events.';
COMMENT ON COLUMN public.subscription_audit_log.id IS 'Unique identifier for the audit log entry.';
COMMENT ON COLUMN public.subscription_audit_log.user_id IS 'User associated with the subscription event, references auth.users.id.';
COMMENT ON COLUMN public.subscription_audit_log.event_type IS 'Type of subscription event that occurred.';
COMMENT ON COLUMN public.subscription_audit_log.product_id IS 'The subscription product ID from the app store.';
COMMENT ON COLUMN public.subscription_audit_log.purchase_token IS 'The purchase token from the app store.';
COMMENT ON COLUMN public.subscription_audit_log.subscription_tier IS 'The subscription tier (e.g., premium, basic).';
COMMENT ON COLUMN public.subscription_audit_log.subscription_status IS 'Current subscription status (active, expired, cancelled).';
COMMENT ON COLUMN public.subscription_audit_log.expiry_date IS 'When the subscription expires.';
COMMENT ON COLUMN public.subscription_audit_log.cycle_start_date IS 'When the current subscription cycle started.';
COMMENT ON COLUMN public.subscription_audit_log.previous_values IS 'Previous values before the change (JSON format).';
COMMENT ON COLUMN public.subscription_audit_log.new_values IS 'New values after the change (JSON format).';
COMMENT ON COLUMN public.subscription_audit_log.error_details IS 'Error information if the operation failed (JSON format).';
COMMENT ON COLUMN public.subscription_audit_log.metadata IS 'Additional context and debugging information (JSON format).';
COMMENT ON COLUMN public.subscription_audit_log.source IS 'Source system or component that generated this audit entry.';
COMMENT ON COLUMN public.subscription_audit_log.created_at IS 'Timestamp when the audit entry was created.';
COMMENT ON COLUMN public.subscription_audit_log.created_by IS 'Identifier of who/what created this audit entry.';

-- Create indexes for better query performance
CREATE INDEX idx_subscription_audit_log_user_id ON public.subscription_audit_log(user_id);
CREATE INDEX idx_subscription_audit_log_event_type ON public.subscription_audit_log(event_type);
CREATE INDEX idx_subscription_audit_log_created_at ON public.subscription_audit_log(created_at DESC);
CREATE INDEX idx_subscription_audit_log_product_id ON public.subscription_audit_log(product_id);
CREATE INDEX idx_subscription_audit_log_purchase_token ON public.subscription_audit_log(purchase_token);
CREATE INDEX idx_subscription_audit_log_source ON public.subscription_audit_log(source);

-- Composite indexes for common query patterns
CREATE INDEX idx_subscription_audit_log_user_event_time ON public.subscription_audit_log(user_id, event_type, created_at DESC);
CREATE INDEX idx_subscription_audit_log_product_token ON public.subscription_audit_log(product_id, purchase_token);

-- Enable RLS for the subscription_audit_log table
ALTER TABLE public.subscription_audit_log ENABLE ROW LEVEL SECURITY;

-- Allow service_role to perform all operations on the table
-- Edge functions will use the service_role key to interact with this table
CREATE POLICY "Allow service_role full access to subscription_audit_log" 
ON public.subscription_audit_log
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- Allow authenticated users to read their own audit logs (for transparency)
CREATE POLICY "Allow users to read their own subscription audit logs"
ON public.subscription_audit_log
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

-- Create a helper function to log subscription events
CREATE OR REPLACE FUNCTION public.log_subscription_event(
    p_user_id UUID,
    p_event_type TEXT,
    p_product_id TEXT DEFAULT NULL,
    p_purchase_token TEXT DEFAULT NULL,
    p_subscription_tier TEXT DEFAULT NULL,
    p_subscription_status TEXT DEFAULT NULL,
    p_expiry_date TIMESTAMPTZ DEFAULT NULL,
    p_cycle_start_date TIMESTAMPTZ DEFAULT NULL,
    p_previous_values JSONB DEFAULT NULL,
    p_new_values JSONB DEFAULT NULL,
    p_error_details JSONB DEFAULT NULL,
    p_metadata JSONB DEFAULT NULL,
    p_source TEXT DEFAULT 'unknown',
    p_created_by TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    audit_id UUID;
BEGIN
    INSERT INTO public.subscription_audit_log (
        user_id,
        event_type,
        product_id,
        purchase_token,
        subscription_tier,
        subscription_status,
        expiry_date,
        cycle_start_date,
        previous_values,
        new_values,
        error_details,
        metadata,
        source,
        created_by
    ) VALUES (
        p_user_id,
        p_event_type,
        p_product_id,
        p_purchase_token,
        p_subscription_tier,
        p_subscription_status,
        p_expiry_date,
        p_cycle_start_date,
        p_previous_values,
        p_new_values,
        p_error_details,
        p_metadata,
        p_source,
        p_created_by
    ) RETURNING id INTO audit_id;
    
    RETURN audit_id;
END;
$$;

COMMENT ON FUNCTION public.log_subscription_event IS 'Helper function to create subscription audit log entries with proper validation and defaults.';
