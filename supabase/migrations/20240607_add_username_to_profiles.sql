-- Add username column to profiles table
ALTER TABLE public.profiles
ADD COLUMN username TEXT UNIQUE;

COMMENT ON COLUMN public.profiles.username IS 'Unique username for the user profile.';

-- Allow users to update their own username
DROP POLICY IF EXISTS "Allow update for own profile" ON public.profiles;
CREATE POLICY "Allow update for own profile"
  ON public.profiles
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id); 