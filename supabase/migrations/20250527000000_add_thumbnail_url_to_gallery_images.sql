ALTER TABLE public.gallery_images
ADD COLUMN thumbnail_url TEXT NULL;

COMMENT ON COLUMN public.gallery_images.thumbnail_url IS 'Direct URL or path to the gallery image thumbnail'; 