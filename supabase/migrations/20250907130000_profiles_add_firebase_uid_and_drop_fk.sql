-- Decouple profiles from auth.users for Firebase UID usage and add firebase_uid column
-- Idempotent migration: guards and IF EXISTS/IF NOT EXISTS used where possible

-- 1) Drop foreign key constraint if present
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'profiles_id_fkey'
      AND table_name = 'profiles'
      AND table_schema = 'public'
  ) THEN
    ALTER TABLE public.profiles DROP CONSTRAINT profiles_id_fkey;
  END IF;
END $$;

-- 2) Ensure id has a default value so inserts can omit it
ALTER TABLE public.profiles
  ALTER COLUMN id SET DEFAULT gen_random_uuid();

-- 3) Add firebase_uid column for Firebase Auth users
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS firebase_uid TEXT;

-- 4) Create unique index on firebase_uid for fast lookups and idempotency
CREATE UNIQUE INDEX IF NOT EXISTS profiles_firebase_uid_key
  ON public.profiles (firebase_uid)
  WHERE firebase_uid IS NOT NULL;

-- 5) Optional: comment
COMMENT ON COLUMN public.profiles.firebase_uid IS 'Firebase Auth user UID; used when not using Supabase Auth.';

-- Note:
-- - Existing rows (from Supabase Auth) will have firebase_uid = NULL. That is fine.
-- - New rows created by Edge Function will set firebase_uid and let id be auto-generated.
-- - RLS remains unchanged; client writes are done via Edge Functions using service role.

