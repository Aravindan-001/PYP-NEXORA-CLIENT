BEGIN;

SELECT plan(5);

-- Isolated local-only fixtures.
INSERT INTO auth.users (id, email) VALUES
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1', 'conflict-customer@test.local'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2', 'conflict-photographer@test.local');

INSERT INTO public.photographer_profiles (
  id, user_id, display_name, bio, city, category,
  starting_price_paise, is_published
) VALUES (
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',
  'Payment Conflict Test Photographer',
  'Isolated local regression fixture',
  'Chennai',
  'Wedding',
  150000,
  true
);

INSERT INTO public.bookings (
  id, customer_id, photographer_id,
  event_date, event_city, event_type, status,
  photographer_fee_paise, commission_paise
) VALUES
  (
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb4',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3',
    current_date + 5, 'Chennai', 'Wedding', 'accepted',
    150000, 7500
  ),
  (
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb5',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3',
    current_date + 6, 'Chennai', 'Wedding', 'accepted',
    150000, 7500
  );

-- Existing failed payment records provide safe conflict fixtures.
-- A failed status also avoids the one-pending-payment-per-booking index.
INSERT INTO public.payments (
  booking_id, provider, provider_order_id,
  provider_payment_id, amount_paise, status
) VALUES
  (
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb4',
    'razorpay', 'conflict_provider_order',
    NULL, 157500, 'failed'
  ),
  (
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb4',
    'razorpay', 'conflict_amount_order',
    NULL, 157499, 'failed'
  ),
  (
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb4',
    'razorpay', 'conflict_payment_id_order',
    'pay_original_conflict', 157500, 'failed'
  ),
  (
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb4',
    'razorpay', 'conflict_reuse_source_order',
    'pay_reused_conflict', 157500, 'failed'
  ),
  (
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb4',
    'razorpay', 'conflict_booking_order',
    'pay_booking_conflict', 157500, 'failed'
  );

-- TEST 1: Existing order cannot change its payment provider.
SELECT throws_like(
  $test$
    SELECT private.process_payment_success(
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb4',
      'conflict_provider_order',
      'pay_provider_attempt',
      157500,
      'stripe'
    )
  $test$,
  '%Provider mismatch for order%',
  '1. Rejects provider mismatch for an existing order'
);

-- TEST 2: The stored order amount must match the verified amount.
-- Booking total is 157500; the intentionally mismatched stored amount is 157499.
SELECT throws_like(
  $test$
    SELECT private.process_payment_success(
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb4',
      'conflict_amount_order',
      'pay_amount_attempt',
      157500,
      'razorpay'
    )
  $test$,
  '%Stored payment amount mismatch for order%',
  '2. Rejects an existing order with a different stored amount'
);

-- TEST 3: An existing order cannot be assigned a different payment ID.
SELECT throws_like(
  $test$
    SELECT private.process_payment_success(
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb4',
      'conflict_payment_id_order',
      'pay_different_conflict',
      157500,
      'razorpay'
    )
  $test$,
  '%Conflicting payment ID%',
  '3. Rejects a conflicting payment ID for the same order'
);

-- TEST 4: A payment ID already attached to another order cannot be reused.
SELECT throws_like(
  $test$
    SELECT private.process_payment_success(
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb5',
      'brand_new_conflict_order',
      'pay_reused_conflict',
      157500,
      'razorpay'
    )
  $test$,
  '%already associated with a different order%',
  '4. Rejects reuse of a payment ID across different orders'
);

-- TEST 5: An existing order cannot be attached to another booking.
SELECT throws_like(
  $test$
    SELECT private.process_payment_success(
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb5',
      'conflict_booking_order',
      'pay_booking_attempt',
      157500,
      'razorpay'
    )
  $test$,
  '%belongs to a different booking%',
  '5. Rejects an order associated with a different booking'
);

SELECT * FROM finish();

ROLLBACK;