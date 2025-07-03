-- Add like_count column to gallery_images
ALTER TABLE public.gallery_images ADD COLUMN like_count INTEGER NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.gallery_images.like_count IS 'Number of likes for this image.';

-- Trigger function to increment like_count
CREATE OR REPLACE FUNCTION public.increment_gallery_like_count()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.gallery_images SET like_count = like_count + 1 WHERE id = NEW.gallery_image_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger function to decrement like_count
CREATE OR REPLACE FUNCTION public.decrement_gallery_like_count()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.gallery_images SET like_count = GREATEST(like_count - 1, 0) WHERE id = OLD.gallery_image_id;
  RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create triggers
DROP TRIGGER IF EXISTS trigger_increment_gallery_like_count ON public.gallery_likes;
CREATE TRIGGER trigger_increment_gallery_like_count
AFTER INSERT ON public.gallery_likes
FOR EACH ROW EXECUTE FUNCTION public.increment_gallery_like_count();

DROP TRIGGER IF EXISTS trigger_decrement_gallery_like_count ON public.gallery_likes;
CREATE TRIGGER trigger_decrement_gallery_like_count
AFTER DELETE ON public.gallery_likes
FOR EACH ROW EXECUTE FUNCTION public.decrement_gallery_like_count(); 