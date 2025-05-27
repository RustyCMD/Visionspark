-- Create gallery_likes table
CREATE TABLE public.gallery_likes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  gallery_image_id UUID NOT NULL REFERENCES gallery_images(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
  UNIQUE (user_id, gallery_image_id)
);

COMMENT ON TABLE public.gallery_likes IS 'Tracks which users have liked which gallery images.';

-- Enable RLS
ALTER TABLE public.gallery_likes ENABLE ROW LEVEL SECURITY;

-- Policies for gallery_likes
CREATE POLICY "Allow read for all" ON public.gallery_likes FOR SELECT USING (true);
CREATE POLICY "Allow insert own like" ON public.gallery_likes FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Allow delete own like" ON public.gallery_likes FOR DELETE TO authenticated USING (auth.uid() = user_id); 