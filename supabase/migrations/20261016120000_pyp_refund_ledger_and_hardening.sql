-- PYP Migration: Auditable Refund Ledger & Hardened Refund Processing
-- File: supabase/migrations/20261016120000_pyp_refund_ledger_and_hardening.sql

-- 1. Create public.refunds table to store auditable refund events
CREATE TABLE IF NOT EXISTS public.refunds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_id uuid NOT NULL REFERENCES public.payments(id) ON DELETE CASCADE,
  booking_id uuid NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
  provider_refund_id text UNIQUE,
  amount_paise integer NOT NULL CHECK (amount_paise > 0),
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_refunds_payment_id ON public.refunds(payment_id);
CREATE INDEX IF NOT EXISTS idx_refunds_booking_id ON public.refunds(booking_id);

-- Enable RLS and restrict access to server roles
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.refunds FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.refunds TO authenticated;

-- RLS policy: Booking participants & admins can view refund records
DROP POLICY IF EXISTS "Booking participants can view refund records" ON public.refunds;
CREATE POLICY "Booking participants can view refund records"
  ON public.refunds FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.bookings b
      LEFT JOIN public.photographer_profiles pp ON pp.id = b.photographer_id
      WHERE b.id = refunds.booking_id
        AND (
          b.customer_id = (SELECT auth.uid())
          OR pp.user_id = (SELECT auth.uid())
          OR private.is_admin_user((SELECT auth.uid()))
        )
    )
  );

-- Drop old function signatures to prevent function overloading ambiguity
DROP FUNCTION IF EXISTS public.process_refund_success(text, integer);
DROP FUNCTION IF EXISTS private.process_refund_success(text, integer);

-- 2. Update private.process_refund_success implementation
CREATE OR REPLACE FUNCTION private.process_refund_success(
  p_provider_payment_id text,
  p_refund_amount_paise integer,
  p_provider_refund_id text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_payment record;
  v_clean_payment_id text := trim(coalesce(p_provider_payment_id, ''));
  v_clean_refund_id text := nullif(trim(coalesce(p_provider_refund_id, '')), '');
  v_existing_refunded integer := 0;
  v_incremental_amount integer;
  v_new_total_refunded integer;
BEGIN
  IF v_clean_payment_id = '' THEN
    RAISE EXCEPTION 'Provider payment ID is required';
  END IF;

  IF p_refund_amount_paise IS NULL OR p_refund_amount_paise <= 0 THEN
    RAISE EXCEPTION 'Invalid refund amount: %', p_refund_amount_paise;
  END IF;

  -- Lock payment row FOR UPDATE to prevent concurrent refund race conditions
  SELECT * INTO v_payment
  FROM public.payments
  WHERE provider_payment_id = v_clean_payment_id
  FOR UPDATE;

  IF v_payment.id IS NULL THEN
    RAISE NOTICE 'Payment record not found for provider_payment_id %', v_clean_payment_id;
    RETURN;
  END IF;

  -- Check if provider_refund_id was already recorded (idempotent duplicate check)
  IF v_clean_refund_id IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM public.refunds
      WHERE provider_refund_id = v_clean_refund_id
    ) THEN
      RAISE NOTICE 'Refund event % already processed', v_clean_refund_id;
      RETURN;
    END IF;
  END IF;

  -- Calculate current cumulative amount refunded for this payment
  SELECT COALESCE(SUM(amount_paise), 0)
  INTO v_existing_refunded
  FROM public.refunds
  WHERE payment_id = v_payment.id;

  -- Handle both incremental refund amounts and cumulative payload values
  IF p_refund_amount_paise = v_payment.amount_paise AND v_existing_refunded > 0 THEN
    v_incremental_amount := v_payment.amount_paise - v_existing_refunded;
  ELSE
    v_incremental_amount := p_refund_amount_paise;
  END IF;

  -- Check if total refunded exceeds captured payment
  v_new_total_refunded := v_existing_refunded + v_incremental_amount;

  IF v_new_total_refunded > v_payment.amount_paise THEN
    RAISE EXCEPTION 'Cumulative refund amount % exceeds captured payment amount %',
      v_new_total_refunded, v_payment.amount_paise;
  END IF;

  -- Record auditable refund ledger entry
  INSERT INTO public.refunds (
    payment_id,
    booking_id,
    provider_refund_id,
    amount_paise
  ) VALUES (
    v_payment.id,
    v_payment.booking_id,
    v_clean_refund_id,
    v_incremental_amount
  );

  -- Update payment status based on new cumulative total
  IF v_new_total_refunded >= v_payment.amount_paise THEN
    UPDATE public.payments
    SET status = 'refunded'
    WHERE id = v_payment.id;

    -- Reverse pending photographer payout if present
    UPDATE public.payouts
    SET status = 'reversed', updated_at = now()
    WHERE booking_id = v_payment.booking_id AND status = 'pending';
  ELSE
    UPDATE public.payments
    SET status = 'partially_refunded'
    WHERE id = v_payment.id;
  END IF;

END;
$$;

-- Revoke all direct client execution privileges on private function
REVOKE ALL ON FUNCTION private.process_refund_success(text, integer, text) FROM PUBLIC, anon, authenticated;

-- 3. Update public wrapper public.process_refund_success to support optional provider_refund_id
CREATE OR REPLACE FUNCTION public.process_refund_success(
  p_provider_payment_id text,
  p_refund_amount_paise integer,
  p_provider_refund_id text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'Service role required';
  END IF;

  PERFORM private.process_refund_success(
    p_provider_payment_id,
    p_refund_amount_paise,
    p_provider_refund_id
  );
END;
$$;

-- Secure public wrapper execution permissions
REVOKE ALL ON FUNCTION public.process_refund_success(text, integer, text)
  FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.process_refund_success(text, integer, text)
  TO service_role;

NOTIFY pgrst, 'reload schema';
