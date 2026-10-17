BEGIN;

SELECT plan(12);

-- Isolated local-only test fixtures.
INSERT INTO auth.users (id, email) VALUES
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1', 'pyp-payment-customer@test.local'),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2', 'pyp-payment-photographer@test.local');

INSERT INTO public.photographer_profiles (
  id, user_id, display_name, bio, city, category,
  starting_price_paise, is_published
) VALUES (
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2',
  'Local Payment Test Photographer',
  'Isolated database test fixture',
  'Chennai',
  'Wedding',
  150000,
  true
);

-- ₹1,500 fee + ₹75 commission = ₹1,575.
INSERT INTO public.bookings (
  id, customer_id, photographer_id,
  event_date, event_city, event_type, status,
  photographer_fee_paise, commission_paise
) VALUES (
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3',
  current_date + 5,
  'Chennai',
  'Wedding',
  'accepted',
  150000,
  7500
);

-- Customer prepares the accepted booking for payment.
SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1","role":"authenticated"}',
  true
);

SELECT * FROM public.prepare_booking_for_payment(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'
);

RESET ROLE;

SELECT is(
  (SELECT status::text FROM public.bookings
   WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'),
  'awaiting_payment',
  '1. Accepted booking moves to awaiting_payment'
);

-- Simulate a verified payment callback using fake provider IDs.
SELECT private.process_payment_success(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4',
  'local_test_order_001',
  'local_test_payment_001',
  157500,
  'razorpay'
);

SELECT is(
  (SELECT status::text FROM public.bookings
   WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'),
  'confirmed',
  '2. Successful payment confirms the booking'
);

SELECT is(
  (SELECT status::text FROM public.payments
   WHERE booking_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'),
  'captured',
  '3. Payment is recorded as captured'
);

SELECT is(
  (SELECT amount_paise FROM public.payments
   WHERE booking_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'),
  157500,
  '4. Captured payment amount is exactly 157500 paise'
);

SELECT is(
  (SELECT amount_paise FROM public.commission_ledger
   WHERE booking_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'),
  7500,
  '5. Commission ledger records exactly 7500 paise'
);

SELECT is(
  (SELECT amount_paise FROM public.payouts
   WHERE booking_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'),
  150000,
  '6. Photographer payout records exactly 150000 paise'
);

SELECT is(
  (SELECT status::text FROM public.payouts
   WHERE booking_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'),
  'pending',
  '7. Photographer payout starts in pending status'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.notifications
    WHERE user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
      AND booking_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'
      AND type = 'payment_confirmed'
  ),
  '8. Customer receives payment confirmation notification'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.notifications
    WHERE user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2'
      AND booking_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'
      AND type = 'payment_confirmed'
  ),
  '9. Photographer receives payment confirmation notification'
);

-- Retry the identical callback to test idempotency.
SELECT private.process_payment_success(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4',
  'local_test_order_001',
  'local_test_payment_001',
  157500,
  'razorpay'
);

SELECT is(
  (SELECT count(*)::integer FROM public.commission_ledger
   WHERE booking_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'),
  1,
  '10. Retrying payment does not duplicate commission ledger entries'
);

SELECT is(
  (SELECT count(*)::integer FROM public.payouts
   WHERE booking_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'),
  1,
  '11. Retrying payment does not duplicate photographer payouts'
);

SELECT is(
  (SELECT count(*)::integer FROM public.payments
   WHERE booking_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'),
  1,
  '12. Retrying payment does not duplicate payment records'
);

SELECT * FROM finish();

ROLLBACK;