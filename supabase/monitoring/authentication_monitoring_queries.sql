-- Authentication and Subscription Monitoring Queries
-- Use these queries to monitor the health of the authentication system and detect issues

-- 1. Monitor for duplicate accounts by email
-- This query identifies users with the same email address (potential duplicates)
SELECT 
    email,
    COUNT(*) as account_count,
    array_agg(id ORDER BY created_at DESC) as user_ids,
    array_agg(created_at ORDER BY created_at DESC) as creation_dates,
    MAX(created_at) as most_recent_creation,
    MIN(created_at) as first_creation,
    MAX(created_at) - MIN(created_at) as time_span
FROM profiles 
WHERE email IS NOT NULL
GROUP BY email
HAVING COUNT(*) > 1
ORDER BY account_count DESC, most_recent_creation DESC;

-- 2. Monitor recent authentication events from audit log
-- This shows recent authentication and subscription events
SELECT 
    event_type,
    user_id,
    created_at,
    source,
    metadata->>'action' as action,
    metadata->>'error' as error,
    metadata
FROM subscription_audit_log 
WHERE created_at >= NOW() - INTERVAL '24 hours'
ORDER BY created_at DESC
LIMIT 50;

-- 3. Monitor failed subscription updates
-- This shows any subscription updates that failed and need manual attention
SELECT 
    user_id,
    product_id,
    error_code,
    error_message,
    status,
    retry_count,
    created_at,
    updated_at,
    intended_update_payload
FROM failed_subscription_updates 
WHERE status IN ('pending_manual_review', 'in_progress')
ORDER BY created_at DESC;

-- 4. Check for users with null emails in auth.users
-- This identifies users who might have authentication issues
SELECT 
    au.id,
    au.email as auth_email,
    au.created_at,
    au.raw_user_meta_data->>'email' as metadata_email,
    au.raw_user_meta_data->>'provider' as provider,
    p.email as profile_email
FROM auth.users au
LEFT JOIN profiles p ON au.id = p.id
WHERE au.email IS NULL
ORDER BY au.created_at DESC;

-- 5. Monitor subscription synchronization issues
-- This identifies users whose subscription status might be out of sync
SELECT 
    p.id,
    p.email,
    p.current_subscription_tier,
    p.subscription_active,
    p.subscription_expires_at,
    p.created_at,
    CASE 
        WHEN p.subscription_expires_at < NOW() AND p.subscription_active = true 
        THEN 'EXPIRED_BUT_ACTIVE'
        WHEN p.subscription_expires_at > NOW() AND p.subscription_active = false 
        THEN 'VALID_BUT_INACTIVE'
        ELSE 'OK'
    END as sync_status
FROM profiles p
WHERE p.current_subscription_tier IS NOT NULL
AND (
    (p.subscription_expires_at < NOW() AND p.subscription_active = true) OR
    (p.subscription_expires_at > NOW() AND p.subscription_active = false)
)
ORDER BY p.created_at DESC;

-- 6. Monitor recent user creations for duplicate detection
-- This helps identify if the duplicate account bug is still occurring
SELECT 
    p.email,
    COUNT(*) as accounts_created_today,
    array_agg(p.id ORDER BY p.created_at DESC) as user_ids,
    array_agg(p.created_at ORDER BY p.created_at DESC) as creation_times
FROM profiles p
WHERE p.created_at >= CURRENT_DATE
AND p.email IS NOT NULL
GROUP BY p.email
HAVING COUNT(*) > 1
ORDER BY accounts_created_today DESC;

-- 7. Check authentication trigger health
-- This verifies that the handle_new_user trigger is working correctly
SELECT 
    au.id,
    au.email as auth_email,
    au.created_at as auth_created,
    p.id as profile_id,
    p.email as profile_email,
    p.created_at as profile_created,
    CASE 
        WHEN p.id IS NULL THEN 'MISSING_PROFILE'
        WHEN p.email IS NULL AND au.email IS NOT NULL THEN 'MISSING_EMAIL'
        WHEN p.created_at > au.created_at + INTERVAL '1 minute' THEN 'DELAYED_CREATION'
        ELSE 'OK'
    END as trigger_status
FROM auth.users au
LEFT JOIN profiles p ON au.id = p.id
WHERE au.created_at >= NOW() - INTERVAL '24 hours'
ORDER BY au.created_at DESC;

-- 8. Monitor Google OAuth identity consistency
-- This checks if Google identities are properly linked
SELECT 
    au.id,
    au.email,
    au.raw_user_meta_data->>'google_id' as metadata_google_id,
    au.raw_user_meta_data->>'sub' as metadata_sub,
    (
        SELECT i.identity_data->>'sub' 
        FROM auth.identities i 
        WHERE i.user_id = au.id AND i.provider = 'google' 
        LIMIT 1
    ) as identity_google_id,
    (
        SELECT COUNT(*) 
        FROM auth.identities i 
        WHERE i.user_id = au.id AND i.provider = 'google'
    ) as google_identity_count
FROM auth.users au
WHERE au.raw_user_meta_data->>'provider' = 'google'
OR EXISTS (
    SELECT 1 FROM auth.identities i 
    WHERE i.user_id = au.id AND i.provider = 'google'
)
ORDER BY au.created_at DESC;

-- 9. Create a monitoring view for easy dashboard access
CREATE OR REPLACE VIEW authentication_health_dashboard AS
SELECT 
    'duplicate_accounts' as metric,
    COUNT(*) as value,
    'Number of email addresses with multiple accounts' as description
FROM (
    SELECT email
    FROM profiles 
    WHERE email IS NOT NULL
    GROUP BY email
    HAVING COUNT(*) > 1
) duplicates

UNION ALL

SELECT 
    'failed_subscriptions' as metric,
    COUNT(*) as value,
    'Number of failed subscription updates pending review' as description
FROM failed_subscription_updates 
WHERE status = 'pending_manual_review'

UNION ALL

SELECT 
    'null_emails' as metric,
    COUNT(*) as value,
    'Number of auth.users with null email addresses' as description
FROM auth.users 
WHERE email IS NULL

UNION ALL

SELECT 
    'recent_users' as metric,
    COUNT(*) as value,
    'Number of users created in last 24 hours' as description
FROM profiles 
WHERE created_at >= NOW() - INTERVAL '24 hours'

UNION ALL

SELECT 
    'sync_issues' as metric,
    COUNT(*) as value,
    'Number of users with subscription sync issues' as description
FROM profiles p
WHERE p.current_subscription_tier IS NOT NULL
AND (
    (p.subscription_expires_at < NOW() AND p.subscription_active = true) OR
    (p.subscription_expires_at > NOW() AND p.subscription_active = false)
);

COMMENT ON VIEW authentication_health_dashboard IS 'Real-time dashboard view for monitoring authentication and subscription system health.';
