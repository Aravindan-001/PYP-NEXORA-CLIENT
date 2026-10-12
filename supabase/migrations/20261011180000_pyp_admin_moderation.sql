-- PYP: Admin Photographer Moderation RPCs
-- Forward-only migration

-- 1. RPC for admins to list pending (unpublished) photographer profiles
CREATE OR REPLACE FUNCTION public.admin_get_pending_photographers()
RETURNS TABLE (
  out_id uuid,
  out_user_id uuid,
  out_display_name text,
  out_bio text,
  out_city text,
  out_category text,
  out_starting_price_paise integer,
  out_created_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_admin_id uuid := auth.uid();
BEGIN
  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'Unauthenticated user';
  END IF;

  -- Server-verified admin role check
  IF NOT EXISTS (
    SELECT 1 FROM public.user_roles ur
    WHERE ur.user_id = v_admin_id AND ur.role = 'admin'
  ) THEN
    RAISE EXCEPTION 'Access denied: Admin role required';
  END IF;

  RETURN QUERY
    SELECT
      p.id,
      p.user_id,
      p.display_name,
      p.bio,
      p.city,
      p.category,
      p.starting_price_paise,
      p.created_at
    FROM public.photographer_profiles p
    WHERE p.is_published = false
    ORDER BY p.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_get_pending_photographers FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_pending_photographers TO authenticated;

-- 2. RPC for admins to moderate (approve/publish or reject) a photographer profile
CREATE OR REPLACE FUNCTION public.admin_moderate_photographer(
  p_photographer_id uuid,
  p_approve boolean
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_admin_id uuid := auth.uid();
BEGIN
  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'Unauthenticated user';
  END IF;

  -- Server-verified admin role check
  IF NOT EXISTS (
    SELECT 1 FROM public.user_roles ur
    WHERE ur.user_id = v_admin_id AND ur.role = 'admin'
  ) THEN
    RAISE EXCEPTION 'Access denied: Admin role required';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.photographer_profiles pp
    WHERE pp.id = p_photographer_id
  ) THEN
    RAISE EXCEPTION 'Photographer profile not found';
  END IF;

  UPDATE public.photographer_profiles
  SET is_published = p_approve, updated_at = now()
  WHERE id = p_photographer_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_moderate_photographer FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_moderate_photographer TO authenticated;
