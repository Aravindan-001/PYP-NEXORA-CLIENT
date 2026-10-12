-- PYP Concurrency, Cancellation, Webhook & Refund Test Suite
begin;
select plan(11);

-- Seed auth users
insert into auth.users (id, email) values ('55555555-5555-5555-5555-555555555555', 'cust_conc@test.com');
insert into auth.users (id, email) values ('66666666-6666-6666-6666-666666666666', 'photo_conc@test.com');

-- Register photographer and publish
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "66666666-6666-6666-6666-666666666666", "role": "authenticated"}', true);

select public.register_as_photographer(
  'Conc Photo',
  'Bio',
  'Bangalore',
  'Event',
  200000,
  '9123456789',
  'photo_conc@test.com'
);

reset role;
update public.photographer_profiles set is_published = true where user_id = '66666666-6666-6666-6666-666666666666';

-- Customer creates booking
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "55555555-5555-5555-5555-555555555555", "role": "authenticated"}', true);

select public.create_booking_request(
  (select id from public.photographer_profiles where user_id = '66666666-6666-6666-6666-666666666666'),
  (current_date + 7)::date,
  'Bangalore',
  'Event',
  'Conc Test Note'
);

-- Photographer accepts booking
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "66666666-6666-6666-6666-666666666666", "role": "authenticated"}', true);

select public.photographer_respond_booking(
  (select id from public.bookings where photographer_id = (select id from public.photographer_profiles where user_id = '66666666-6666-6666-6666-666666666666')),
  true
);

-- TEST 1: prepare_booking_for_payment transitions accepted booking to awaiting_payment
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "55555555-5555-5555-5555-555555555555", "role": "authenticated"}', true);

select is(
  (
    select (public.prepare_booking_for_payment(
      (select id from public.bookings where photographer_id = (select id from public.photographer_profiles where user_id = '66666666-6666-6666-6666-666666666666'))
    )).out_status::text
  ),
  'awaiting_payment',
  'Test 1: Booking status transitions to awaiting_payment'
);

-- TEST 2 & 3: Insert pending payment record and verify prepare_booking_for_payment reuses existing pending order
reset role;

insert into public.payments (
  booking_id,
  provider,
  provider_order_id,
  amount_paise,
  status
) values (
  (select id from public.bookings where photographer_id = (select id from public.photographer_profiles where user_id = '66666666-6666-6666-6666-666666666666')),
  'razorpay',
  'order_pending_001',
  210000,
  'pending'
);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "55555555-5555-5555-5555-555555555555", "role": "authenticated"}', true);

select is(
  (
    select (public.prepare_booking_for_payment(
      (select id from public.bookings where photographer_id = (select id from public.photographer_profiles where user_id = '66666666-6666-6666-6666-666666666666'))
    )).out_existing_provider_order_id
  ),
  'order_pending_001',
  'Test 3: Existing pending order is safely returned'
);

-- TEST 4: Partial unique index blocks simultaneous second pending payment
reset role;

select throws_like(
  format('insert into public.payments (booking_id, provider, provider_order_id, amount_paise, status) values (%L::uuid, ''razorpay'', ''order_pending_002'', 210000, ''pending'')',
    (select id from public.bookings where photographer_id = (select id from public.photographer_profiles where user_id = '66666666-6666-6666-6666-666666666666'))),
  '%payments_pending_booking_idx%',
  'Test 4: Concurrent second pending payment is blocked by partial unique index'
);

-- TEST 5: Customer can cancel booking from awaiting_payment when no captured payment exists
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "55555555-5555-5555-5555-555555555555", "role": "authenticated"}', true);

select public.customer_cancel_booking(
  (select id from public.bookings where photographer_id = (select id from public.photographer_profiles where user_id = '66666666-6666-6666-6666-666666666666'))
);

select is(
  (select status::text from public.bookings where photographer_id = (select id from public.photographer_profiles where user_id = '66666666-6666-6666-6666-666666666666')),
  'cancelled',
  'Test 5a: Booking in awaiting_payment cancelled successfully'
);

select is(
  (select status::text from public.payments where provider_order_id = 'order_pending_001'),
  'failed',
  'Test 5b: Pending payment updated to failed upon cancellation'
);

-- TEST 6: Payment capture on cancelled booking records payment for refund reconciliation without confirming booking
reset role;

select private.process_payment_success(
  (select id from public.bookings where photographer_id = (select id from public.photographer_profiles where user_id = '66666666-6666-6666-6666-666666666666')),
  'order_pending_001',
  'pay_captured_001',
  210000
);

select is(
  (select status::text from public.bookings where photographer_id = (select id from public.photographer_profiles where user_id = '66666666-6666-6666-6666-666666666666')),
  'cancelled',
  'Test 6: Booking status remains cancelled after late payment capture'
);

-- TEST 7: Customer cannot cancel a booking if a captured payment exists
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "55555555-5555-5555-5555-555555555555", "role": "authenticated"}', true);

select throws_like(
  format('select public.customer_cancel_booking(%L::uuid)',
    (select id from public.bookings where photographer_id = (select id from public.photographer_profiles where user_id = '66666666-6666-6666-6666-666666666666'))),
  '%cannot be cancelled directly by customer%',
  'Test 7: Cancellation blocked when captured payment exists'
);

-- TEST 8, 9, 10: Setup confirmed booking with payment and payout for refund test
reset role;

insert into public.bookings (
  id, customer_id, photographer_id, event_date, event_city, event_type, status, photographer_fee_paise, commission_paise
) values (
  '77777777-7777-7777-7777-777777777777',
  '55555555-5555-5555-5555-555555555555',
  (select id from public.photographer_profiles where user_id = '66666666-6666-6666-6666-666666666666'),
  current_date + 10,
  'Bangalore',
  'Wedding',
  'accepted',
  200000,
  10000
);

select private.process_payment_success(
  '77777777-7777-7777-7777-777777777777',
  'order_refund_test',
  'pay_refund_test',
  210000
);

-- TEST 9: Partial refund updates payment status to partially_refunded and leaves payout pending
select private.process_refund_success('pay_refund_test', 100000);

select is(
  (select status::text from public.payments where provider_payment_id = 'pay_refund_test'),
  'partially_refunded',
  'Test 9a: Partial refund sets payment status to partially_refunded'
);

select is(
  (select status::text from public.payouts where booking_id = '77777777-7777-7777-7777-777777777777'),
  'pending',
  'Test 9b: Partial refund keeps payout pending'
);

-- TEST 10: Full refund updates payment status to refunded and reverses pending payout
select private.process_refund_success('pay_refund_test', 210000);

select is(
  (select status::text from public.payments where provider_payment_id = 'pay_refund_test'),
  'refunded',
  'Test 10a: Full refund sets payment status to refunded'
);

select is(
  (select status::text from public.payouts where booking_id = '77777777-7777-7777-7777-777777777777'),
  'reversed',
  'Test 10b: Full refund reverses pending payout'
);

select * from finish();
rollback;
