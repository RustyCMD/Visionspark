import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.7';

serve(async (req) => {
  // Get JWT from Authorization header
  const authHeader = req.headers.get('Authorization');
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return new Response(JSON.stringify({ error: 'Missing or invalid Authorization header' }), { status: 401 });
  }
  const jwt = authHeader.replace('Bearer ', '');

  // Get env vars
  const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
  const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
    return new Response(JSON.stringify({ error: 'Missing Supabase env vars' }), { status: 500 });
  }

  // Parse query params
  const url = new URL(req.url);
  const limit = parseInt(url.searchParams.get('limit') ?? '20', 10);
  const offset = parseInt(url.searchParams.get('offset') ?? '0', 10);

  // Create admin client
  const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Get user info from JWT
  const { data: { user }, error: userError } = await adminClient.auth.getUser(jwt);
  if (userError || !user) {
    return new Response(JSON.stringify({ error: 'Invalid user or session' }), { status: 401 });
  }
  const userId = user.id;

  // Fetch paginated gallery images
  const { data: images, error: imgError } = await adminClient
    .from('gallery_images')
    .select('id, user_id, image_path, prompt, created_at, like_count')
    .order('created_at', { ascending: false })
    .range(offset, offset + limit - 1);
  if (imgError) {
    return new Response(JSON.stringify({ error: imgError.message }), { status: 500 });
  }

  // For each image, get signed URL and like status
  const debugLogs: any[] = [];
  const results = await Promise.all(images.map(async (img) => {
    // Signed URL for thumbnail (or image_path if no thumbnail)
    const thumbPath = img.image_path.replace(/\.(jpg|jpeg|png)$/i, '_thumb.$1');
    let signedUrl = null;
    let log: { id: any, image_path: any, thumb_path: any, signedUrl: string | null, error: string | null } = {
      id: img.id,
      image_path: img.image_path,
      thumb_path: thumbPath,
      signedUrl: null,
      error: null
    };
    try {
      const { data: urlData, error: thumbError } = await adminClient.storage
        .from('imagestorage')
        .createSignedUrl(thumbPath, 3600);
      if (thumbError) {
        log.error = `Thumb error: ${thumbError.message}`;
      }
      signedUrl = urlData?.signedUrl ?? null;
      log.signedUrl = signedUrl;
      if (!signedUrl) {
        throw new Error('No signed URL for thumb');
      }
    } catch (e) {
      log.error = log.error ? log.error + `; Fallback error: ${e.message}` : `Fallback error: ${e.message}`;
      // fallback to original image if thumbnail not found
      try {
        const { data: urlData, error: origError } = await adminClient.storage
          .from('imagestorage')
          .createSignedUrl(img.image_path, 3600);
        if (origError) {
          log.error = log.error ? log.error + `; Orig error: ${origError.message}` : `Orig error: ${origError.message}`;
        }
        signedUrl = urlData?.signedUrl ?? null;
        log.signedUrl = signedUrl;
      } catch (origEx) {
        log.error = log.error ? log.error + `; Orig exception: ${origEx.message}` : `Orig exception: ${origEx.message}`;
      }
    }
    debugLogs.push(log);
    // Check if liked by current user
    const { data: likeData } = await adminClient
      .from('gallery_likes')
      .select('id')
      .eq('user_id', userId)
      .eq('gallery_image_id', img.id)
      .maybeSingle();
    return {
      ...img,
      image_url: signedUrl,
      is_liked_by_current_user: !!likeData,
    };
  }));

  return new Response(JSON.stringify({ images: results, debugLogs }), {
    headers: { 'Content-Type': 'application/json' },
    status: 200,
  });
}); 