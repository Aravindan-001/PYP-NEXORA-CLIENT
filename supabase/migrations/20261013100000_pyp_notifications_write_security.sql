-- PYP Forward Migration: Notifications Write Security Hardening
-- File: supabase/migrations/20261013100000_pyp_notifications_write_security.sql

BEGIN;

-- 1. Remove permissive INSERT and UPDATE policies on public.notifications
DROP POLICY IF EXISTS "Authenticated users or triggers can insert notifications" ON public.notifications;
DROP POLICY IF EXISTS "Users can update own notifications" ON public.notifications;

-- 2. Revoke all privileges from PUBLIC and anon, and revoke write privileges from authenticated role
REVOKE ALL ON TABLE public.notifications FROM PUBLIC, anon;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.notifications FROM authenticated;

-- 3. Ensure SELECT privilege remains granted to authenticated users for listing and Realtime
GRANT SELECT ON TABLE public.notifications TO authenticated;

-- 4. Preserve / ensure SELECT RLS policy exists and is strictly scoped to owner
DROP POLICY IF EXISTS "Users can read own notifications" ON public.notifications;
CREATE POLICY "Users can read own notifications"
  ON public.notifications FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- 5. Ensure mark_notifications_read RPC remains SECURITY DEFINER with safe search_path and execution grant
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

REVOKE ALL ON FUNCTION public.mark_notifications_read(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_notifications_read(uuid) TO authenticated;

COMMIT;
