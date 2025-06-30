-- supabase/migrations/20250721100000_update_handle_new_user_trigger_with_timezone.sql

-- Drop the existing trigger and function to redefine
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();

-- Recreate the function to handle new user entries, now including timezone
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, email, timezone)
  VALUES (
    new.id,
    new.email,
    new.raw_user_meta_data ->> 'timezone' -- Extract timezone from user_metadata
  );
  RETURN new;
END;
$$;

-- Recreate the trigger to execute the function after a new user is added to auth.users
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

COMMENT ON FUNCTION public.handle_new_user() IS 'Handles new user creation by populating the profiles table, including the user''s timezone from user_metadata.'; 