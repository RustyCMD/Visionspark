-- Migration: Drop obsolete trigger/function for profile creation
-- Context: VisionSpark now uses Firebase Auth + Edge Function (create-user-profile) to manage profiles.
-- The legacy trigger/function designed for pure Supabase Auth causes duplicate inserts and race conditions.

-- Safety: Use IF EXISTS to allow repeated runs without failure.

-- 1) Drop the trigger that auto-inserts into public.profiles on auth.users insert
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- 2) Drop the function invoked by the trigger
DROP FUNCTION IF EXISTS public.handle_new_user();

-- Notes:
-- - Ensure the create-user-profile Edge Function is deployed and healthy before applying this migration.
-- - Profile creation/update is now owned by the Edge Function for idempotency and better control.

