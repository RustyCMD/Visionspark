-- Create the public.profiles table
CREATE TABLE public.profiles (
  id UUID NOT NULL PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email VARCHAR(255),
  created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Add comments to the table and columns
COMMENT ON TABLE public.profiles IS 'Stores public profile information for users.';
COMMENT ON COLUMN public.profiles.id IS 'References auth.users.id';
COMMENT ON COLUMN public.profiles.email IS 'User''s email, can be sourced from auth.users.';
COMMENT ON COLUMN public.profiles.created_at IS 'Timestamp of when the profile was created.';

-- Create a function to handle new user entries
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, email)
  VALUES (new.id, new.email);
  RETURN new;
END;
$$;

-- Create a trigger to execute the function after a new user is added to auth.users
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Enable RLS for the profiles table
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Allow authenticated users to read their own profile
CREATE POLICY "Allow authenticated read access to own profile"
ON public.profiles
FOR SELECT
TO authenticated
USING (auth.uid() = id);

-- Example: Allow users to update their own profile (if you add more fields like username, avatar_url)
-- You would typically add specific columns users are allowed to update.
-- CREATE POLICY "Allow update for own profile"
-- ON public.profiles
-- FOR UPDATE
-- TO authenticated
-- USING (auth.uid() = id)
-- WITH CHECK (auth.uid() = id); 