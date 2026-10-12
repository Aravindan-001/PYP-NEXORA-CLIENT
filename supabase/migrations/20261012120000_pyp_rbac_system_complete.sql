-- PYP: Comprehensive Role-Based Access Control (RBAC) & Governance System
-- Forward-only migration

-- 1. Recursion-safe helper functions in private schema
CREATE OR REPLACE FUNCTION private.is_admin(p_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = p_user_id AND role = 'admin'
  );
$$;

REVOKE ALL ON FUNCTION private.is_admin FROM public, anon;
GRANT EXECUTE ON FUNCTION private.is_admin TO authenticated;

CREATE OR REPLACE FUNCTION private.is_photographer(p_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = p_user_id AND role = 'photographer'
  );
$$;

REVOKE ALL ON FUNCTION private.is_photographer FROM public, anon;
GRANT EXECUTE ON FUNCTION private.is_photographer TO authenticated;

CREATE OR REPLACE FUNCTION private.is_customer(p_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = p_user_id AND role = 'customer'
  );
$$;

REVOKE ALL ON FUNCTION private.is_customer FROM public, anon;
GRANT EXECUTE ON FUNCTION private.is_customer TO authenticated;

-- 2. Secure Admin Provisioning Procedure
-- Allows authorized administrative provisioning via SQL without exposing admin role to public signups.
CREATE OR REPLACE FUNCTION private.provision_admin(p_email text)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid;
  v_clean_email text := lower(trim(coalesce(p_email, '')));
BEGIN
  IF v_clean_email = '' THEN
    RAISE EXCEPTION 'Email address is required';
  END IF;

  SELECT id INTO v_user_id
  FROM auth.users
  WHERE lower(email) = v_clean_email;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'User with email % not found in auth.users', p_email;
  END IF;

  -- Insert admin role
  INSERT INTO public.user_roles (user_id, role)
  VALUES (v_user_id, 'admin')
  ON CONFLICT (user_id, role) DO NOTHING;

  -- Ensure customer role is also present
  INSERT INTO public.user_roles (user_id, role)
  VALUES (v_user_id, 'customer')
  ON CONFLICT (user_id, role) DO NOTHING;

  RETURN v_user_id;
END;
$$;

REVOKE ALL ON FUNCTION private.provision_admin FROM public, anon, authenticated;

-- 3. Enhanced Signup Trigger (Guarantees Admin Role cannot be self-assigned)
CREATE OR REPLACE FUNCTION private.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_requested_role text := lower(trim(coalesce(new.raw_user_meta_data ->> 'requested_role', 'customer')));
  v_full_name text := nullif(trim(coalesce(new.raw_user_meta_data ->> 'full_name', '')), '');
BEGIN
  -- Insert base user profile
  INSERT INTO public.profiles (id, full_name)
  VALUES (new.id, v_full_name)
  ON CONFLICT (id) DO UPDATE SET full_name = excluded.full_name;

  -- Grant customer role by default to all accounts
  INSERT INTO public.user_roles (user_id, role)
  VALUES (new.id, 'customer')
  ON CONFLICT (user_id, role) DO NOTHING;

  -- Handle photographer registration request (STRICTLY DENIES 'admin' role)
  IF v_requested_role = 'photographer' THEN
    INSERT INTO public.user_roles (user_id, role)
    VALUES (new.id, 'photographer')
    ON CONFLICT (user_id, role) DO NOTHING;

    -- Create initial pending photographer profile requiring admin moderation
    INSERT INTO public.photographer_profiles (
      user_id, display_name, city, category, starting_price_paise, is_published
    )
    VALUES (
      new.id,
      coalesce(v_full_name, 'New Photographer'),
      'City Pending',
      'General',
      100000,
      false
    )
    ON CONFLICT (user_id) DO NOTHING;

    -- Create empty private details row
    INSERT INTO public.photographer_private_details (photographer_id, email)
    SELECT id, new.email
    FROM public.photographer_profiles
    WHERE user_id = new.id
    ON CONFLICT (photographer_id) DO NOTHING;
  END IF;

  RETURN new;
END;
$$;

