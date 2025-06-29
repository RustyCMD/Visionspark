# VisionSpark Security Guidance: Supabase

This document provides recommendations for critical security configurations in your Supabase project, specifically focusing on Row Level Security (RLS) and Storage Access Policies. It's crucial to implement and regularly review these settings in your Supabase Dashboard.

## 1. Row Level Security (RLS)

RLS is fundamental to protecting your data. Ensure RLS is **ENABLED** on all tables containing sensitive or user-specific data. Policies should follow the principle of least privilege.

**Action Item:** Conduct a comprehensive audit of RLS policies for all tables in the Supabase Dashboard.

### Key Tables & Recommended Policies:

**Table: `public.profiles`**

*   **Purpose:** Stores user-specific profile information.
*   **Default Behavior:** Users should only be able to read and modify their own profile. Sensitive fields (like subscription status if managed by triggers/functions) might not be directly updatable by users.

*   **Example Policies:**

    ```sql
    -- POLICY: Allow users to SELECT their own profile
    CREATE POLICY "Users can select their own profile"
    ON public.profiles
    FOR SELECT
    TO authenticated
    USING (auth.uid() = id);

    -- POLICY: Allow users to UPDATE their own profile (specific columns)
    -- Be specific about which columns users can update. Avoid allowing updates to fields like 'email' (if synced from auth.users), 'created_at', 'subscription_active', etc.
    CREATE POLICY "Users can update their own profile (e.g., username, timezone)"
    ON public.profiles
    FOR UPDATE
    TO authenticated
    USING (auth.uid() = id)
    WITH CHECK (
      auth.uid() = id
      -- Add column checks if necessary, e.g. if only 'username' and 'timezone' are updatable:
      -- AND (column_name = 'username' OR column_name = 'timezone') -- This is pseudo-SQL for column check concept, actual check might be more complex or handled by app logic
    );
    -- Note: The `WITH CHECK` clause for UPDATE is crucial.
    -- For simpler scenarios where users can update most non-critical fields, the USING clause alone might suffice for user ID check.
    -- Consider if `email` should be updatable here, or if it's only synced from `auth.users` via the trigger.
    ```

**Table: `public.gallery_images`**

*   **Purpose:** Stores information about images shared to the gallery.
*   **Existing Policies (from migration `20240608_add_likes_tables.sql` - which references `gallery_images`):** The migrations for `gallery_likes` suggest `gallery_images` exists, but its own RLS setup isn't fully shown in existing migrations beyond enabling RLS implicitly if it was created with it.
*   **Recommended Policies:**

    ```sql
    -- POLICY: Allow authenticated users to INSERT new gallery images
    CREATE POLICY "Authenticated users can insert gallery images"
    ON public.gallery_images
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id); -- Ensures user_id matches the inserter

    -- POLICY: Allow users to SELECT all gallery images (if gallery is public)
    -- Adjust if gallery images have privacy settings (e.g., a 'is_public' boolean column)
    CREATE POLICY "Allow public read access to gallery images"
    ON public.gallery_images
    FOR SELECT
    USING (true); -- Or TO public; or TO authenticated; depending on desired visibility

    -- POLICY: Allow users to UPDATE their own gallery images (e.g., prompt, is_public flag)
    CREATE POLICY "Users can update their own gallery images"
    ON public.gallery_images
    FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

    -- POLICY: Allow users to DELETE their own gallery images
    CREATE POLICY "Users can delete their own gallery images"
    ON public.gallery_images
    FOR DELETE
    TO authenticated
    USING (auth.uid() = user_id);
    ```

**Table: `public.gallery_likes`**

*   **Purpose:** Tracks user likes on gallery images.
*   **Existing Policies (from migration `20240608_add_likes_tables.sql`):**
    *   `CREATE POLICY "Allow read for all" ON public.gallery_likes FOR SELECT USING (true);`
        *   *Review:* This allows any authenticated user (or even anonymous if table access is granted) to see all like relationships. This might be acceptable if like data is considered public. If not, restrict it (e.g., `USING (auth.uid() = user_id)` if users can only see their own likes, which is less common for a "like" system).
    *   `CREATE POLICY "Allow insert own like" ON public.gallery_likes FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);` (This is good)
    *   `CREATE POLICY "Allow delete own like" ON public.gallery_likes FOR DELETE TO authenticated USING (auth.uid() = user_id);` (This is good)

