-- PYP Stage 1 pgTAP Security & Behavior Test Suite
begin;
select plan(16);

-- Seed auth users
insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111', 'user_a@test.com');
insert into auth.users (id, email) values ('22222222-2222-2222-2222-222222222222', 'user_b@test.com');
insert into auth.users (id, email) values ('33333333-3333-3333-3333-333333333333', 'photo@test.com');
insert into auth.users (id, email) values ('44444444-4444-4444-4444-444444444444', 'published_photo@test.com');

-- TEST 1: Photographer registration creates an unpublished profile
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}', true);

select is(
  (
    select public.register_as_photographer(
      'Test Photographer',
      'Bio details',
      'Chennai',
      'Wedding',
      200000,
      '9876543210',
      'photo@test.com'
    ) is not null
  ),
  true,
  'Registration RPC completes successfully'
);

select is(
  (select is_published from public.photographer_profiles where user_id = '33333333-3333-3333-3333-333333333333'),
  false,
  'Test 1: Photographer registration must default to is_published = false'
);

-- TEST 2: Authenticated users cannot directly update is_published or protected fields
select throws_like(
  'update public.photographer_profiles set is_published = true where user_id = ''33333333-3333-3333-3333-333333333333''',
  '%permission denied%',
  'Test 2: Direct client update of is_published must be denied'
);

-- Admin publishes photographer for subsequent tests
reset role;
update public.photographer_profiles set is_published = true where user_id = '33333333-3333-3333-3333-333333333333';

-- Register second published photographer
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "44444444-4444-4444-4444-444444444444", "role": "authenticated"}', true);

select public.register_as_photographer(
  'Published Photo',
  'Bio details 2',
  'Mumbai',
  'Portrait',
  150000,
  '9876543211',
  'published_photo@test.com'
);

reset role;
update public.photographer_profiles set is_published = true where user_id = '44444444-4444-4444-4444-444444444444';

-- TEST 3: Profile reads respect RLS privacy boundaries
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}', true);

select is(
  (select count(*)::integer from public.profiles),
  3,
  'Test 3: Unrelated non-photographer profiles must be hidden by RLS'
);

-- TEST 5: Customers cannot create bookings for invalid or unpublished photographers
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}', true);

select public.register_as_photographer(
  'Unpublished Photo',
  'Bio',
  'Delhi',
  'Event',
  100000,
  '9876543212',
  'unpub@test.com'
);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}', true);

select throws_like(
  format('select public.create_booking_request((select id from public.photographer_profiles where user_id = %L), (current_date + 5)::date, %L, %L, %L)',
    '22222222-2222-2222-2222-222222222222', 'Delhi', 'Event', 'Note'),
  '%Photographer profile not found or inactive%',
  'Test 5: Booking an unpublished photographer must fail'
);

-- TEST 6: Booking price and 5% commission are calculated server-side
select is(
  (
    select public.create_booking_request(
      (select id from public.photographer_profiles where user_id = '44444444-4444-4444-4444-444444444444'),
      (current_date + 5)::date,
      'Mumbai',
      'Portrait',
      'Customer Note'
    ) is not null
  ),
  true,
  'Booking 1 created successfully'
);

select is(
  (select photographer_fee_paise from public.bookings limit 1),
  150000,
  'Test 6a: Fee must match starting price (150,000 paise)'
);

select is(
  (select commission_paise from public.bookings limit 1),
  7500,
  'Test 6b: Commission must be exactly 5% (7,500 paise)'
);

select is(
  (select total_amount_paise from public.bookings limit 1),
  157500,
  'Test 6c: Total amount must be fee + commission (157,500 paise)'
);

-- Create Booking 2
select public.create_booking_request(
  (select id from public.photographer_profiles where user_id = '33333333-3333-3333-3333-333333333333'),
  (current_date + 10)::date,
  'Chennai',
  'Wedding',
  'Note 2'
);

