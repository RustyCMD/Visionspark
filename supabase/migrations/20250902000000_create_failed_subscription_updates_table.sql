-- Create failed_subscription_updates table for tracking subscription update failures
-- This table is used by the validate-purchase-and-update-profile function for fallback procedures

CREATE TABLE public.failed_subscription_updates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    product_id TEXT NOT NULL,
    purchase_token TEXT NOT NULL,
    intended_update_payload JSONB NOT NULL,
    error_code TEXT,
    error_message TEXT NOT NULL,
    error_context JSONB,
    status TEXT NOT NULL DEFAULT 'pending_manual_review' CHECK (status IN ('pending_manual_review', 'in_progress', 'resolved', 'failed')),
    retry_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    resolved_at TIMESTAMPTZ NULL,
    resolved_by TEXT NULL,
    resolution_notes TEXT NULL
);

-- Add comments to the table and columns
COMMENT ON TABLE public.failed_subscription_updates IS 'Tracks subscription profile update failures for manual resolution and debugging.';
COMMENT ON COLUMN public.failed_subscription_updates.id IS 'Unique identifier for the failed update record.';
COMMENT ON COLUMN public.failed_subscription_updates.user_id IS 'User whose subscription update failed, references auth.users.id.';
COMMENT ON COLUMN public.failed_subscription_updates.product_id IS 'The subscription product ID that was purchased.';
COMMENT ON COLUMN public.failed_subscription_updates.purchase_token IS 'The purchase token from the app store.';
COMMENT ON COLUMN public.failed_subscription_updates.intended_update_payload IS 'The subscription data that should have been applied to the user profile.';
COMMENT ON COLUMN public.failed_subscription_updates.error_code IS 'Error code from the failed update operation.';
COMMENT ON COLUMN public.failed_subscription_updates.error_message IS 'Human-readable error message describing the failure.';
COMMENT ON COLUMN public.failed_subscription_updates.error_context IS 'Additional context and debugging information about the failure.';
COMMENT ON COLUMN public.failed_subscription_updates.status IS 'Current status of the failed update record.';
COMMENT ON COLUMN public.failed_subscription_updates.retry_count IS 'Number of automatic retry attempts made.';
COMMENT ON COLUMN public.failed_subscription_updates.resolved_at IS 'Timestamp when the issue was resolved.';
COMMENT ON COLUMN public.failed_subscription_updates.resolved_by IS 'Identifier of who resolved the issue (admin user, system, etc.).';
COMMENT ON COLUMN public.failed_subscription_updates.resolution_notes IS 'Notes about how the issue was resolved.';

-- Create indexes for better query performance
CREATE INDEX idx_failed_subscription_updates_user_id ON public.failed_subscription_updates(user_id);
CREATE INDEX idx_failed_subscription_updates_status ON public.failed_subscription_updates(status);
CREATE INDEX idx_failed_subscription_updates_created_at ON public.failed_subscription_updates(created_at DESC);
CREATE INDEX idx_failed_subscription_updates_product_id ON public.failed_subscription_updates(product_id);

-- Enable RLS for the failed_subscription_updates table
ALTER TABLE public.failed_subscription_updates ENABLE ROW LEVEL SECURITY;

-- Allow service_role to perform all operations on the table
-- Edge functions will use the service_role key to interact with this table
CREATE POLICY "Allow service_role full access to failed_subscription_updates" 
ON public.failed_subscription_updates
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- Allow authenticated users to view their own failed update records
CREATE POLICY "Users can view their own failed subscription updates" 
ON public.failed_subscription_updates
FOR SELECT 
TO authenticated
USING (auth.uid() = user_id);

-- Create trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_failed_subscription_updates_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = timezone('utc', now());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_failed_subscription_updates_updated_at
    BEFORE UPDATE ON public.failed_subscription_updates
    FOR EACH ROW
    EXECUTE FUNCTION update_failed_subscription_updates_updated_at();