-- 4. Admin Management RPCs
-- Platform Overview Statistics
CREATE OR REPLACE FUNCTION public.admin_get_platform_stats()
RETURNS TABLE (
  total_clients integer,
  total_photographers integer,
  pending_photographers integer,
  approved_photographers integer,
  total_bookings integer,
  active_bookings integer,
  total_revenue_paise bigint
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_admin_id uuid := auth.uid();
BEGIN
  IF v_admin_id IS NULL OR NOT private.is_admin(v_admin_id) THEN
    RAISE EXCEPTION 'Access denied: Admin role required';
  END IF;

  RETURN QUERY
  SELECT
    (SELECT count(DISTINCT user_id)::integer FROM public.user_roles WHERE role = 'customer') AS total_clients,
    (SELECT count(*)::integer FROM public.photographer_profiles) AS total_photographers,
    (SELECT count(*)::integer FROM public.photographer_profiles WHERE is_published = false) AS pending_photographers,
    (SELECT count(*)::integer FROM public.photographer_profiles WHERE is_published = true) AS approved_photographers,
    (SELECT count(*)::integer FROM public.bookings) AS total_bookings,
    (SELECT count(*)::integer FROM public.bookings WHERE status IN ('requested', 'accepted', 'awaiting_payment', 'confirmed')) AS active_bookings,
    coalesce((SELECT sum(total_amount_paise)::bigint FROM public.bookings WHERE status IN ('confirmed', 'completed')), 0) AS total_revenue_paise;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_get_platform_stats FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_platform_stats TO authenticated;

-- List All Photographers with Private Details for Admin Moderation
CREATE OR REPLACE FUNCTION public.admin_get_all_photographers()
RETURNS TABLE (
  out_id uuid,
  out_user_id uuid,
  out_display_name text,
  out_bio text,
  out_city text,
  out_category text,
  out_starting_price_paise integer,
  out_portfolio_urls text[],
  out_is_published boolean,
  out_created_at timestamptz,
  out_phone text,
  out_email text
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_admin_id uuid := auth.uid();
BEGIN
  IF v_admin_id IS NULL OR NOT private.is_admin(v_admin_id) THEN
    RAISE EXCEPTION 'Access denied: Admin role required';
  END IF;

  RETURN QUERY
  SELECT
    pp.id,
    pp.user_id,
    pp.display_name,
    pp.bio,
    pp.city,
    pp.category,
    pp.starting_price_paise,
    pp.portfolio_urls,
    pp.is_published,
    pp.created_at,
    pd.phone AS out_phone,
    pd.email AS out_email
  FROM public.photographer_profiles pp
  LEFT JOIN public.photographer_private_details pd ON pd.photographer_id = pp.id
  ORDER BY pp.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_get_all_photographers FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_all_photographers TO authenticated;

-- List All Registered Clients for Admin Management
CREATE OR REPLACE FUNCTION public.admin_get_all_clients()
RETURNS TABLE (
  out_id uuid,
  out_full_name text,
  out_avatar_url text,
  out_city text,
  out_email text,
  out_created_at timestamptz,
  out_total_bookings integer
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_admin_id uuid := auth.uid();
BEGIN
  IF v_admin_id IS NULL OR NOT private.is_admin(v_admin_id) THEN
    RAISE EXCEPTION 'Access denied: Admin role required';
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.full_name,
    p.avatar_url,
    p.city,
    u.email AS out_email,
    p.created_at,
    (SELECT count(*)::integer FROM public.bookings b WHERE b.customer_id = p.id) AS out_total_bookings
  FROM public.profiles p
  JOIN auth.users u ON u.id = p.id
  ORDER BY p.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_get_all_clients FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_all_clients TO authenticated;

-- Admin Manage / Moderate Photographer Account Status (Approve, Reject, Suspend, Reactivate)
DROP FUNCTION IF EXISTS public.admin_manage_photographer_status(uuid, boolean);

CREATE OR REPLACE FUNCTION public.admin_manage_photographer_status(
  p_photographer_id uuid,
  p_action text
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_admin_id uuid := auth.uid();
  v_clean_action text := lower(trim(coalesce(p_action, '')));
BEGIN
  IF v_admin_id IS NULL OR NOT private.is_admin(v_admin_id) THEN
    RAISE EXCEPTION 'Access denied: Admin role required';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.photographer_profiles WHERE id = p_photographer_id) THEN
    RAISE EXCEPTION 'Photographer profile not found';
  END IF;

  IF v_clean_action IN ('approve', 'reactivate', 'publish') THEN
    UPDATE public.photographer_profiles
    SET is_published = true, updated_at = now()
    WHERE id = p_photographer_id;
  ELSIF v_clean_action IN ('reject', 'suspend', 'unpublish') THEN
    UPDATE public.photographer_profiles
    SET is_published = false, updated_at = now()
    WHERE id = p_photographer_id;
  ELSE
    RAISE EXCEPTION 'Invalid moderation action. Allowed: approve, reject, suspend, reactivate';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_manage_photographer_status FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_manage_photographer_status TO authenticated;

-- 5. Admin Row Level Security Policies
-- Ensures admins can read and audit platform data across tables

DROP POLICY IF EXISTS "Admins can view all user roles" ON public.user_roles;
CREATE POLICY "Admins can view all user roles"
  ON public.user_roles FOR SELECT TO authenticated
  USING (private.is_admin());

DROP POLICY IF EXISTS "Admins can view all photographer profiles" ON public.photographer_profiles;
CREATE POLICY "Admins can view all photographer profiles"
  ON public.photographer_profiles FOR SELECT TO authenticated
  USING (private.is_admin());

DROP POLICY IF EXISTS "Admins can view all photographer private details" ON public.photographer_private_details;
CREATE POLICY "Admins can view all photographer private details"
  ON public.photographer_private_details FOR SELECT TO authenticated
  USING (private.is_admin());

DROP POLICY IF EXISTS "Admins can view all bookings" ON public.bookings;
CREATE POLICY "Admins can view all bookings"
  ON public.bookings FOR SELECT TO authenticated
  USING (private.is_admin());

DROP POLICY IF EXISTS "Admins can view all profiles" ON public.profiles;
CREATE POLICY "Admins can view all profiles"
  ON public.profiles FOR SELECT TO authenticated
  USING (private.is_admin());