-- Photographer accepts Booking 1
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "44444444-4444-4444-4444-444444444444", "role": "authenticated"}', true);

select public.photographer_respond_booking(
  (select id from public.bookings where photographer_id = (select id from public.photographer_profiles where user_id = '44444444-4444-4444-4444-444444444444')),
  true
);

-- Customer prepares Booking 1 for payment
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}', true);

select public.prepare_booking_for_payment(
  (select id from public.bookings where photographer_id = (select id from public.photographer_profiles where user_id = '44444444-4444-4444-4444-444444444444'))
);

-- TEST 7: Payment completion rejects order IDs associated with another booking
reset role;

select private.process_payment_success(
  (select id from public.bookings where photographer_id = (select id from public.photographer_profiles where user_id = '44444444-4444-4444-4444-444444444444')),
  'order_rzp_001',
  'pay_rzp_001',
  157500
);

-- TEST 4: Customers cannot cancel bookings in confirmed state once payment is captured
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}', true);

select throws_like(
  format('select public.customer_cancel_booking(%L::uuid)',
    (select id from public.bookings where photographer_id = (select id from public.photographer_profiles where user_id = '44444444-4444-4444-4444-444444444444'))),
  '%cannot be cancelled directly by customer%',
  'Test 4: Cancelling in confirmed state must be rejected'
);

reset role;

select throws_like(
  format('select private.process_payment_success(%L::uuid, ''order_rzp_001'', ''pay_rzp_002'', 210000)',
    (select id from public.bookings where photographer_id = (select id from public.photographer_profiles where user_id = '33333333-3333-3333-3333-333333333333'))),
  '%belongs to a different booking%',
  'Test 7: Reusing order ID for a different booking must be rejected'
);

-- TEST 8: Duplicate payment completion cannot duplicate commission or payout records
select private.process_payment_success(
  (select id from public.bookings where photographer_id = (select id from public.photographer_profiles where user_id = '44444444-4444-4444-4444-444444444444')),
  'order_rzp_001',
  'pay_rzp_001',
  157500
);

select is(
  (select count(*)::integer from public.commission_ledger),
  1,
  'Test 8a: Commission ledger count must remain 1'
);

select is(
  (select count(*)::integer from public.payouts),
  1,
  'Test 8b: Payout record count must remain 1'
);

-- TEST 9 & 10: Cancelled/rejected bookings recorded for refund reconciliation
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}', true);

select public.customer_cancel_booking(
  (select id from public.bookings where photographer_id = (select id from public.photographer_profiles where user_id = '33333333-3333-3333-3333-333333333333'))
);

reset role;

select private.process_payment_success(
  (select id from public.bookings where photographer_id = (select id from public.photographer_profiles where user_id = '33333333-3333-3333-3333-333333333333')),
  'order_rzp_002',
  'pay_rzp_002',
  210000
);

select is(
  (select status::text from public.payments where provider_order_id = 'order_rzp_002'),
  'captured',
  'Test 10a: Payment on cancelled booking captured for audit'
);

-- TEST 11: Untrusted roles cannot execute private payment-processing functions
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}', true);

select throws_like(
  format('select private.process_payment_success(%L::uuid, ''order_hack'', ''pay_hack'', 100)',
    (select id from public.bookings limit 1)),
  '%permission denied%',
  'Test 11: Authenticated user cannot execute private.process_payment_success'
);

-- TEST 12: SECURITY DEFINER functions use safe search path
reset role;

select is(
  (
    select count(*)::integer
    from pg_proc p
    join pg_namespace n on n.nspname in ('public', 'private')
    where n.nspname in ('public', 'private')
      and p.prosecdef = true
      and (p.proconfig is null or not array_to_string(p.proconfig, ',') like '%search_path=%')
  ),
  0,
  'Test 12: All SECURITY DEFINER functions have explicit empty search_path set'
);

select * from finish();
rollback;
