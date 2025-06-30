/// <reference types="https://deno.land/x/service_worker@0.1.0/window.d.ts" />
// Add Deno types reference for linter
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.7';
import { corsHeaders } from '../_shared/cors.ts';

serve(async (req) => {
  // Handle OPTIONS preflight request
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  // Get the JWT from the Authorization header
  const authHeader = req.headers.get('Authorization');
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return new Response(JSON.stringify({ error: 'Missing or invalid Authorization header' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
  const jwt = authHeader.replace('Bearer ', '');

  // Get env vars
  const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
  const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
    return new Response(JSON.stringify({ error: 'Missing Supabase env vars' }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }

  // Create admin client
  const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Get user info from JWT
  const { data: { user }, error: userError } = await adminClient.auth.getUser(jwt);
  if (userError || !user) {
    return new Response(JSON.stringify({ error: 'Invalid user or session' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
  const userId = user.id;

  // Delete related data (optional, but recommended)
  // Delete from profiles
  await adminClient.from('profiles').delete().eq('id', userId);
  // Delete from gallery_images
  await adminClient.from('gallery_images').delete().eq('user_id', userId);

  // Delete profile picture from Supabase Storage
  try {
    const { data: files, error: listError } = await adminClient.storage
      .from('profilepictures')
      .list(userId, { limit: 10 }); // Assuming user won't have many profile pics, limit 10 is generous

    if (listError) {
      console.error(`Error listing profile pictures for user ${userId}:`, listError.message);
      // Non-fatal, proceed with account deletion
    } else if (files && files.length > 0) {
      const filesToRemove = files.map((file) => `${userId}/${file.name}`);
      if (filesToRemove.length > 0) {
        console.log(`Attempting to delete profile pictures for user ${userId}:`, filesToRemove);
        const { error: removeError } = await adminClient.storage
          .from('profilepictures')
          .remove(filesToRemove);
        if (removeError) {
          console.error(`Error deleting profile pictures for user ${userId}:`, removeError.message);
          // Non-fatal, proceed with account deletion
        } else {
          console.log(`Successfully deleted profile pictures for user ${userId}:`, filesToRemove);
        }
      }
    }
  } catch (storageError) {
    console.error(`Unexpected error during profile picture deletion for user ${userId}:`, storageError.message);
    // Non-fatal, proceed with account deletion
  }

  // Delete the user from auth.users
  const { error: deleteError } = await adminClient.auth.admin.deleteUser(userId);
  if (deleteError) {
    return new Response(JSON.stringify({ error: deleteError.message }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }

  return new Response(JSON.stringify({ success: true }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
}); 