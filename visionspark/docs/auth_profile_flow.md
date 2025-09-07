# VisionSpark Auth + Profile Flow (Firebase Auth + Supabase)

This document describes how user registration, login, and profile management work now that VisionSpark uses Firebase Auth and a Supabase Edge Function to manage profiles.

## Registration
1. Create Firebase user via `FirebaseAuth.createUserWithEmailAndPassword`.
2. Create Supabase profile by invoking Edge Function `create-user-profile` with `{firebase_uid, email, full_name, email_verified}`.
   - If this step fails: delete the just-created Firebase user, sign out, and surface an error. Registration does not succeed.
3. Send email verification only after profile creation succeeds.

## Login
- After Firebase sign-in, the app ensures a profile exists:
  - Query `public.profiles` by `id == firebase_uid`.
  - If found: no-op.
  - If missing: invoke `create-user-profile` once to create it.

## Profile updates
- App exposes `updateUserProfile` to update Firebase display name and Supabase fields (e.g., `full_name`, `avatar_url`) respecting RLS.

## Database triggers
- The legacy trigger/function `on_auth_user_created`/`public.handle_new_user` have been removed. Profile creation is owned by the Edge Function.

## Backfill
- An idempotent migration backfills any `auth.users` that lack `public.profiles` rows.

## Operational notes
- Edge Function `create-user-profile` must be deployed and reachable (returns 200/201).
- Logs provide context for failures; registration will roll back to avoid partial states.

