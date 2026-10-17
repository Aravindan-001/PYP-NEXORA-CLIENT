-- PYP Refund Security, Auditable Ledger & Payout Reconciliation pgTAP Test Suite
begin;
select plan(13);

-- Apply migration changes locally within test transaction
CREATE TABLE IF NOT EXISTS public.refunds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_id uuid NOT NULL REFERENCES public.payments(id) ON DELETE CASCADE,
  booking_id uuid NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
  provider_refund_id text UNIQUE,
  amount_paise integer NOT NULL CHECK (amount_paise > 0),
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Seed auth users
insert into auth.users (id, email) values ('12121212-1212-1212-1212-121212121212', 'refund_cust@test.com') on conflict do nothing;
insert into auth.users (id, email) values ('13131313-1313-1313-1313-131313131313', 'refund_photo@test.com') on conflict do nothing;
insert into auth.users (id, email) values ('14141414-1414-1414-1414-141414141414', 'refund_hacker@test.com') on conflict do nothing;

-- Photographer registers and gets approved
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "13131313-1313-1313-1313-131313131313", "role": "authenticated"}', true);

select public.register_as_photographer(
  'Refund Studio',
  'Bio',
  'Chennai',
  'Wedding',
  100000, -- ₹1,000 quote
  '9876543210',
  'refund_photo@test.com'
);

reset role;
update public.photographer_profiles set is_published = true where user_id = '13131313-1313-1313-1313-131313131313';

-- Customer creates booking and pays deposit (105,000 paise total)
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "12121212-1212-1212-1212-121212121212", "role": "authenticated"}', true);

select public.create_booking_request(
  (select id from public.photographer_profiles where user_id = '13131313-1313-1313-1313-131313131313'),
  (current_date + 7)::date,
  'Chennai',
  'Wedding',
  'Refund Test'
);

reset role;

select private.process_payment_success(
  (select id from public.bookings where customer_id = '12121212-1212-1212-1212-121212121212'),
  'order_ref_001',
  'pay_ref_001',
  105000
);

-- TEST 1: Rejects NULL refund amount
select throws_like(
  'select private.process_refund_success(''pay_ref_001'', NULL, ''rfnd_err_01'')',
  '%Invalid refund amount%',
  'Test 1: Rejects NULL refund amount'
);

-- TEST 2: Rejects zero or negative refund amount
select throws_like(
  'select private.process_refund_success(''pay_ref_001'', 0, ''rfnd_err_02'')',
  '%Invalid refund amount%',
  'Test 2a: Rejects zero refund amount'
);

select throws_like(
  'select private.process_refund_success(''pay_ref_001'', -500, ''rfnd_err_03'')',
  '%Invalid refund amount%',
  'Test 2b: Rejects negative refund amount'
);

-- TEST 3: Rejects refund amount exceeding captured payment (105,000 paise captured)
select throws_like(
  'select private.process_refund_success(''pay_ref_001'', 150000, ''rfnd_err_04'')',
  '%exceeds captured payment amount%',
  'Test 3: Rejects refund exceeding captured payment amount'
);

-- TEST 4: First partial refund (40,000 paise) sets status to partially_refunded and records in refunds ledger
select lives_ok(
  'select private.process_refund_success(''pay_ref_001'', 40000, ''rfnd_001'')',
  'Test 4a: First partial refund executes successfully'
);

select is(
  (select status::text from public.payments where provider_payment_id = 'pay_ref_001'),
  'partially_refunded',
  'Test 4b: Payment status updated to partially_refunded'
);

select is(
  (select count(*)::integer from public.refunds where provider_refund_id = 'rfnd_001'),
  1,
  'Test 4c: Refund event rfnd_001 recorded in public.refunds'
);

-- TEST 5: Duplicate delivery of rfnd_001 is idempotent and ignored
select lives_ok(
  'select private.process_refund_success(''pay_ref_001'', 40000, ''rfnd_001'')',
  'Test 5a: Duplicate refund call executes without error'
);

select is(
  (select count(*)::integer from public.refunds where payment_id = (select id from public.payments where provider_payment_id = 'pay_ref_001')),
  1,
  'Test 5b: Duplicate refund delivery does not duplicate ledger entry'
);

-- TEST 6: Second refund completing total (65,000 paise) sets status to refunded and reverses pending payout
select lives_ok(
  'select private.process_refund_success(''pay_ref_001'', 65000, ''rfnd_002'')',
  'Test 6a: Second refund completing total executes successfully'
);

select is(
  (select status::text from public.payments where provider_payment_id = 'pay_ref_001'),
  'refunded',
  'Test 6b: Payment status updated to refunded'
);

select is(
  (select status::text from public.payouts where booking_id = (select id from public.bookings where customer_id = '12121212-1212-1212-1212-121212121212')),
  'reversed',
  'Test 6c: Pending payout status reversed'
);

-- TEST 7: Authenticated user cannot execute process_refund_success wrapper
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "14141414-1414-1414-1414-141414141414", "role": "authenticated"}', true);

select throws_like(
  'select public.process_refund_success(''pay_ref_001'', 1000)',
  '%permission denied%',
  'Test 7: Authenticated user blocked from process_refund_success wrapper'
);

select * from finish();
rollback;
