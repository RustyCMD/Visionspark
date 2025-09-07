-- Migration: Backfill missing rows in public.profiles from auth.users
-- Context: Ensure every Firebase-authenticated user has a corresponding profile row
-- Safety: Idempotent via anti-join; safe to re-run

INSERT INTO public.profiles (id, email, created_at)
SELECT u.id, u.email, timezone('utc'::text, now())
FROM auth.users u
LEFT JOIN public.profiles p ON p.id = u.id
WHERE p.id IS NULL;

