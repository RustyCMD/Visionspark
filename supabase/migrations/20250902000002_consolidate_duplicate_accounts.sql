-- Account Consolidation Strategy for Duplicate User Accounts
-- This migration consolidates duplicate accounts for kanerigby2006@gmail.com
-- Preserves the most recent subscription data and merges user activity

-- Step 1: Log the consolidation process in audit log
DO $$
DECLARE
    canonical_user_id UUID := '8cd283ed-de99-4d25-874a-ede097677e32'; -- Most recent account
    duplicate_user_ids UUID[] := ARRAY[
        '34752fcf-4b91-4774-9fd8-b86144c529bf',
        'c5ae519f-0fa7-457e-a847-4e13296cd002', 
        '4e280cbb-81cd-46da-8527-319b812a7f05',
        '2b8efbd1-e6e2-410d-b457-054ca12682a5'
    ];
    duplicate_id UUID;
    audit_id UUID;
BEGIN
    -- Log the start of consolidation process
    INSERT INTO public.subscription_audit_log (
        user_id,
        event_type,
        metadata,
        source,
        created_by
    ) VALUES (
        canonical_user_id,
        'sync_attempted',
        jsonb_build_object(
            'consolidation_type', 'duplicate_account_merge',
            'canonical_user_id', canonical_user_id,
            'duplicate_user_ids', duplicate_user_ids,
            'reason', 'Authentication bug created duplicate accounts for same Google user'
        ),
        'manual_admin',
        'account_consolidation_script'
    ) RETURNING id INTO audit_id;

    RAISE NOTICE 'Started account consolidation process. Audit ID: %', audit_id;

    -- Step 2: Preserve the best subscription data in canonical account
    -- The canonical account (most recent) already has the latest subscription data
    -- Log this decision
    INSERT INTO public.subscription_audit_log (
        user_id,
        event_type,
        subscription_tier,
        subscription_status,
        expiry_date,
        cycle_start_date,
        metadata,
        source,
        created_by
    ) SELECT 
        canonical_user_id,
        'profile_updated',
        current_subscription_tier,
        CASE WHEN subscription_active THEN 'active' ELSE 'inactive' END,
        subscription_expires_at,
        subscription_cycle_start_date,
        jsonb_build_object(
            'action', 'preserved_canonical_subscription',
            'canonical_user_id', canonical_user_id
        ),
        'manual_admin',
        'account_consolidation_script'
    FROM profiles 
    WHERE id = canonical_user_id;

    -- Step 3: Merge generation history (sum up generations_today from all accounts)
    UPDATE profiles 
    SET generations_today = (
        SELECT COALESCE(SUM(generations_today), 0)
        FROM profiles 
        WHERE id = ANY(duplicate_user_ids || canonical_user_id)
    ),
    last_generation_at = (
        SELECT MAX(last_generation_at)
        FROM profiles 
        WHERE id = ANY(duplicate_user_ids || canonical_user_id)
        AND last_generation_at IS NOT NULL
    )
    WHERE id = canonical_user_id;

    -- Step 4: Transfer any gallery images from duplicate accounts to canonical account
    UPDATE gallery_images 
    SET user_id = canonical_user_id
    WHERE user_id = ANY(duplicate_user_ids);

    -- Step 5: Transfer any gallery likes from duplicate accounts to canonical account
    UPDATE gallery_likes 
    SET user_id = canonical_user_id
    WHERE user_id = ANY(duplicate_user_ids);

    -- Step 6: Transfer any support tickets from duplicate accounts to canonical account
    UPDATE support_tickets 
    SET user_id = canonical_user_id
    WHERE user_id = ANY(duplicate_user_ids);

    -- Step 7: Log each duplicate account before deletion
    FOREACH duplicate_id IN ARRAY duplicate_user_ids
    LOOP
        INSERT INTO public.subscription_audit_log (
            user_id,
            event_type,
            metadata,
            source,
            created_by
        ) SELECT 
            duplicate_id,
            'sync_completed',
            jsonb_build_object(
                'action', 'duplicate_account_marked_for_deletion',
                'canonical_user_id', canonical_user_id,
                'duplicate_user_id', duplicate_id,
                'original_subscription_tier', current_subscription_tier,
                'original_subscription_active', subscription_active,
                'original_generations_today', generations_today
            ),
            'manual_admin',
            'account_consolidation_script'
        FROM profiles 
        WHERE id = duplicate_id;
    END LOOP;

    -- Step 8: Delete duplicate profiles (this will cascade to auth.users due to foreign key)
    DELETE FROM profiles WHERE id = ANY(duplicate_user_ids);

    -- Step 9: Log successful consolidation
    INSERT INTO public.subscription_audit_log (
        user_id,
        event_type,
        metadata,
        source,
        created_by
    ) VALUES (
        canonical_user_id,
        'sync_completed',
        jsonb_build_object(
            'consolidation_result', 'success',
            'canonical_user_id', canonical_user_id,
            'deleted_duplicate_count', array_length(duplicate_user_ids, 1),
            'final_generations_today', (SELECT generations_today FROM profiles WHERE id = canonical_user_id)
        ),
        'manual_admin',
        'account_consolidation_script'
    );

    RAISE NOTICE 'Account consolidation completed successfully';
    RAISE NOTICE 'Canonical user ID: %', canonical_user_id;
    RAISE NOTICE 'Deleted % duplicate accounts', array_length(duplicate_user_ids, 1);

EXCEPTION
    WHEN OTHERS THEN
        -- Log the error
        INSERT INTO public.subscription_audit_log (
            user_id,
            event_type,
            error_details,
            metadata,
            source,
            created_by
        ) VALUES (
            canonical_user_id,
            'sync_failed',
            jsonb_build_object(
                'error_message', SQLERRM,
                'error_state', SQLSTATE
            ),
            jsonb_build_object(
                'consolidation_step', 'account_consolidation',
                'canonical_user_id', canonical_user_id
            ),
            'manual_admin',
            'account_consolidation_script'
        );
        
        RAISE NOTICE 'Account consolidation failed: %', SQLERRM;
        RAISE;
END $$;

-- Step 10: Create a function for future duplicate account detection and prevention
CREATE OR REPLACE FUNCTION public.detect_duplicate_accounts_by_email(target_email TEXT)
RETURNS TABLE(
    user_id UUID,
    email TEXT,
    created_at TIMESTAMPTZ,
    subscription_active BOOLEAN,
    subscription_tier TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.id,
        p.email,
        p.created_at,
        p.subscription_active,
        p.current_subscription_tier
    FROM profiles p
    WHERE p.email ILIKE target_email
    ORDER BY p.created_at DESC;
END;
$$;

COMMENT ON FUNCTION public.detect_duplicate_accounts_by_email IS 'Helper function to detect duplicate accounts by email address for monitoring and prevention.';

-- Step 11: Create a monitoring view for duplicate accounts
CREATE OR REPLACE VIEW public.duplicate_accounts_monitor AS
SELECT 
    email,
    COUNT(*) as account_count,
    array_agg(id ORDER BY created_at DESC) as user_ids,
    array_agg(created_at ORDER BY created_at DESC) as creation_dates,
    MAX(created_at) as most_recent_creation
FROM profiles 
WHERE email IS NOT NULL
GROUP BY email
HAVING COUNT(*) > 1;

COMMENT ON VIEW public.duplicate_accounts_monitor IS 'Monitoring view to detect duplicate accounts by email address.';
