-- Fix Email Field Population in Authentication System
-- This migration ensures that the primary email field in auth.users is properly populated
-- and that the profiles table gets the correct email information

-- Step 1: Update the handle_new_user function to handle email extraction more robustly
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();

-- Enhanced function to handle new user entries with better email extraction
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    user_email TEXT;
    user_timezone TEXT;
BEGIN
    -- Extract email with fallback logic
    user_email := COALESCE(
        new.email,                                    -- Primary email field
        new.raw_user_meta_data ->> 'email',         -- Email from metadata
        new.raw_user_meta_data ->> 'email_verified', -- Alternative email field
        new.raw_user_meta_data -> 'user_metadata' ->> 'email' -- Nested email
    );
    
    -- Extract timezone from metadata
    user_timezone := new.raw_user_meta_data ->> 'timezone';
    
    -- Log the user creation for debugging
    INSERT INTO public.subscription_audit_log (
        user_id,
        event_type,
        metadata,
        source,
        created_by
    ) VALUES (
        new.id,
        'sync_attempted',
        jsonb_build_object(
            'action', 'new_user_profile_creation',
            'auth_email', new.email,
            'extracted_email', user_email,
            'raw_user_meta_data', new.raw_user_meta_data,
            'provider', new.raw_user_meta_data ->> 'provider'
        ),
        'system_trigger',
        'handle_new_user_function'
    );

    -- Insert into profiles with extracted email
    INSERT INTO public.profiles (id, email, timezone)
    VALUES (
        new.id,
        user_email,
        user_timezone
    );
    
    -- Log successful profile creation
    INSERT INTO public.subscription_audit_log (
        user_id,
        event_type,
        metadata,
        source,
        created_by
    ) VALUES (
        new.id,
        'sync_completed',
        jsonb_build_object(
            'action', 'profile_created_successfully',
            'profile_email', user_email,
            'profile_timezone', user_timezone
        ),
        'system_trigger',
        'handle_new_user_function'
    );
    
    RETURN new;
    
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
            new.id,
            'sync_failed',
            jsonb_build_object(
                'error_message', SQLERRM,
                'error_state', SQLSTATE
            ),
            jsonb_build_object(
                'action', 'profile_creation_failed',
                'auth_email', new.email,
                'raw_user_meta_data', new.raw_user_meta_data
            ),
            'system_trigger',
            'handle_new_user_function'
        );
        
        -- Re-raise the error to prevent user creation if profile creation fails
        RAISE;
END;
$$;

-- Recreate the trigger
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

COMMENT ON FUNCTION public.handle_new_user() IS 'Enhanced function to handle new user creation with robust email extraction and comprehensive logging.';

-- Step 2: Create a function to fix existing users with null emails
CREATE OR REPLACE FUNCTION public.fix_null_emails_in_auth_users()
RETURNS TABLE(
    user_id UUID,
    old_email TEXT,
    new_email TEXT,
    status TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    user_record RECORD;
    extracted_email TEXT;
    update_count INTEGER := 0;
BEGIN
    -- Find auth.users with null email but email in metadata
    FOR user_record IN 
        SELECT au.id, au.email, au.raw_user_meta_data, p.email as profile_email
        FROM auth.users au
        LEFT JOIN public.profiles p ON au.id = p.id
        WHERE au.email IS NULL 
        AND (
            au.raw_user_meta_data ->> 'email' IS NOT NULL OR
            p.email IS NOT NULL
        )
    LOOP
        -- Extract email with priority: profile email > metadata email
        extracted_email := COALESCE(
            user_record.profile_email,
            user_record.raw_user_meta_data ->> 'email',
            user_record.raw_user_meta_data ->> 'email_verified'
        );
        
        IF extracted_email IS NOT NULL THEN
            -- Note: We cannot directly update auth.users from a regular function
            -- This would need to be done through Supabase admin API or manual intervention
            -- For now, we'll log what needs to be fixed
            
            user_id := user_record.id;
            old_email := user_record.email;
            new_email := extracted_email;
            status := 'needs_manual_fix';
            
            -- Log the issue for manual resolution
            INSERT INTO public.subscription_audit_log (
                user_id,
                event_type,
                metadata,
                source,
                created_by
            ) VALUES (
                user_record.id,
                'sync_attempted',
                jsonb_build_object(
                    'action', 'null_email_detected',
                    'current_auth_email', user_record.email,
                    'suggested_email', extracted_email,
                    'profile_email', user_record.profile_email,
                    'metadata_email', user_record.raw_user_meta_data ->> 'email'
                ),
                'manual_admin',
                'fix_null_emails_function'
            );
            
            update_count := update_count + 1;
            RETURN NEXT;
        END IF;
    END LOOP;
    
    -- Log summary
    INSERT INTO public.subscription_audit_log (
        user_id,
        event_type,
        metadata,
        source,
        created_by
    ) VALUES (
        NULL, -- No specific user for summary
        'sync_completed',
        jsonb_build_object(
            'action', 'null_email_audit_completed',
            'users_needing_fix', update_count
        ),
        'manual_admin',
        'fix_null_emails_function'
    );
    
    RETURN;
END;
$$;

COMMENT ON FUNCTION public.fix_null_emails_in_auth_users IS 'Identifies auth.users records with null emails that can be fixed from metadata or profiles.';

-- Step 3: Create a function to ensure profile emails are populated from auth.users
CREATE OR REPLACE FUNCTION public.sync_profile_emails_from_auth()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    update_count INTEGER := 0;
BEGIN
    -- Update profiles where email is null but auth.users has email
    UPDATE public.profiles 
    SET email = au.email
    FROM auth.users au
    WHERE profiles.id = au.id
    AND profiles.email IS NULL
    AND au.email IS NOT NULL;
    
    GET DIAGNOSTICS update_count = ROW_COUNT;
    
    -- Log the sync operation
    INSERT INTO public.subscription_audit_log (
        user_id,
        event_type,
        metadata,
        source,
        created_by
    ) VALUES (
        NULL,
        'sync_completed',
        jsonb_build_object(
            'action', 'profile_emails_synced_from_auth',
            'updated_profiles', update_count
        ),
        'manual_admin',
        'sync_profile_emails_function'
    );
    
    RETURN update_count;
END;
$$;

COMMENT ON FUNCTION public.sync_profile_emails_from_auth IS 'Syncs profile emails from auth.users where profiles have null emails.';

-- Step 4: Run the profile email sync immediately
SELECT public.sync_profile_emails_from_auth();

-- Step 5: Identify users that need manual email fixes
SELECT * FROM public.fix_null_emails_in_auth_users();
