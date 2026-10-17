-- Forward migration: harden payment order conflict handling.
-- Does not modify payment data or apply itself to the remote database.

CREATE OR REPLACE FUNCTION private.process_payment_success(
  p_booking_id uuid,
  p_provider_order_id text,
  p_provider_payment_id text,
  p_amount_paise integer,
  p_provider text DEFAULT 'razorpay'
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_booking record;
  v_existing_payment record;
  v_clean_order_id text := trim(coalesce(p_provider_order_id, ''));
  v_clean_payment_id text := trim(coalesce(p_provider_payment_id, ''));
  v_clean_provider text := trim(coalesce(p_provider, 'razorpay'));
  v_photo_user_id uuid;
  v_photo_name text;
  v_payment_rows integer;
BEGIN
  IF v_clean_order_id = '' OR v_clean_payment_id = '' THEN
    RAISE EXCEPTION 'Provider order ID and payment ID are required';
  END IF;

  -- Lock booking row FOR UPDATE to serialize concurrent payment attempts
  SELECT b.*, pp.user_id AS photo_user_id, pp.display_name AS photo_display_name INTO v_booking
  FROM public.bookings b
  LEFT JOIN public.photographer_profiles pp ON pp.id = b.photographer_id
  WHERE b.id = p_booking_id
  FOR UPDATE OF b;

  IF v_booking.id IS NULL THEN
    RAISE EXCEPTION 'Booking not found: %', p_booking_id;
  END IF;

  IF v_booking.total_amount_paise IS NULL OR v_booking.total_amount_paise IS DISTINCT FROM p_amount_paise THEN
    RAISE EXCEPTION 'Payment amount mismatch: expected %, got %', v_booking.total_amount_paise, p_amount_paise;
  END IF;

  -- Resolve by order ID first; never treat a payment-ID-only match as the same order.
  SELECT * INTO v_existing_payment
  FROM public.payments
  WHERE provider_order_id = v_clean_order_id;

  -- A payment ID already assigned to another order must never be reused.
  IF EXISTS (
    SELECT 1
    FROM public.payments p
    WHERE p.provider_payment_id = v_clean_payment_id
      AND p.provider_order_id IS DISTINCT FROM v_clean_order_id
  ) THEN
    RAISE EXCEPTION 'Provider payment ID % is already associated with a different order',
      v_clean_payment_id;
  END IF;

  IF v_existing_payment.id IS NOT NULL THEN
    IF v_existing_payment.booking_id IS DISTINCT FROM p_booking_id THEN
      RAISE EXCEPTION 'Provider order ID % belongs to a different booking',
        v_clean_order_id;
    END IF;

    IF v_existing_payment.provider IS DISTINCT FROM v_clean_provider THEN
      RAISE EXCEPTION 'Provider mismatch for order %', v_clean_order_id;
    END IF;

    IF v_existing_payment.amount_paise IS DISTINCT FROM p_amount_paise THEN
      RAISE EXCEPTION 'Stored payment amount mismatch for order %', v_clean_order_id;
    END IF;

    IF v_existing_payment.provider_payment_id IS NOT NULL
       AND v_existing_payment.provider_payment_id <> v_clean_payment_id THEN
      RAISE EXCEPTION 'Conflicting payment ID % for order %',
        v_clean_payment_id, v_clean_order_id;
    END IF;

    IF v_existing_payment.status = 'captured'
       AND v_existing_payment.provider_payment_id = v_clean_payment_id
       AND v_booking.status = 'confirmed' THEN
      RETURN;
    END IF;
  END IF;

  -- Handle captured payment for cancelled or rejected bookings (Refund Reconciliation)
  IF v_booking.status IN ('cancelled', 'rejected') THEN
    INSERT INTO public.payments (
      booking_id,
      provider,
      provider_order_id,
      provider_payment_id,
      amount_paise,
      status,
      verified_at
    ) VALUES (
      p_booking_id,
      v_clean_provider,
      v_clean_order_id,
      v_clean_payment_id,
      p_amount_paise,
      'captured',
      now()
    )
    ON CONFLICT (provider_order_id) DO UPDATE
    SET provider_payment_id = EXCLUDED.provider_payment_id,
        status = 'captured',
        verified_at = now()
    WHERE public.payments.booking_id = EXCLUDED.booking_id
      AND public.payments.provider = EXCLUDED.provider
      AND public.payments.amount_paise = EXCLUDED.amount_paise
      AND (
        public.payments.provider_payment_id IS NULL
        OR public.payments.provider_payment_id = EXCLUDED.provider_payment_id
      )
      AND (
        public.payments.status <> 'captured'
        OR public.payments.provider_payment_id = EXCLUDED.provider_payment_id
      );
    GET DIAGNOSTICS v_payment_rows = ROW_COUNT;
    IF v_payment_rows = 0 THEN
      RAISE EXCEPTION 'Conflicting payment record for provider order ID %', v_clean_order_id;
    END IF;

    RAISE NOTICE 'Payment captured for % booking %. Recorded for refund reconciliation.',
      v_booking.status, p_booking_id;
    RETURN;
  END IF;

  IF v_booking.status NOT IN ('requested', 'accepted', 'awaiting_payment', 'confirmed') THEN
    RAISE EXCEPTION 'Booking status % cannot transition to confirmed', v_booking.status;
  END IF;

  -- Insert or update payment entry
  INSERT INTO public.payments (
    booking_id,
    provider,
    provider_order_id,
    provider_payment_id,
    amount_paise,
    status,
    verified_at
  ) VALUES (
    p_booking_id,
    v_clean_provider,
    v_clean_order_id,
    v_clean_payment_id,
    p_amount_paise,
    'captured',
    now()
  )
  ON CONFLICT (provider_order_id) DO UPDATE
  SET provider_payment_id = EXCLUDED.provider_payment_id,
      status = 'captured',
      verified_at = now()
  WHERE public.payments.booking_id = EXCLUDED.booking_id
    AND public.payments.provider = EXCLUDED.provider
    AND public.payments.amount_paise = EXCLUDED.amount_paise
    AND (
      public.payments.provider_payment_id IS NULL
      OR public.payments.provider_payment_id = EXCLUDED.provider_payment_id
    )
    AND (
      public.payments.status <> 'captured'
      OR public.payments.provider_payment_id = EXCLUDED.provider_payment_id
    );
  GET DIAGNOSTICS v_payment_rows = ROW_COUNT;
  IF v_payment_rows = 0 THEN
    RAISE EXCEPTION 'Conflicting payment record for provider order ID %', v_clean_order_id;
  END IF;

  -- Advance booking status to confirmed
  UPDATE public.bookings
  SET status = 'confirmed', updated_at = now()
  WHERE id = p_booking_id;

  -- Post to commission ledger (idempotent)
  INSERT INTO public.commission_ledger (
    booking_id,
    amount_paise
  ) VALUES (
    p_booking_id,
    v_booking.commission_paise
  )
  ON CONFLICT (booking_id) DO NOTHING;

  -- Post to payouts ledger for photographer (idempotent)
  INSERT INTO public.payouts (
    booking_id,
    photographer_id,
    amount_paise,
    status
  ) VALUES (
    p_booking_id,
    v_booking.photographer_id,
    v_booking.photographer_fee_paise,
    'pending'
  )
  ON CONFLICT (booking_id) DO NOTHING;

  -- Notifications
  v_photo_name := coalesce(v_booking.photo_display_name, 'Photographer');

  -- Notification for Customer
  INSERT INTO public.notifications (
    user_id,
    title,
    message,
    type,
    booking_id
  ) VALUES (
    v_booking.customer_id,
    'Payment Confirmed!',
    'Your payment for ' || v_booking.event_type || ' with ' || v_photo_name || ' has been verified. Chat is now unlocked!',
    'payment_confirmed',
    p_booking_id
  );

  -- Notification for Photographer
  IF v_booking.photo_user_id IS NOT NULL THEN
    INSERT INTO public.notifications (
      user_id,
      title,
      message,
      type,
      booking_id
    ) VALUES (
      v_booking.photo_user_id,
      'Booking Confirmed & Paid',
      'Payment confirmed for ' || v_booking.event_type || ' with ' || coalesce(v_booking.customer_name, 'Client') || '. Chat is now active.',
      'payment_confirmed',
      p_booking_id
    );
  END IF;
END;
$$;

-- Keep payment processing inaccessible to untrusted client roles.
REVOKE ALL ON FUNCTION private.process_payment_success(uuid, text, text, integer, text)
FROM PUBLIC, anon, authenticated;