import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.5.0";
import { corsHeaders } from "../_shared/cors.ts";

serve(async (req) => {
  console.log(`[create-user-profile] Request received: ${req.method}`);

  // Handle CORS preflight requests
  if (req.method === "OPTIONS") {
    console.log(`[create-user-profile] CORS preflight request handled`);
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Only allow POST requests
    if (req.method !== "POST") {
      console.log(`[create-user-profile] Method not allowed: ${req.method}`);
      return new Response(
        JSON.stringify({ error: "Method not allowed" }),
        { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    console.log(`[create-user-profile] Parsing request body...`);

    // Parse request body
    const requestBody = await req.json();
    console.log(`[create-user-profile] Request body:`, requestBody);

    const { firebase_uid, email, full_name, email_verified } = requestBody;

    if (!firebase_uid || !email) {
      console.log(`[create-user-profile] Missing required fields - firebase_uid: ${firebase_uid}, email: ${email}`);
      return new Response(
        JSON.stringify({ error: "Missing required fields: firebase_uid and email" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    console.log(`[create-user-profile] Creating/updating profile for Firebase UID: ${firebase_uid}, Email: ${email}, Full Name: ${full_name}, Email Verified: ${email_verified}`);

    // Get environment variables
    console.log(`[create-user-profile] Getting environment variables...`);
    const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
    const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

    console.log(`[create-user-profile] SUPABASE_URL: ${SUPABASE_URL ? 'SET' : 'NOT SET'}`);
    console.log(`[create-user-profile] SERVICE_ROLE_KEY: ${SERVICE_ROLE_KEY ? 'SET' : 'NOT SET'}`);

    if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
      console.log(`[create-user-profile] Missing environment variables`);
      return new Response(
        JSON.stringify({ error: 'Missing Supabase environment variables' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Create admin client with service role key
    console.log(`[create-user-profile] Creating Supabase admin client...`);
    const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // Check if profile already exists
    console.log(`[create-user-profile] Checking if profile exists for UID: ${firebase_uid}`);
    const { data: existingProfile, error: checkError } = await adminClient
      .from('profiles')
      .select('id')
      .eq('id', firebase_uid)
      .maybeSingle();

    console.log(`[create-user-profile] Profile check result - exists: ${!!existingProfile}, error: ${checkError?.message || 'none'}`);

    if (checkError) {
      console.error(`[create-user-profile] Error checking existing profile:`, checkError);
      return new Response(
        JSON.stringify({ error: 'Database error while checking profile' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (existingProfile) {
      // Profile already exists, update it
      console.log(`[create-user-profile] Profile exists, updating...`);
      const updateData = {
        email: email,
        full_name: full_name || null,
        email_verified: email_verified || false,
        updated_at: new Date().toISOString(),
      };
      console.log(`[create-user-profile] Update data:`, updateData);

      const { error: updateError } = await adminClient
        .from('profiles')
        .update(updateData)
        .eq('id', firebase_uid);

      if (updateError) {
        console.error(`[create-user-profile] Error updating profile:`, updateError);
        return new Response(
          JSON.stringify({ error: 'Failed to update user profile' }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      console.log(`[create-user-profile] Profile updated successfully for UID: ${firebase_uid}`);
      return new Response(
        JSON.stringify({
          success: true,
          message: 'Profile updated successfully',
          profile_id: firebase_uid
        }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    } else {
      // Create new profile
      console.log(`[create-user-profile] Profile doesn't exist, creating new one...`);
      const insertData = {
        id: firebase_uid,
        email: email,
        full_name: full_name || null,
        email_verified: email_verified || false,
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      };
      console.log(`[create-user-profile] Insert data:`, insertData);

      const { error: insertError } = await adminClient
        .from('profiles')
        .insert(insertData);

      if (insertError) {
        console.error(`[create-user-profile] Error creating profile:`, insertError);
        return new Response(
          JSON.stringify({ error: 'Failed to create user profile' }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      console.log(`[create-user-profile] Profile created successfully for UID: ${firebase_uid}`);
      return new Response(
        JSON.stringify({
          success: true,
          message: 'Profile created successfully',
          profile_id: firebase_uid
        }),
        { status: 201, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

  } catch (error) {
    console.error(`[create-user-profile] Unexpected error:`, error);
    console.error(`[create-user-profile] Error stack:`, error.stack);
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
