-- Expose only the payment RPC entry points needed by trusted Edge Functions.
-- Do not expose the private schema through PostgREST.

CREATE FUNCTION public.process_payment_success(
    p_booking_id uuid,
    p_provider_order_id text,
    p_provider_payment_id text,
    p_amount_paise integer,
    p_provider text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    IF auth.role() IS DISTINCT FROM 'service_role' THEN
        RAISE EXCEPTION 'Service role required';
    END IF;

    PERFORM private.process_payment_success(
        p_booking_id,
        p_provider_order_id,
        p_provider_payment_id,
        p_amount_paise,
        p_provider
    );
END;
$function$;

CREATE FUNCTION public.process_refund_success(
    p_provider_payment_id text,
    p_refund_amount_paise integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    IF auth.role() IS DISTINCT FROM 'service_role' THEN
        RAISE EXCEPTION 'Service role required';
    END IF;

    PERFORM private.process_refund_success(
        p_provider_payment_id,
        p_refund_amount_paise
    );
END;
$function$;

-- Remove default/public access and grant only to the trusted server role.
REVOKE ALL ON FUNCTION public.process_payment_success(uuid, text, text, integer, text)
    FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.process_refund_success(text, integer)
    FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.process_payment_success(uuid, text, text, integer, text)
    TO service_role;

GRANT EXECUTE ON FUNCTION public.process_refund_success(text, integer)
    TO service_role;

NOTIFY pgrst, 'reload schema';
