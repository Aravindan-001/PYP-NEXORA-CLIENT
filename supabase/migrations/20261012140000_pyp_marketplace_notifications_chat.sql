-- Migration: 20261012140000_pyp_marketplace_notifications_chat.sql
-- Description: Marketplace workflow enhancements, notifications system, and server-authoritative chat access.

-- 1. ENUM UPDATES FOR BOOKING STATUS ALIASES
ALTER TYPE public.booking_status ADD VALUE IF NOT EXISTS 'pending';
ALTER TYPE public.booking_status ADD VALUE IF NOT EXISTS 'declined';
ALTER TYPE public.booking_status ADD VALUE IF NOT EXISTS 'payment_pending';

-- 2. EXTEND BOOKINGS TABLE WITH CUSTOMER DETAILS
ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS customer_name text,
  ADD COLUMN IF NOT EXISTS customer_phone text;

-- 3. EXTEND PHOTOGRAPHER PROFILES WITH DETAILED FIELDS
ALTER TABLE public.photographer_profiles
  ADD COLUMN IF NOT EXISTS experience_years integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS specializations text[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS service_locations text[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS availability_note text;

-- 4. CREATE NOTIFICATIONS TABLE
CREATE TABLE IF NOT EXISTS public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title text NOT NULL,
  message text NOT NULL,
  type text NOT NULL DEFAULT 'general',
  booking_id uuid REFERENCES public.bookings(id) ON DELETE CASCADE,
  is_read boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Index for fast user queries
CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON public.notifications(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_is_read ON public.notifications(user_id, is_read);

-- Enable RLS on notifications
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read own notifications" ON public.notifications;
CREATE POLICY "Users can read own notifications"
  ON public.notifications FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can update own notifications" ON public.notifications;
CREATE POLICY "Users can update own notifications"
  ON public.notifications FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Authenticated users or triggers can insert notifications" ON public.notifications;
CREATE POLICY "Authenticated users or triggers can insert notifications"
  ON public.notifications FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- Enable Realtime on notifications
ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;

-- 5. CREATE CHAT MESSAGES TABLE
CREATE TABLE IF NOT EXISTS public.chat_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
  sender_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  sender_name text,
  message text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Index for chat history lookup
CREATE INDEX IF NOT EXISTS idx_chat_messages_booking ON public.chat_messages(booking_id, created_at ASC);

-- Enable RLS on chat_messages
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;

-- Server-Authoritative RLS Policy for SELECTing chat messages:
-- ONLY participants of a confirmed or completed booking can read messages
DROP POLICY IF EXISTS "Chat participants can view messages of confirmed bookings" ON public.chat_messages;
CREATE POLICY "Chat participants can view messages of confirmed bookings"
  ON public.chat_messages FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.bookings b
      JOIN public.photographer_profiles pp ON pp.id = b.photographer_id
      WHERE b.id = chat_messages.booking_id
        AND (b.customer_id = auth.uid() OR pp.user_id = auth.uid())
        AND b.status IN ('confirmed', 'completed')
    )
  );

-- Server-Authoritative RLS Policy for INSERTing chat messages:
-- ONLY participants of a confirmed booking can send messages
DROP POLICY IF EXISTS "Chat participants can send messages to confirmed bookings" ON public.chat_messages;
CREATE POLICY "Chat participants can send messages to confirmed bookings"
  ON public.chat_messages FOR INSERT
  TO authenticated
  WITH CHECK (
    sender_id = auth.uid() AND
    EXISTS (
      SELECT 1 FROM public.bookings b
      JOIN public.photographer_profiles pp ON pp.id = b.photographer_id
      WHERE b.id = chat_messages.booking_id
        AND (b.customer_id = auth.uid() OR pp.user_id = auth.uid())
        AND b.status IN ('confirmed', 'completed')
    )
  );

-- Enable Realtime on chat_messages
ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_messages;

-- 6. UPDATE BOOKING CREATION RPC TO SUPPORT CUSTOMER NAME & PHONE AND GENERATE NOTIFICATION
DROP FUNCTION IF EXISTS public.create_booking_request(uuid, date, text, text, text);
DROP FUNCTION IF EXISTS public.create_booking_request(uuid, date, text, text, text, text, text);

CREATE OR REPLACE FUNCTION public.create_booking_request(
  p_photographer_id uuid,
  p_event_date date,
  p_event_city text,
  p_event_type text,
  p_customer_note text DEFAULT NULL,
  p_customer_name text DEFAULT NULL,
  p_customer_phone text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_customer_id uuid := auth.uid();
  v_fee_paise integer;
  v_commission_paise integer;
  v_booking_id uuid;
  v_photographer_user_id uuid;
  v_photographer_name text;
  v_cust_name text;
  v_clean_event_city text := trim(coalesce(p_event_city, ''));
  v_clean_event_type text := trim(coalesce(p_event_type, ''));
  v_clean_note text := nullif(trim(coalesce(p_customer_note, '')), '');
BEGIN
  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Unauthenticated user';
  END IF;

  IF length(v_clean_event_city) < 2 OR length(v_clean_event_city) > 100 THEN
    RAISE EXCEPTION 'Event city must be specified';
  END IF;

  IF length(v_clean_event_type) < 2 OR length(v_clean_event_type) > 50 THEN
    RAISE EXCEPTION 'Event type must be specified';
  END IF;

  IF p_event_date < (now() AT TIME ZONE 'UTC')::date THEN
    RAISE EXCEPTION 'Event date cannot be in the past';
  END IF;

  -- Prevent duplicate pending or confirmed requests for same photographer and date
  IF EXISTS (
    SELECT 1 FROM public.bookings
    WHERE customer_id = v_customer_id
      AND photographer_id = p_photographer_id
      AND event_date = p_event_date
      AND status IN ('requested', 'pending', 'accepted', 'awaiting_payment', 'payment_pending', 'confirmed')
  ) THEN
    RAISE EXCEPTION 'You already have an active booking request with this photographer for the selected date.';
  END IF;

  SELECT starting_price_paise, user_id, display_name
  INTO v_fee_paise, v_photographer_user_id, v_photographer_name
  FROM public.photographer_profiles
  WHERE id = p_photographer_id AND is_published = true;

  IF v_fee_paise IS NULL THEN
    RAISE EXCEPTION 'Photographer profile not found or inactive';
  END IF;

  IF v_photographer_user_id = v_customer_id THEN
    RAISE EXCEPTION 'Photographers cannot book themselves';
  END IF;

  -- Get customer full name if not supplied
  IF p_customer_name IS NOT NULL AND length(trim(p_customer_name)) > 0 THEN
    v_cust_name := trim(p_customer_name);
  ELSE
    SELECT full_name INTO v_cust_name FROM public.profiles WHERE id = v_customer_id;
    IF v_cust_name IS NULL OR length(trim(v_cust_name)) = 0 THEN
      v_cust_name := 'Client';
    END IF;
  END IF;

  -- Standard 5% platform commission calculation with precision rounding
  v_commission_paise := round((v_fee_paise * 5.0) / 100.0)::integer;

  INSERT INTO public.bookings (
    customer_id,
    photographer_id,
    event_date,
    event_city,
    event_type,
    customer_note,
    customer_name,
    customer_phone,
    status,
    photographer_fee_paise,
    commission_paise
  )
  VALUES (
    v_customer_id,
    p_photographer_id,
    p_event_date,
    v_clean_event_city,
    v_clean_event_type,
    v_clean_note,
    v_cust_name,
    nullif(trim(coalesce(p_customer_phone, '')), ''),
    'requested',
    v_fee_paise,
    v_commission_paise
  )
  RETURNING id INTO v_booking_id;

  -- Create Notification for Photographer
  INSERT INTO public.notifications (
    user_id,
    title,
    message,
    type,
    booking_id
  ) VALUES (
    v_photographer_user_id,
    'New Booking Request',
    v_cust_name || ' sent a request for ' || v_clean_event_type || ' in ' || v_clean_event_city || ' on ' || p_event_date::text || '.',
    'booking_request',
    v_booking_id
  );

  RETURN v_booking_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_booking_request FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_booking_request TO authenticated;

-- 7. UPDATE PHOTOGRAPHER RESPOND BOOKING RPC TO GENERATE NOTIFICATION
CREATE OR REPLACE FUNCTION public.photographer_respond_booking(
  p_booking_id uuid,
  p_accept boolean
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_booking record;
  v_photo_name text;
  v_new_status text;
  v_notif_title text;
  v_notif_msg text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthenticated user';
  END IF;

  SELECT b.*, pp.user_id as photo_user_id, pp.display_name as photo_display_name INTO v_booking
  FROM public.bookings b
  JOIN public.photographer_profiles pp ON pp.id = b.photographer_id
  WHERE b.id = p_booking_id
  FOR UPDATE;

  IF v_booking.id IS NULL THEN
    RAISE EXCEPTION 'Booking not found';
  END IF;

  IF v_booking.photo_user_id != v_user_id THEN
    RAISE EXCEPTION 'Unauthorized to manage this booking';
  END IF;

  IF v_booking.status NOT IN ('requested', 'pending') THEN
    RAISE EXCEPTION 'Booking status % cannot be responded to', v_booking.status;
  END IF;

  v_photo_name := coalesce(v_booking.photo_display_name, 'Your photographer');

  IF p_accept THEN
    v_new_status := 'accepted';
    v_notif_title := 'Booking Accepted!';
    v_notif_msg := v_photo_name || ' accepted your booking request for ' || v_booking.event_type || '. You can now proceed to payment.';
  ELSE
    v_new_status := 'rejected';
    v_notif_title := 'Booking Request Declined';
    v_notif_msg := v_photo_name || ' was unable to accept your booking request for ' || v_booking.event_type || '.';
  END IF;

  UPDATE public.bookings
  SET status = v_new_status::public.booking_status, updated_at = now()
  WHERE id = p_booking_id;

  -- Create Notification for Customer
  INSERT INTO public.notifications (
    user_id,
    title,
    message,
    type,
    booking_id
  ) VALUES (
    v_booking.customer_id,
    v_notif_title,
    v_notif_msg,
    CASE WHEN p_accept THEN 'booking_accepted' ELSE 'booking_declined' END,
    p_booking_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.photographer_respond_booking FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.photographer_respond_booking TO authenticated;

-- 8. UPDATE PROCESS PAYMENT SUCCESS TO GENERATE NOTIFICATIONS & ADVANCE STATUS TO CONFIRMED
CREATE OR REPLACE FUNCTION private.process_payment_success(
  p_booking_id uuid,
  p_provider text,
  p_provider_order_id text,
  p_provider_payment_id text,
  p_amount_paise integer
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_booking record;
  v_photo_user_id uuid;
  v_photo_name text;
BEGIN
  SELECT b.*, pp.user_id as photo_user_id, pp.display_name as photo_display_name INTO v_booking
  FROM public.bookings b
  JOIN public.photographer_profiles pp ON pp.id = b.photographer_id
  WHERE b.id = p_booking_id
  FOR UPDATE;

  IF v_booking.id IS NULL THEN
    RAISE EXCEPTION 'Booking not found: %', p_booking_id;
  END IF;

  IF v_booking.total_amount_paise IS NULL OR v_booking.total_amount_paise != p_amount_paise THEN
    RAISE EXCEPTION 'Payment amount mismatch. Expected: %, Received: %', v_booking.total_amount_paise, p_amount_paise;
  END IF;

  IF v_booking.status = 'confirmed' THEN
    RETURN; -- Idempotent return
  END IF;

  -- Record payment entry
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
    p_provider,
    p_provider_order_id,
    p_provider_payment_id,
    p_amount_paise,
    'captured',
    now()
  );

  -- Update booking status to confirmed
  UPDATE public.bookings
  SET status = 'confirmed', updated_at = now()
  WHERE id = p_booking_id;

  -- Record ledger entry
  INSERT INTO public.commission_ledger (
    booking_id,
    amount_paise
  ) VALUES (
    p_booking_id,
    v_booking.commission_paise
  );

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
END;
$$;

-- 9. RPC TO SEND CHAT MESSAGE AND NOTIFY RECIPIENT
CREATE OR REPLACE FUNCTION public.send_chat_message(
  p_booking_id uuid,
  p_message text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_sender_id uuid := auth.uid();
  v_booking record;
  v_photo_user_id uuid;
  v_recipient_id uuid;
  v_sender_name text;
  v_msg_id uuid;
  v_clean_msg text := trim(coalesce(p_message, ''));
BEGIN
  IF v_sender_id IS NULL THEN
    RAISE EXCEPTION 'Unauthenticated user';
  END IF;

  IF length(v_clean_msg) = 0 THEN
    RAISE EXCEPTION 'Message cannot be empty';
  END IF;

  SELECT b.*, pp.user_id as photo_user_id INTO v_booking
  FROM public.bookings b
  JOIN public.photographer_profiles pp ON pp.id = b.photographer_id
  WHERE b.id = p_booking_id;

  IF v_booking.id IS NULL THEN
    RAISE EXCEPTION 'Booking not found';
  END IF;

  IF v_booking.status NOT IN ('confirmed', 'completed') THEN
    RAISE EXCEPTION 'Chat is available only for confirmed or completed bookings.';
  END IF;

  IF v_sender_id = v_booking.customer_id THEN
    v_recipient_id := v_booking.photo_user_id;
    SELECT full_name INTO v_sender_name FROM public.profiles WHERE id = v_sender_id;
    v_sender_name := coalesce(v_booking.customer_name, v_sender_name, 'Client');
  ELSIF v_sender_id = v_booking.photo_user_id THEN
    v_recipient_id := v_booking.customer_id;
    SELECT display_name INTO v_sender_name FROM public.photographer_profiles WHERE user_id = v_sender_id;
  ELSE
    RAISE EXCEPTION 'Unauthorized to participate in this chat';
  END IF;

  INSERT INTO public.chat_messages (
    booking_id,
    sender_id,
    sender_name,
    message
  ) VALUES (
    p_booking_id,
    v_sender_id,
    v_sender_name,
    v_clean_msg
  ) RETURNING id INTO v_msg_id;

  -- Create Notification for recipient
  INSERT INTO public.notifications (
    user_id,
    title,
    message,
    type,
    booking_id
  ) VALUES (
    v_recipient_id,
    'New message from ' || v_sender_name,
    CASE WHEN length(v_clean_msg) > 60 THEN substring(v_clean_msg from 1 for 57) || '...' ELSE v_clean_msg END,
    'chat',
    p_booking_id
  );

  RETURN v_msg_id;
END;
$$;

REVOKE ALL ON FUNCTION public.send_chat_message FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.send_chat_message TO authenticated;

-- 10. RPC TO MARK NOTIFICATIONS AS READ
CREATE OR REPLACE FUNCTION public.mark_notifications_read(
  p_notification_id uuid DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthenticated user';
  END IF;

  IF p_notification_id IS NOT NULL THEN
    UPDATE public.notifications
    SET is_read = true
    WHERE id = p_notification_id AND user_id = v_user_id;
  ELSE
    UPDATE public.notifications
    SET is_read = true
    WHERE user_id = v_user_id AND is_read = false;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_notifications_read FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_notifications_read TO authenticated;
