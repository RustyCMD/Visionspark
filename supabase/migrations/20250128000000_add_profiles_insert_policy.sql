-- Add missing INSERT policy for profiles table
-- This allows users to create their own profile when the trigger fails or manual creation is needed

-- Allow authenticated users to insert their own profile
CREATE POLICY "Allow authenticated users to insert their own profile"
ON public.profiles
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = id);

-- Add comment explaining the policy
COMMENT ON POLICY "Allow authenticated users to insert their own profile" ON public.profiles 
IS 'Allows users to create their own profile record when automatic trigger creation fails or manual creation is needed during Auth0 authentication flow.';
