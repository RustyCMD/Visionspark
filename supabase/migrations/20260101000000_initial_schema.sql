-- =============================================================================
-- VisionSpark — Initial Schema (Consolidated)
-- =============================================================================
-- This is the single, clean baseline migration for fresh deployments.
-- Identity is owned by Firebase Auth; profile rows are keyed by `firebase_uid`.
-- All client mutations are funneled through Supabase Edge Functions running
-- under the service-role key, so RLS policies for the `authenticated` role
-- are intentionally restrictive (read-only where useful, otherwise omitted).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- profiles
-- -----------------------------------------------------------------------------
CREATE TABLE public.profiles (
  id                            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  firebase_uid                  TEXT,
  email                         TEXT,
  username                      TEXT UNIQUE,
  timezone                      TEXT,

  -- Generation quota
  generation_limit              INT,
  generations_today             INT  NOT NULL DEFAULT 0,
  last_generation_at            TIMESTAMPTZ,

  -- Enhancement quota
  enhancement_limit             INT,
  enhancements_today            INT  NOT NULL DEFAULT 0,
  last_enhancement_at           TIMESTAMPTZ,

  -- Subscription
  current_subscription_tier     TEXT,
  subscription_active           BOOLEAN NOT NULL DEFAULT FALSE,
  subscription_expires_at       TIMESTAMPTZ,
  subscription_cycle_start_date TIMESTAMPTZ,

  created_at                    TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);

COMMENT ON TABLE  public.profiles IS 'User profiles. Identity is Firebase Auth; lookup by firebase_uid.';
COMMENT ON COLUMN public.profiles.firebase_uid IS 'Firebase Auth user UID. Unique when set.';
COMMENT ON COLUMN public.profiles.timezone IS 'IANA timezone, used to calculate daily quota resets.';

CREATE UNIQUE INDEX profiles_firebase_uid_key
  ON public.profiles (firebase_uid)
  WHERE firebase_uid IS NOT NULL;

CREATE INDEX profiles_email_idx ON public.profiles (lower(email));

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "service_role full access on profiles"
  ON public.profiles FOR ALL TO service_role USING (true) WITH CHECK (true);

-- -----------------------------------------------------------------------------
-- gallery_images
-- -----------------------------------------------------------------------------
CREATE TABLE public.gallery_images (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  image_path    TEXT NOT NULL,
  thumbnail_url TEXT,
  prompt        TEXT,
  like_count    INT  NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);

COMMENT ON TABLE  public.gallery_images IS 'Images shared to the public gallery.';
COMMENT ON COLUMN public.gallery_images.image_path IS 'Path within the imagestorage bucket.';
COMMENT ON COLUMN public.gallery_images.thumbnail_url IS 'Path within the imagestorage bucket for the thumbnail.';

CREATE INDEX gallery_images_user_id_idx    ON public.gallery_images (user_id);
CREATE INDEX gallery_images_created_at_idx ON public.gallery_images (created_at DESC);

ALTER TABLE public.gallery_images ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public read on gallery_images"
  ON public.gallery_images FOR SELECT USING (true);

CREATE POLICY "service_role full access on gallery_images"
  ON public.gallery_images FOR ALL TO service_role USING (true) WITH CHECK (true);

-- -----------------------------------------------------------------------------
-- gallery_likes
-- -----------------------------------------------------------------------------
CREATE TABLE public.gallery_likes (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID NOT NULL REFERENCES public.profiles(id)       ON DELETE CASCADE,
  gallery_image_id UUID NOT NULL REFERENCES public.gallery_images(id) ON DELETE CASCADE,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
  UNIQUE (user_id, gallery_image_id)
);

COMMENT ON TABLE public.gallery_likes IS 'Likes by users on gallery images.';

CREATE INDEX gallery_likes_image_id_idx ON public.gallery_likes (gallery_image_id);
CREATE INDEX gallery_likes_user_id_idx  ON public.gallery_likes (user_id);

ALTER TABLE public.gallery_likes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public read on gallery_likes"
  ON public.gallery_likes FOR SELECT USING (true);

CREATE POLICY "service_role full access on gallery_likes"
  ON public.gallery_likes FOR ALL TO service_role USING (true) WITH CHECK (true);