**Table: `public.webhook_rate_limits`**

*   **Purpose:** Internal table for rate limiting webhooks, likely managed by service functions.
*   **Existing Policies (from migration `20250721120000_create_webhook_rate_limits.sql`):**
    *   `CREATE POLICY "Allow service_role full access to webhook_rate_limits" ON public.webhook_rate_limits FOR ALL TO service_role USING (true) WITH CHECK (true);`
        *   *Review:* This is appropriate if this table is exclusively managed by backend functions using the `service_role` key. No public or individual user access should be granted.

### General RLS Principles:

*   **Deny by Default:** If no policy allows an operation, it's denied.
*   **`USING` Clause:** Filters which rows are visible or can be acted upon for `SELECT`, `UPDATE`, `DELETE`.
*   **`WITH CHECK` Clause:** Enforces conditions for `INSERT` and `UPDATE` operations on new/modified data. Crucial for preventing users from inserting/updating data in ways that violate your rules (e.g., assigning data to another user).
*   **`SECURITY DEFINER` Functions:** Use with caution. Functions like `handle_new_user` (which populates `profiles`) and like-counting triggers need `SECURITY DEFINER` to operate correctly across tables with different ownership/privileges. Ensure their internal logic is secure and doesn't introduce vulnerabilities. The `SET search_path` within these functions is a good practice.
*   **Test Thoroughly:** After defining policies, test them rigorously from various user contexts (anonymous, authenticated user A, authenticated user B) to ensure they behave as expected.

---

## 2. Storage Access Policies

Supabase Storage uses policies similar to RLS to control access to files and folders within buckets. Proper configuration is essential to protect stored assets.

**Action Item:** Conduct a comprehensive audit of Storage policies for all buckets in the Supabase Dashboard.

### Key Buckets & Recommended Policies:

**Bucket: `profilepictures`**

*   **Purpose:** Stores user profile pictures.
*   **Intended Access:** These images should generally be private to the user or readable by authenticated users if profiles are public. Write access should be restricted to the owning user. Deletion might be handled by the user or by service functions (like `delete-account`).
*   **Code Insights:**
    *   The `delete-account` function uses a service role key to list and delete files from a path like `{userId}/{filename}`, indicating user-specific folders.
*   **Recommended Policies (Examples in Supabase Dashboard SQL interface):**

    ```sql
    -- POLICY: Allow users to upload their own profile picture.
    -- Assumes files are uploaded to a path like: {user_id}/{filename.ext}
    CREATE POLICY "Users can upload own profile pictures"
    ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (
      bucket_id = 'profilepictures' AND
      auth.uid()::text = (storage.foldername(name))[1] -- Checks if the first part of the path is the user's ID
      -- You might add checks for file size, type etc. if desired, often handled client-side or in a pre-upload function.
      -- e.g. AND metadata->>'size' < '1048576' -- 1MB limit
      -- AND metadata->>'mimetype' IN ('image/jpeg', 'image/png')
    );

    -- POLICY: Allow users to update their own profile picture (replace).
    CREATE POLICY "Users can update own profile pictures"
    ON storage.objects FOR UPDATE TO authenticated
    USING (
      bucket_id = 'profilepictures' AND
      auth.uid()::text = (storage.foldername(name))[1]
    )
    WITH CHECK (
      auth.uid()::text = (storage.foldername(name))[1]
    );

    -- POLICY: Allow users to delete their own profile pictures.
    CREATE POLICY "Users can delete own profile pictures"
    ON storage.objects FOR DELETE TO authenticated
    USING (
      bucket_id = 'profilepictures' AND
      auth.uid()::text = (storage.foldername(name))[1]
    );

    -- POLICY: Allow authenticated users to read profile pictures.
    -- This makes profile pictures generally readable by anyone logged in if they know the path.
    -- If profiles are private, you might restrict this further or rely on signed URLs if profiles are only shown to specific users.
    CREATE POLICY "Authenticated users can read profile pictures"
    ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id = 'profilepictures');

    -- OR if profile pictures should only be accessible via signed URLs or by the owner directly:
    -- POLICY: Users can view their own profile picture
    -- CREATE POLICY "Users can view their own profile picture"
    -- ON storage.objects FOR SELECT TO authenticated
    -- USING (bucket_id = 'profilepictures' AND auth.uid()::text = (storage.foldername(name))[1]);
    ```

