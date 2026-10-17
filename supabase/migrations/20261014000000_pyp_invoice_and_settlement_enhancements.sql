-- PYP Forward Migration: Invoice Data RPC & Settlement Tracking Enhancements
-- File: supabase/migrations/20261014000000_pyp_invoice_and_settlement_enhancements.sql

-- 1. Helper function to check if caller is an admin
CREATE OR REPLACE FUNCTION private.is_admin_user(p_user_id uuid DEFAULT auth.uid())
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

REVOKE ALL ON FUNCTION private.is_admin_user FROM public, anon, authenticated;

-- 2. RPC to fetch authoritative booking invoice data for authorized participants
CREATE OR REPLACE FUNCTION public.get_booking_invoice_data(
  p_booking_id uuid
) RETURNS TABLE (
  out_booking_id uuid,
  out_invoice_number text,
  out_issue_date timestamptz,
  out_customer_name text,
  out_customer_phone text,
  out_photographer_name text,
  out_event_date date,
  out_event_city text,
  out_event_type text,
  out_photographer_fee_paise integer,
  out_commission_paise integer,
  out_total_amount_paise integer,
  out_booking_status public.booking_status,
  out_payment_status text,
  out_provider_order_id text,
  out_provider_payment_id text,
  out_verified_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_booking record;
  v_payment record;
  v_photo_user_id uuid;
  v_photo_name text;
  v_cust_name text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthenticated user';
  END IF;

  SELECT b.*, pp.user_id AS photo_user_id, pp.display_name AS photo_display_name
  INTO v_booking
  FROM public.bookings b
  JOIN public.photographer_profiles pp ON pp.id = b.photographer_id
  WHERE b.id = p_booking_id;

  IF v_booking.id IS NULL THEN
    RAISE EXCEPTION 'Booking not found';
  END IF;

  -- Security check: Caller must be the booking customer, the photographer, or an admin
  IF v_booking.customer_id != v_user_id
     AND v_booking.photo_user_id != v_user_id
     AND NOT private.is_admin_user(v_user_id) THEN
    RAISE EXCEPTION 'Unauthorized: Access denied to booking invoice';
  END IF;

  -- Fetch verified captured payment if available
  SELECT * INTO v_payment
  FROM public.payments
  WHERE booking_id = p_booking_id
  ORDER BY verified_at DESC NULLS LAST, created_at DESC
  LIMIT 1;

  v_photo_name := coalesce(v_booking.photo_display_name, 'Photographer');
  v_cust_name := coalesce(v_booking.customer_name, 'Client');

  RETURN QUERY
  SELECT
    v_booking.id AS out_booking_id,
    'INV-' || to_char(v_booking.created_at, 'YYYYMMDD') || '-' || upper(substring(v_booking.id::text from 1 for 8)) AS out_invoice_number,
    v_booking.created_at AS out_issue_date,
    v_cust_name AS out_customer_name,
    v_booking.customer_phone AS out_customer_phone,
    v_photo_name AS out_photographer_name,
    v_booking.event_date AS out_event_date,
    v_booking.event_city AS out_event_city,
    v_booking.event_type AS out_event_type,
    v_booking.photographer_fee_paise AS out_photographer_fee_paise,
    v_booking.commission_paise AS out_commission_paise,
    v_booking.total_amount_paise AS out_total_amount_paise,
    v_booking.status AS out_booking_status,
    coalesce(v_payment.status::text, 'unpaid') AS out_payment_status,
    v_payment.provider_order_id AS out_provider_order_id,
    v_payment.provider_payment_id AS out_provider_payment_id,
    v_payment.verified_at AS out_verified_at;
END;
$$;

REVOKE ALL ON FUNCTION public.get_booking_invoice_data FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_booking_invoice_data TO authenticated;
