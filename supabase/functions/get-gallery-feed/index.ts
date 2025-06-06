/// <reference types="https://deno.land/x/service_worker@0.1.0/window.d.ts" />
// Add Deno types reference for linter
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.7';

serve(async (req) => {
  // Get JWT from Authorization header
  const authHeader = req.headers.get('Authorization');
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return new Response(JSON.stringify({ error: 'Missing or invalid Authorization header' }), { status: 401, headers: { 'Content-Type': 'application/json' } });
  }
  const jwt = authHeader.replace('Bearer ', '');

  // Get env vars
  const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
  const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
    return new Response(JSON.stringify({ error: 'Missing Supabase env vars' }), { status: 500, headers: { 'Content-Type': 'application/json' } });
  }

  // Parse query params
  const url = new URL(req.url);
  const limit = parseInt(url.searchParams.get('limit') ?? '50', 10); // Default limit 50
  const offset = parseInt(url.searchParams.get('offset') ?? '0', 10);

  // Create admin client
  const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Get user info from JWT
  const { data: { user }, error: userError } = await adminClient.auth.getUser(jwt);
  if (userError || !user) {
    return new Response(JSON.stringify({ error: 'Invalid user or session' }), { status: 401, headers: { 'Content-Type': 'application/json' } });
  }
  const userId = user.id;

  // Fetch paginated gallery images
  const { data: images, error: imgError } = await adminClient
    .from('gallery_images')
    .select('id, user_id, image_path, prompt, created_at, like_count, thumbnail_url')
    .order('created_at', { ascending: false })
    .range(offset, offset + limit - 1);
  if (imgError) {
    return new Response(JSON.stringify({ error: imgError.message }), { status: 500, headers: { 'Content-Type': 'application/json' } });
  }

  if (!images) {
    return new Response(JSON.stringify({ images: [] }), { headers: { 'Content-Type': 'application/json' }, status: 200 });
  }

  // For each image, get signed URL and like status
  const results = await Promise.all(images.map(async (img) => {
    let mainImageUrl = null;
    let signedThumbnailUrl = null;
    let errorLog = '';

    // Get signed URL for the main image_path
    if (img.image_path) {
      try {
        const { data: mainUrlData, error: mainUrlError } = await adminClient.storage
          .from('imagestorage')
          .createSignedUrl(img.image_path, 3600); // 1 hour validity
        if (mainUrlError) {
          errorLog += `MainImgSignedUrlError: ${mainUrlError.message}; `;
        } else {
          mainImageUrl = mainUrlData?.signedUrl ?? null;
        }
      } catch (e) {
        errorLog += `MainImgSignedUrlCatch: ${e.message}; `;
      }
    }

    // Get signed URL for the thumbnail_url if it exists
    if (img.thumbnail_url && typeof img.thumbnail_url === 'string' && img.thumbnail_url.trim() !== '') {
      try {
        const { data: thumbUrlData, error: thumbUrlError } = await adminClient.storage
          .from('imagestorage') // Assuming thumbnails are in the same bucket
          .createSignedUrl(img.thumbnail_url, 3600); // 1 hour validity
        if (thumbUrlError) {
          errorLog += `ThumbUrlSignedUrlError: ${thumbUrlError.message}; `;
        } else {
          signedThumbnailUrl = thumbUrlData?.signedUrl ?? null;
        }
      } catch (e) {
        errorLog += `ThumbUrlSignedUrlCatch: ${e.message}; `;
      }
    }

    const { data: likeData, error: likeError } = await adminClient
      .from('gallery_likes')
      .select('id', { count: 'exact' })
      .eq('user_id', userId)
      .eq('gallery_image_id', img.id)
      .maybeSingle(); // Check if current user liked this specific image

    if (likeError) {
      errorLog += `LikeCheckError: ${likeError.message}; `;
    }

    return {
      id: img.id,
      user_id: img.user_id,
      prompt: img.prompt,
      created_at: img.created_at,
      like_count: img.like_count ?? 0,
      image_url: mainImageUrl,           // Signed URL for full image
      thumbnail_url_signed: signedThumbnailUrl, // Signed URL for thumbnail (or null)
      is_liked_by_current_user: !!likeData,
      _error_log: errorLog.trim() || undefined, // Include error log if any errors occurred
    };
  }));

  return new Response(JSON.stringify({ images: results }), {
    headers: { 'Content-Type': 'application/json' },
    status: 200,
  });
}); 