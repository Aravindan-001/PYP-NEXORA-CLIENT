BEGIN;

SELECT plan(4);

INSERT INTO auth.users (id, email) VALUES
  ('cccccccc-cccc-4ccc-8ccc-ccccccccccc1', 'payment-validation-customer@test.local'),
  ('cccccccc-cccc-4ccc-8ccc-ccccccccccc2', 'payment-validation-photographer@test.local');

INSERT INTO public.photographer_profiles (
  id, user_id, display_name, bio, city, category,
  starting_price_paise, is_published
) VALUES (
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc3',
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc2',
  'Payment Validation Test Photographer',
  'Local regression fixture',
  'Chennai',
  'Wedding',
  150000,
  true
);

INSERT INTO public.bookings (
  id, customer_id, photographer_id,
  event_date, event_city, event_type, status,
  photographer_fee_paise, commission_paise
) VALUES (
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc4',
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc3',
  current_date + 5,
  'Chennai',
  'Wedding',
  'accepted',
  150000,
  7500
);

SELECT throws_like(
  $test$
    SELECT private.process_payment_success(
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc4',
      '   ',
      'validation_payment_1',
      157500,
      'razorpay'
    )
  $test$,
  '%Provider order ID and payment ID are required%',
  'Rejects a whitespace-only provider order ID'
);

SELECT throws_like(
  $test$
    SELECT private.process_payment_success(
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc4',
      'validation_order_2',
      '   ',
      157500,
      'razorpay'
    )
  $test$,
  '%Provider order ID and payment ID are required%',
  'Rejects a whitespace-only provider payment ID'
);

SELECT throws_like(
  $test$
    SELECT private.process_payment_success(
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc4',
      'validation_order_3',
      'validation_payment_3',
      157499,
      'razorpay'
    )
  $test$,
  '%Payment amount mismatch%',
  'Rejects a callback amount that differs from the booking total'
);

SELECT throws_like(
  $test$
    SELECT private.process_payment_success(
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc4',
      'validation_order_4',
      'validation_payment_4',
      NULL,
      'razorpay'
    )
  $test$,
  '%Payment amount mismatch%',
  'Rejects a NULL callback amount explicitly'
);

SELECT * FROM finish();

ROLLBACK;