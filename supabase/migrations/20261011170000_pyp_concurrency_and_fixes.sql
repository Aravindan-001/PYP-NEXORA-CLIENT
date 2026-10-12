-- PYP: Concurrency Protection, Webhook Reliability, Abandoned Checkout & Refund Synchronization
-- Forward-only migration

-- 1. Partial unique index to prevent multiple active pending payments per booking
CREATE UNIQUE INDEX IF NOT EXISTS payments_pending_booking_idx
  ON public.payments (booking_id)
  WHERE status = 'pending';

-- 2. Add 'partially_refunded' to public.payment_status enum
ALTER TYPE public.payment_status ADD VALUE IF NOT EXISTS 'partially_refunded';

-- 3. Replace prepare_booking_for_payment to lock booking row and return existing pending order
DROP FUNCTION IF EXISTS public.prepare_booking_for_payment(uuid) CASCADE;

CREATE OR REPLACE FUNCTION public.prepare_booking_for_payment(
  p_booking_id uuid
) RETURNS TABLE (
  out_booking_id uuid,
  out_status public.booking_status,
  out_total_amount_paise integer,
  out_existing_provider_order_id text
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_booking record;
  v_existing_order text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthenticated user';
  END IF;

  -- Lock booking row for update to serialize concurrent order attempts
  SELECT * INTO v_booking
  FROM public.bookings
  WHERE id = p_booking_id
  FOR UPDATE;

  IF v_booking.id IS NULL THEN
    RAISE EXCEPTION 'Booking not found';
  END IF;

  IF v_booking.customer_id != v_user_id THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_booking.status NOT IN ('accepted', 'awaiting_payment') THEN
    RAISE EXCEPTION 'Booking status % cannot accept payment', v_booking.status;
  END IF;

  -- Transition status from accepted to awaiting_payment
  IF v_booking.status = 'accepted' THEN
    UPDATE public.bookings
    SET status = 'awaiting_payment', updated_at = now()
    WHERE id = p_booking_id;

    v_booking.status := 'awaiting_payment';
  END IF;

  -- Check for an existing pending razorpay order for this booking
  SELECT provider_order_id INTO v_existing_order
  FROM public.payments
  WHERE public.payments.booking_id = p_booking_id
    AND public.payments.status = 'pending'
    AND provider = 'razorpay'
  ORDER BY created_at DESC
  LIMIT 1;

  out_booking_id := v_booking.id;
  out_status := v_booking.status;
  out_total_amount_paise := v_booking.total_amount_paise;
  out_existing_provider_order_id := v_existing_order;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.prepare_booking_for_payment FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_booking_for_payment TO authenticated;

-- 4. Replace customer_cancel_booking to allow cancellation from awaiting_payment when no captured payment exists
CREATE OR REPLACE FUNCTION public.customer_cancel_booking(
  p_booking_id uuid
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_booking record;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthenticated user';
  END IF;

  -- Lock booking row for update
  SELECT * INTO v_booking
  FROM public.bookings
  WHERE id = p_booking_id
  FOR UPDATE;

  IF v_booking.id IS NULL THEN
    RAISE EXCEPTION 'Booking not found';
  END IF;

  IF v_booking.customer_id != v_user_id THEN
    RAISE EXCEPTION 'Unauthorized to cancel this booking';
  END IF;

  IF v_booking.status NOT IN ('requested', 'accepted', 'awaiting_payment') THEN
    RAISE EXCEPTION 'Booking with status % cannot be cancelled directly by customer', v_booking.status;
  END IF;

  -- Ensure no captured payment exists
  IF EXISTS (
    SELECT 1 FROM public.payments
    WHERE booking_id = p_booking_id AND status = 'captured'
  ) THEN
    RAISE EXCEPTION 'Booking cannot be cancelled because a captured payment exists';
  END IF;

  -- Mark any pending payments for this booking as failed
  UPDATE public.payments
  SET status = 'failed'
  WHERE booking_id = p_booking_id AND status = 'pending';

  UPDATE public.bookings
  SET status = 'cancelled', updated_at = now()
  WHERE id = p_booking_id;
END;
$$;

REVOKE ALL ON FUNCTION public.customer_cancel_booking FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.customer_cancel_booking TO authenticated;

-- 5. Private function for refund processing
CREATE OR REPLACE FUNCTION private.process_refund_success(
  p_provider_payment_id text,
  p_refund_amount_paise integer
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_payment record;
  v_clean_payment_id text := trim(coalesce(p_provider_payment_id, ''));
BEGIN
  IF v_clean_payment_id = '' THEN
    RAISE EXCEPTION 'Provider payment ID is required';
  END IF;

  SELECT * INTO v_payment
  FROM public.payments
  WHERE provider_payment_id = v_clean_payment_id
  FOR UPDATE;

  IF v_payment.id IS NULL THEN
    RAISE NOTICE 'Payment record not found for provider_payment_id %', v_clean_payment_id;
    RETURN;
  END IF;

  IF p_refund_amount_paise >= v_payment.amount_paise THEN
    -- Full refund
    UPDATE public.payments
    SET status = 'refunded'
    WHERE id = v_payment.id;

    -- Reverse pending payout if present
    UPDATE public.payouts
    SET status = 'reversed', updated_at = now()
    WHERE booking_id = v_payment.booking_id AND status = 'pending';
  ELSE
    -- Partial refund
    UPDATE public.payments
    SET status = 'partially_refunded'
    WHERE id = v_payment.id;
  END IF;

END;
$$;

REVOKE ALL ON FUNCTION private.process_refund_success FROM public, anon, authenticated;
