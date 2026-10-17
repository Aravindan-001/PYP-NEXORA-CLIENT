-- PYP Forward Migration: Canonical Payment Processor & Security Unification
-- File: supabase/migrations/20261012160000_pyp_canonical_payment_processor.sql

-- 1. Drop old function overloaded signatures to ensure single canonical implementation
DROP FUNCTION IF EXISTS private.process_payment_success(uuid, text, text, integer);
DROP FUNCTION IF EXISTS private.process_payment_success(uuid, text, text, text, integer);

-- 2. Create canonical private.process_payment_success with default provider = 'razorpay'
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

  IF v_booking.total_amount_paise IS NULL OR v_booking.total_amount_paise != p_amount_paise THEN
    RAISE EXCEPTION 'Payment amount mismatch: expected %, got %', v_booking.total_amount_paise, p_amount_paise;
  END IF;

  -- Check existing payment records for order ID or payment ID
  SELECT * INTO v_existing_payment
  FROM public.payments
  WHERE provider_order_id = v_clean_order_id
     OR provider_payment_id = v_clean_payment_id;

  IF v_existing_payment.id IS NOT NULL THEN
    -- Verify the order/payment belongs to this exact booking
    IF v_existing_payment.booking_id != p_booking_id THEN
      RAISE EXCEPTION 'Provider order ID % belongs to a different booking', v_clean_order_id;
    END IF;

    IF v_existing_payment.status = 'captured' THEN
      -- Idempotent retry: verify payment ID matches
      IF v_existing_payment.provider_payment_id = v_clean_payment_id THEN
        -- If booking is already confirmed, idempotent return
        IF v_booking.status = 'confirmed' THEN
          RETURN;
        END IF;
      ELSE
        RAISE EXCEPTION 'Conflicting payment ID % for order %', v_clean_payment_id, v_clean_order_id;
      END IF;
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
    ON CONFLICT (provider_order_id) DO UPDATE SET
      provider_payment_id = excluded.provider_payment_id,
      status = 'captured',
      verified_at = now();

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
  ON CONFLICT (provider_order_id) DO UPDATE SET
    provider_payment_id = excluded.provider_payment_id,
    status = 'captured',
    verified_at = now();

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

-- Restrict private execution strictly to server-side code (postgres / service_role)
REVOKE ALL ON FUNCTION private.process_payment_success FROM public, anon, authenticated;
