import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    console.log('🔍 find-existing-user-by-google-id function called');

    // Create Supabase client with service role key for admin access
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )

    // Get the request body
    const { googleId, email } = await req.json()

    if (!googleId && !email) {
      return new Response(
        JSON.stringify({ error: 'Either googleId or email is required' }),
        { 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 400 
        }
      )
    }

    console.log(`🔍 Searching for user with Google ID: ${googleId} or email: ${email}`);

    let existingUser = null;

    // First, try to find by Google ID in user metadata
    if (googleId) {
      console.log('🔍 Searching by Google ID in user metadata...');
      
      const { data: users, error: usersError } = await supabaseAdmin.auth.admin.listUsers()
      
      if (usersError) {
        console.error('Error listing users:', usersError);
      } else {
        // Search through users for matching Google ID
        console.log(`🔍 Searching through ${users.users.length} users for Google ID: ${googleId}`);

        const matchingUser = users.users.find(user => {
          const hasGoogleIdInMetadata = user.user_metadata?.google_id === googleId;
          const hasSubInMetadata = user.user_metadata?.sub === googleId;
          const hasGoogleIdentity = user.identities?.some(identity =>
            identity.provider === 'google' && identity.id === googleId
          );

          // Log each user's metadata for debugging
          if (user.user_metadata?.google_id || user.user_metadata?.sub) {
            console.log(`👤 User ${user.id}: google_id=${user.user_metadata?.google_id}, sub=${user.user_metadata?.sub}, email=${user.email}`);
          }

          return hasGoogleIdInMetadata || hasSubInMetadata || hasGoogleIdentity;
        });

        if (matchingUser) {
          console.log(`✅ Found existing user by Google ID: ${matchingUser.id}`);
          existingUser = {
            id: matchingUser.id,
            email: matchingUser.email,
            created_at: matchingUser.created_at,
            user_metadata: matchingUser.user_metadata,
            identities: matchingUser.identities
          };
        }
      }
    }

    // If not found by Google ID, try by email
    if (!existingUser && email) {
      console.log('🔍 Searching by email...');
      
      const { data: userByEmail, error: emailError } = await supabaseAdmin.auth.admin.getUserByEmail(email);
      
      if (!emailError && userByEmail.user) {
        console.log(`✅ Found existing user by email: ${userByEmail.user.id}`);
        existingUser = {
          id: userByEmail.user.id,
          email: userByEmail.user.email,
          created_at: userByEmail.user.created_at,
          user_metadata: userByEmail.user.user_metadata,
          identities: userByEmail.user.identities
        };
      }
    }

    // Also check profiles table as backup
    if (!existingUser && email) {
      console.log('🔍 Searching profiles table by email...');
      
      const { data: profiles, error: profileError } = await supabaseAdmin
        .from('profiles')
        .select('id, email, created_at')
        .eq('email', email)
        .limit(1);

      if (!profileError && profiles && profiles.length > 0) {
        const profile = profiles[0];
        console.log(`✅ Found existing user in profiles: ${profile.id}`);
        
        // Get the full auth user data
        const { data: authUser, error: authError } = await supabaseAdmin.auth.admin.getUserById(profile.id);
        
        if (!authError && authUser.user) {
          existingUser = {
            id: authUser.user.id,
            email: authUser.user.email || profile.email,
            created_at: authUser.user.created_at,
            user_metadata: authUser.user.user_metadata,
            identities: authUser.user.identities
          };
        }
      }
    }

    if (existingUser) {
      console.log(`✅ Returning existing user: ${existingUser.id}`);
      
      // Log the successful lookup
      await supabaseAdmin
        .from('subscription_audit_log')
        .insert({
          user_id: existingUser.id,
          event_type: 'sync_completed',
          metadata: {
            action: 'existing_user_found',
            search_google_id: googleId,
            search_email: email,
            found_by: googleId ? 'google_id' : 'email'
          },
          source: 'find_existing_user_function',
          created_by: 'find-existing-user-by-google-id'
        });

      return new Response(
        JSON.stringify({ 
          found: true, 
          user: existingUser 
        }),
        { 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 200 
        }
      )
    } else {
      console.log('❌ No existing user found');
      
      // Log the failed lookup
      await supabaseAdmin
        .from('subscription_audit_log')
        .insert({
          user_id: null,
          event_type: 'sync_attempted',
          metadata: {
            action: 'existing_user_not_found',
            search_google_id: googleId,
            search_email: email
          },
          source: 'find_existing_user_function',
          created_by: 'find-existing-user-by-google-id'
        });

      return new Response(
        JSON.stringify({ 
          found: false, 
          user: null 
        }),
        { 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 200 
        }
      )
    }

  } catch (error) {
    console.error('❌ Error in find-existing-user-by-google-id:', error);
    
    return new Response(
      JSON.stringify({ 
        error: 'Internal server error',
        details: error.message 
      }),
      { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500 
      }
    )
  }
})
