import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

Deno.serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { userId, userProfile } = await req.json();

    if (!userId || !userProfile) {
      return new Response(
        JSON.stringify({ error: 'Missing userId or userProfile' }),
        { 
          status: 400, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      );
    }

    // Create admin client to manage user sessions
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    console.log(`🔗 Creating session for existing user: ${userId}`);
    console.log(`📧 User email: ${userProfile.email}`);

    // Check if the user exists in auth.users
    const { data: authUser, error: authError } = await supabaseAdmin.auth.admin.getUserById(userId);
    
    if (authError || !authUser.user) {
      console.error('❌ User not found in auth.users:', authError);
      return new Response(
        JSON.stringify({ error: 'User not found in authentication system' }),
        { 
          status: 404, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      );
    }

    console.log(`✅ Found user in auth.users: ${authUser.user.id}`);

    // Try to update user metadata only (not email to avoid conflicts)
    console.log('🔄 Updating user metadata...');
    console.log(`📧 Current user email: "${authUser.user.email}"`);
    console.log(`📧 Profile email: "${userProfile.email}"`);

    try {
      const { error: updateError } = await supabaseAdmin.auth.admin.updateUserById(
        userId,
        {
          user_metadata: {
            name: userProfile.name,
            picture: userProfile.picture,
            google_id: userProfile.google_id,
            provider: 'google',
            email: userProfile.email, // Store in metadata instead of updating auth email
          },
        }
      );

      if (updateError) {
        console.error('❌ Error updating user metadata:', updateError);
        // Continue anyway, metadata update is not critical for session creation
      } else {
        console.log('✅ User metadata updated successfully');
      }
    } catch (e) {
      console.error('❌ Metadata update failed:', e);
      // Continue anyway
    }

    // Create session using admin API with user ID directly
    console.log('🔑 Creating session for existing user using admin API...');

    try {
      // Generate a recovery link which creates valid tokens without needing email
      const { data: linkData, error: linkError } = await supabaseAdmin.auth.admin.generateLink({
        type: 'recovery',
        email: userProfile.email, // Use the email from profile
        options: {
          redirectTo: 'app.visionspark.app://auth-callback',
        },
      });

      if (linkError || !linkData) {
        console.error('❌ Error generating recovery link:', linkError);

        // Fallback: Try to create a signup link instead
        console.log('🔄 Trying signup link as fallback...');
        const { data: signupData, error: signupError } = await supabaseAdmin.auth.admin.generateLink({
          type: 'signup',
          email: userProfile.email,
          password: 'temp-password-' + Math.random().toString(36),
          options: {
            redirectTo: 'app.visionspark.app://auth-callback',
          },
        });

        if (signupError || !signupData) {
          console.error('❌ Signup link also failed:', signupError);
          throw new Error(`Both recovery and signup link generation failed`);
        }

        console.log('✅ Signup link generated as fallback');
        const accessToken = signupData.properties?.access_token;
        const refreshToken = signupData.properties?.refresh_token;

        if (!accessToken || !refreshToken) {
          throw new Error('Signup link did not contain required tokens');
        }

        return new Response(
          JSON.stringify({
            success: true,
            session: {
              access_token: accessToken,
              refresh_token: refreshToken,
              expires_at: Math.floor(Date.now() / 1000) + 3600,
              user: signupData.user,
            },
          }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          }
        );
      }

      console.log('✅ Recovery link generated successfully');
      console.log('📋 Link data properties:', {
        hasAccessToken: !!linkData.properties?.access_token,
        hasRefreshToken: !!linkData.properties?.refresh_token,
        hasUser: !!linkData.user,
        userId: linkData.user?.id
      });

      // Extract the tokens from the recovery link properties
      const accessToken = linkData.properties?.access_token;
      const refreshToken = linkData.properties?.refresh_token;

      if (!accessToken || !refreshToken) {
        console.error('❌ Recovery link missing required tokens');
        throw new Error('Recovery link did not contain required tokens');
      }

      // Return the session data
      return new Response(
        JSON.stringify({
          success: true,
          session: {
            access_token: accessToken,
            refresh_token: refreshToken,
            expires_at: Math.floor(Date.now() / 1000) + 3600, // 1 hour from now
            user: linkData.user,
          },
        }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      );

    } catch (error) {
      console.error('❌ Error in session creation:', error);
      return new Response(
        JSON.stringify({
          error: 'Failed to create session for existing user',
          details: error.message
        }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      );
    }

  } catch (error) {
    console.error('❌ Unexpected error in create-session-for-existing-user:', error);
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { 
        status: 500, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    );
  }
});