**Bucket: `imagestorage`**

*   **Purpose:** Stores images generated by users and shared to the gallery, including thumbnails.
*   **Intended Access:**
    *   Users upload their generated images (and client-generated thumbnails) to this bucket.
    *   The `get-gallery-feed` function generates signed URLs for these images, suggesting that direct public anonymous access might not be intended or should be limited.
    *   The Flutter app's `_shareToGallery` uploads to paths like `public/{user_id}_{timestamp}.png`. The `public/` prefix is a convention and does not automatically make files public without a policy.
*   **Recommended Policies (Examples in Supabase Dashboard SQL interface):**

    ```sql
    -- POLICY: Allow authenticated users to upload images and thumbnails they generated.
    -- Path for main images: public/{user_id}_{timestamp}.png
    -- Path for thumbnails: public/{user_id}_{timestamp}_thumb.png
    CREATE POLICY "Authenticated users can upload to imagestorage"
    ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (
      bucket_id = 'imagestorage' AND
      auth.uid()::text = split_part((storage.foldername(name))[2], '_', 1) AND -- Assumes foldername is [public, {user_id_...}]
      left((storage.foldername(name))[1], 6) = 'public' -- Ensure it's in the 'public' folder
      -- Add checks for file size, type if necessary.
    );

    -- POLICY: Allow users to delete their own images from imagestorage.
    -- This assumes they might delete from gallery, which should also delete the storage object.
    CREATE POLICY "Users can delete their own images from imagestorage"
    ON storage.objects FOR DELETE TO authenticated
    USING (
        bucket_id = 'imagestorage' AND
        auth.uid()::text = split_part((storage.foldername(name))[2], '_', 1) AND
        left((storage.foldername(name))[1], 6) = 'public'
    );

    -- Regarding SELECT access for `imagestorage`:
    -- Option 1: All access via Signed URLs (Recommended if `get-gallery-feed` is the primary way to serve images)
    --   In this case, you would NOT have a broad public SELECT policy.
    --   The `get-gallery-feed` function uses the service role to create signed URLs, bypassing RLS-like storage policies for that specific action.
    --   You might have a policy allowing users to select THEIR OWN images if they need direct access for some reason (e.g. viewing their uploads list).
    --   POLICY: "Users can select their own images in imagestorage"
    --   ON storage.objects FOR SELECT TO authenticated
    --   USING (
    --     bucket_id = 'imagestorage' AND
    --     auth.uid()::text = split_part((storage.foldername(name))[2], '_', 1) AND
    --     left((storage.foldername(name))[1], 6) = 'public'
    --   );

    -- Option 2: Files under `public/` are truly publicly readable by anyone (even anonymous users).
    --   This makes the `public/` path convention meaningful.
    --   If this is the case, signed URLs from `get-gallery-feed` are still useful for client-side caching control or if the feed sometimes includes non-public images.
    --   CREATE POLICY "Public read access for files in public folder of imagestorage"
    --   ON storage.objects FOR SELECT TO public -- or anon, authenticated
    --   USING (
    --     bucket_id = 'imagestorage' AND
    --     left((storage.foldername(name))[1], 6) = 'public'
    --   );

    -- **Decision Point:** Choose Option 1 or 2 based on your application's requirements.
    -- If unsure, Option 1 (Signed URLs as primary access method) is generally more secure as it provides temporary, controlled access.
    ```

### General Storage Policy Principles:

*   **Path-Based Restrictions:** Policies often rely on extracting user IDs or specific folder names from the file path (`name` or `storage.foldername(name)`). Ensure your upload logic consistently creates these paths.
*   **Bucket-Specific:** Policies are per-bucket.
*   **Service Role Bypass:** Operations using the `service_role` key (like generating signed URLs in a function, or admin deletions) bypass these policies. This is powerful but means those functions must be secure.
*   **Test Thoroughly:** Use different user accounts and anonymous access (if applicable) to test file uploads, downloads, and deletions against your policies.

By carefully configuring both RLS and Storage policies, you significantly enhance the security and integrity of your VisionSpark application.
