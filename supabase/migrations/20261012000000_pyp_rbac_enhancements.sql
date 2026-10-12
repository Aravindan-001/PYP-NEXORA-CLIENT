-- PYP: Role-Based Access Control (RBAC) & Administrative Governance Enhancements
-- Forward-only migration

-- 1. Helper functions in private schema for recursion-safe role checks
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

REVOKE ALL ON FUNCTION private.is_admin FROM public, anon, authenticated;

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

REVOKE ALL ON FUNCTION private.is_photographer FROM public, anon, authenticated;

-- 2. Enhanced handle_new_user trigger supporting Client vs Photographer signup
CREATE OR REPLACE FUNCTION private.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_role text := trim(coalesce(new.raw_user_meta_data ->> 'requested_role', 'customer'));
  v_full_name text := nullif(trim(coalesce(new.raw_user_meta_data ->> 'full_name', '')), '');
BEGIN
  -- Always insert base user profile
  INSERT INTO public.profiles (id, full_name)
  VALUES (new.id, v_full_name)
  ON CONFLICT (id) DO UPDATE SET full_name = excluded.full_name;

  -- Customer role is granted to all new users
  INSERT INTO public.user_roles (user_id, role)
  VALUES (new.id, 'customer')
  ON CONFLICT (user_id, role) DO NOTHING;

  -- Photographer requested role assignment (STRICTLY IGNORES 'admin' metadata)
  IF v_role = 'photographer' THEN
    INSERT INTO public.user_roles (user_id, role)
    VALUES (new.id, 'photographer')
    ON CONFLICT (user_id, role) DO NOTHING;

    -- Create initial pending photographer profile requiring admin approval
    INSERT INTO public.photographer_profiles (
      user_id, display_name, city, category, starting_price_paise, is_published
    )
    VALUES (
      new.id,
      coalesce(v_full_name, 'New Photographer'),
      'Select City',
      'General',
      100000,
      false
    )
    ON CONFLICT (user_id) DO NOTHING;
  END IF;

  RETURN new;
END;
$$;

-- 3. Admin RLS Policies for comprehensive platform governance
DROP POLICY IF EXISTS "Admins can view all user roles" ON public.user_roles;
CREATE POLICY "Admins can view all user roles"
  ON public.user_roles FOR SELECT TO authenticated
  USING (private.is_admin());

DROP POLICY IF EXISTS "Admins can view all photographer profiles" ON public.photographer_profiles;
CREATE POLICY "Admins can view all photographer profiles"
  ON public.photographer_profiles FOR SELECT TO authenticated
  USING (private.is_admin());

DROP POLICY IF EXISTS "Admins can view all bookings" ON public.bookings;
CREATE POLICY "Admins can view all bookings"
  ON public.bookings FOR SELECT TO authenticated
  USING (private.is_admin());

DROP POLICY IF EXISTS "Admins can view all profiles" ON public.profiles;
CREATE POLICY "Admins can view all profiles"
  ON public.profiles FOR SELECT TO authenticated
  USING (private.is_admin());

-- 4. Admin RPC: Platform Statistics
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

-- 5. Admin RPC: Fetch All Bookings
CREATE OR REPLACE FUNCTION public.admin_get_all_bookings()
RETURNS TABLE (
  out_id uuid,
  out_customer_id uuid,
  out_photographer_id uuid,
  out_photographer_name text,
  out_customer_name text,
  out_event_date date,
  out_event_city text,
  out_event_type text,
  out_status public.booking_status,
  out_total_amount_paise integer,
  out_created_at timestamptz
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
    b.id,
    b.customer_id,
    b.photographer_id,
    pp.display_name AS out_photographer_name,
    coalesce(p.full_name, 'Customer') AS out_customer_name,
    b.event_date,
    b.event_city,
    b.event_type,
    b.status,
    b.total_amount_paise,
    b.created_at
  FROM public.bookings b
  JOIN public.photographer_profiles pp ON pp.id = b.photographer_id
  LEFT JOIN public.profiles p ON p.id = b.customer_id
  ORDER BY b.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_get_all_bookings FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_all_bookings TO authenticated;

-- 6. Admin RPC: Moderate / Approve / Reject Photographer Status
CREATE OR REPLACE FUNCTION public.admin_manage_photographer_status(
  p_photographer_id uuid,
  p_approve boolean
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_admin_id uuid := auth.uid();
BEGIN
  IF v_admin_id IS NULL OR NOT private.is_admin(v_admin_id) THEN
    RAISE EXCEPTION 'Access denied: Admin role required';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.photographer_profiles WHERE id = p_photographer_id) THEN
    RAISE EXCEPTION 'Photographer profile not found';
  END IF;

  UPDATE public.photographer_profiles
  SET is_published = p_approve, updated_at = now()
  WHERE id = p_photographer_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_manage_photographer_status FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_manage_photographer_status TO authenticated;
