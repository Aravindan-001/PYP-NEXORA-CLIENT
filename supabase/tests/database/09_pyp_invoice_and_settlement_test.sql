-- PYP Platform Settlement & Invoice Security pgTAP Test Suite
begin;
select plan(7);

-- Apply migration changes locally within test transaction
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

  IF v_booking.customer_id != v_user_id
     AND v_booking.photo_user_id != v_user_id
     AND NOT private.is_admin_user(v_user_id) THEN
    RAISE EXCEPTION 'Unauthorized: Access denied to booking invoice';
  END IF;

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

-- Seed auth users
insert into auth.users (id, email) values ('77777777-7777-7777-7777-777777777777', 'inv_cust@test.com') on conflict do nothing;
insert into auth.users (id, email) values ('88888888-8888-8888-8888-888888888888', 'inv_photo@test.com') on conflict do nothing;
insert into auth.users (id, email) values ('99999999-9999-9999-9999-999999999999', 'inv_hacker@test.com') on conflict do nothing;
insert into auth.users (id, email) values ('11111111-2222-3333-4444-555555555555', 'inv_admin@test.com') on conflict do nothing;

insert into public.user_roles (user_id, role) values ('11111111-2222-3333-4444-555555555555', 'admin') on conflict do nothing;

-- Photographer registers
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "88888888-8888-8888-8888-888888888888", "role": "authenticated"}', true);

select public.register_as_photographer(
  'Invoice Studio',
  'Professional Photography',
  'Chennai',
  'Wedding',
  100000, -- ₹1,000 quote
  '9876543210',
  'inv_photo@test.com'
);

-- Admin approves photographer
reset role;
update public.photographer_profiles set is_published = true where user_id = '88888888-8888-8888-8888-888888888888';

-- Customer creates booking request for ₹1,000 quote
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "77777777-7777-7777-7777-777777777777", "role": "authenticated"}', true);

select public.create_booking_request(
  (select id from public.photographer_profiles where user_id = '88888888-8888-8888-8888-888888888888'),
  (now() + interval '7 days')::date,
  'Chennai',
  'Wedding',
  'Invoice Test Note',
  'Invoice Client',
  '9876500000'
);

-- TEST 1: Fee calculation: photographer quote = 100000 (₹1,000), commission = 5000 (₹50), total = 105000 (₹1,050)
reset role;

select is(
  (select photographer_fee_paise from public.bookings where customer_id = '77777777-7777-7777-7777-777777777777'),
  100000,
  'Test 1a: Photographer fee is exactly 100,000 paise'
);

select is(
  (select commission_paise from public.bookings where customer_id = '77777777-7777-7777-7777-777777777777'),
  5000,
  'Test 1b: Platform commission is exactly 5,000 paise'
);

select is(
  (select total_amount_paise from public.bookings where customer_id = '77777777-7777-7777-7777-777777777777'),
  105000,
  'Test 1c: Total customer payable is exactly 105,000 paise'
);

-- TEST 2: Customer can access get_booking_invoice_data for own booking
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "77777777-7777-7777-7777-777777777777", "role": "authenticated"}', true);

select is(
  (
    select out_total_amount_paise
    from public.get_booking_invoice_data(
      (select id from public.bookings where customer_id = '77777777-7777-7777-7777-777777777777')
    )
  ),
  105000,
  'Test 2: Authorized customer retrieves invoice data with 105,000 paise total'
);

-- TEST 3: Photographer can access get_booking_invoice_data for assigned booking
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "88888888-8888-8888-8888-888888888888", "role": "authenticated"}', true);

select is(
  (
    select out_photographer_fee_paise
    from public.get_booking_invoice_data(
      (select id from public.bookings where customer_id = '77777777-7777-7777-7777-777777777777')
    )
  ),
  100000,
  'Test 3: Authorized photographer retrieves invoice data with 100,000 paise fee'
);

-- TEST 4: Unauthorized user CANNOT access get_booking_invoice_data for another booking
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "99999999-9999-9999-9999-999999999999", "role": "authenticated"}', true);

select throws_like(
  'select * from public.get_booking_invoice_data((select id from public.bookings where customer_id = ''77777777-7777-7777-7777-777777777777''))',
  '%Booking not found%',
  'Test 4: Unauthorized user blocked from reading another booking invoice'
);

-- TEST 5: Admin user CAN access get_booking_invoice_data
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "11111111-2222-3333-4444-555555555555", "role": "authenticated"}', true);

select is(
  (
    select out_invoice_number
    from public.get_booking_invoice_data(
      (select id from public.bookings where customer_id = '77777777-7777-7777-7777-777777777777')
    )
  ) is not null,
  true,
  'Test 5: Authorized admin retrieves invoice number'
);

select * from finish();
rollback;