-- like_count maintenance triggers
CREATE OR REPLACE FUNCTION public.increment_gallery_like_count()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE public.gallery_images
     SET like_count = like_count + 1
   WHERE id = NEW.gallery_image_id;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.decrement_gallery_like_count()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE public.gallery_images
     SET like_count = GREATEST(like_count - 1, 0)
   WHERE id = OLD.gallery_image_id;
  RETURN OLD;
END;
$$;

CREATE TRIGGER trigger_increment_gallery_like_count
  AFTER INSERT ON public.gallery_likes
  FOR EACH ROW EXECUTE FUNCTION public.increment_gallery_like_count();

CREATE TRIGGER trigger_decrement_gallery_like_count
  AFTER DELETE ON public.gallery_likes
  FOR EACH ROW EXECUTE FUNCTION public.decrement_gallery_like_count();

-- -----------------------------------------------------------------------------
-- support_tickets
-- -----------------------------------------------------------------------------
CREATE TABLE public.support_tickets (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  user_email  TEXT NOT NULL,
  title       TEXT NOT NULL CHECK (char_length(title) <= 200),
  content     TEXT NOT NULL CHECK (char_length(content) BETWEEN 10 AND 5000),
  status      TEXT NOT NULL DEFAULT 'open'   CHECK (status   IN ('open','in_progress','resolved','closed')),
  priority    TEXT          DEFAULT 'normal' CHECK (priority IN ('low','normal','high','urgent')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);

CREATE INDEX support_tickets_user_id_idx    ON public.support_tickets (user_id);
CREATE INDEX support_tickets_status_idx     ON public.support_tickets (status);
CREATE INDEX support_tickets_created_at_idx ON public.support_tickets (created_at DESC);

ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "service_role full access on support_tickets"
  ON public.support_tickets FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := timezone('utc', now());
  RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_support_tickets_updated_at
  BEFORE UPDATE ON public.support_tickets
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- -----------------------------------------------------------------------------
-- webhook_rate_limits
-- -----------------------------------------------------------------------------
CREATE TABLE public.webhook_rate_limits (
  webhook_identifier TEXT PRIMARY KEY,
  last_sent_at       TIMESTAMPTZ NOT NULL
);

COMMENT ON TABLE public.webhook_rate_limits IS 'Last-sent timestamps for outgoing webhooks.';

ALTER TABLE public.webhook_rate_limits ENABLE ROW LEVEL SECURITY;

CREATE POLICY "service_role full access on webhook_rate_limits"
  ON public.webhook_rate_limits FOR ALL TO service_role USING (true) WITH CHECK (true);

-- -----------------------------------------------------------------------------
-- subscription_audit_log
-- -----------------------------------------------------------------------------
CREATE TABLE public.subscription_audit_log (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  event_type          TEXT NOT NULL CHECK (event_type IN (
                        'purchase_initiated','purchase_validated','purchase_failed',
                        'profile_updated','profile_update_failed',
                        'subscription_activated','subscription_expired','subscription_cancelled',
                        'acknowledgment_sent','acknowledgment_failed',
                        'sync_attempted','sync_completed','sync_failed')),
  product_id          TEXT,
  purchase_token      TEXT,
  subscription_tier   TEXT,
  subscription_status TEXT,
  expiry_date         TIMESTAMPTZ,
  cycle_start_date    TIMESTAMPTZ,
  previous_values     JSONB,
  new_values          JSONB,
  error_details       JSONB,
  metadata            JSONB,
  source              TEXT NOT NULL DEFAULT 'unknown' CHECK (source IN (
                        'mobile_app','validate_purchase_function','generation_status_function',
                        'manual_admin','system_trigger','unknown')),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
  created_by          TEXT
);

COMMENT ON TABLE public.subscription_audit_log IS 'Append-only audit trail for subscription operations.';

CREATE INDEX subscription_audit_log_user_id_idx        ON public.subscription_audit_log (user_id);
CREATE INDEX subscription_audit_log_event_type_idx     ON public.subscription_audit_log (event_type);
CREATE INDEX subscription_audit_log_created_at_idx     ON public.subscription_audit_log (created_at DESC);
CREATE INDEX subscription_audit_log_user_event_time_idx
  ON public.subscription_audit_log (user_id, event_type, created_at DESC);
CREATE INDEX subscription_audit_log_product_token_idx
  ON public.subscription_audit_log (product_id, purchase_token);

ALTER TABLE public.subscription_audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "service_role full access on subscription_audit_log"
  ON public.subscription_audit_log FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE OR REPLACE FUNCTION public.log_subscription_event(
  p_user_id             UUID,
  p_event_type          TEXT,
  p_product_id          TEXT        DEFAULT NULL,
  p_purchase_token      TEXT        DEFAULT NULL,
  p_subscription_tier   TEXT        DEFAULT NULL,
  p_subscription_status TEXT        DEFAULT NULL,
  p_expiry_date         TIMESTAMPTZ DEFAULT NULL,
  p_cycle_start_date    TIMESTAMPTZ DEFAULT NULL,
  p_previous_values     JSONB       DEFAULT NULL,
  p_new_values          JSONB       DEFAULT NULL,
  p_error_details       JSONB       DEFAULT NULL,
  p_metadata            JSONB       DEFAULT NULL,
  p_source              TEXT        DEFAULT 'unknown',
  p_created_by          TEXT        DEFAULT NULL
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE audit_id UUID;
BEGIN
  INSERT INTO public.subscription_audit_log (
    user_id, event_type, product_id, purchase_token,
    subscription_tier, subscription_status, expiry_date, cycle_start_date,
    previous_values, new_values, error_details, metadata, source, created_by
  ) VALUES (
    p_user_id, p_event_type, p_product_id, p_purchase_token,
    p_subscription_tier, p_subscription_status, p_expiry_date, p_cycle_start_date,
    p_previous_values, p_new_values, p_error_details, p_metadata, p_source, p_created_by
  ) RETURNING id INTO audit_id;
  RETURN audit_id;
END;
$$;

-- -----------------------------------------------------------------------------
-- failed_subscription_updates
-- -----------------------------------------------------------------------------
CREATE TABLE public.failed_subscription_updates (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                  UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  product_id               TEXT NOT NULL,
  purchase_token           TEXT NOT NULL,
  intended_update_payload  JSONB NOT NULL,
  error_code               TEXT,
  error_message            TEXT NOT NULL,
  error_context            JSONB,
  status                   TEXT NOT NULL DEFAULT 'pending_manual_review'
                             CHECK (status IN ('pending_manual_review','in_progress','resolved','failed')),
  retry_count              INT  NOT NULL DEFAULT 0,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
  resolved_at              TIMESTAMPTZ,
  resolved_by              TEXT,
  resolution_notes         TEXT
);

CREATE INDEX failed_subscription_updates_user_id_idx     ON public.failed_subscription_updates (user_id);
CREATE INDEX failed_subscription_updates_status_idx      ON public.failed_subscription_updates (status);
CREATE INDEX failed_subscription_updates_created_at_idx  ON public.failed_subscription_updates (created_at DESC);
CREATE INDEX failed_subscription_updates_product_id_idx  ON public.failed_subscription_updates (product_id);

ALTER TABLE public.failed_subscription_updates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "service_role full access on failed_subscription_updates"
  ON public.failed_subscription_updates FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE TRIGGER trigger_failed_subscription_updates_updated_at
  BEFORE UPDATE ON public.failed_subscription_updates
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- -----------------------------------------------------------------------------
-- Diagnostics
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.detect_duplicate_accounts_by_email(target_email TEXT)
RETURNS TABLE(
  user_id            UUID,
  email              TEXT,
  created_at         TIMESTAMPTZ,
  subscription_active BOOLEAN,
  subscription_tier  TEXT
) LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
  SELECT p.id, p.email, p.created_at, p.subscription_active, p.current_subscription_tier
    FROM public.profiles p
   WHERE p.email ILIKE target_email
   ORDER BY p.created_at DESC;
END;
$$;

CREATE OR REPLACE VIEW public.duplicate_accounts_monitor AS
  SELECT email,
         COUNT(*)                              AS account_count,
         array_agg(id          ORDER BY created_at DESC) AS user_ids,
         array_agg(created_at  ORDER BY created_at DESC) AS creation_dates,
         MAX(created_at)                       AS most_recent_creation
    FROM public.profiles
   WHERE email IS NOT NULL
   GROUP BY email
  HAVING COUNT(*) > 1;

COMMENT ON VIEW public.duplicate_accounts_monitor IS 'Detects multiple profiles sharing the same email.';
