# PYP — Payment Flow & Security Architecture

**Project:** PYP — Pick Your Photographer
**Scope:** End-to-End Payment Lifecycle, RPC Security Wrappers, Idempotency, Refund Reconciliation, and Provider Setup

---

## 1. End-to-End Payment Lifecycle

The PYP payment lifecycle follows a **Zero-Trust, Server-Authoritative** pattern across four primary stages:

```
[Customer Request] ──> [Photographer Accepts] ──> [Order Creation] ──> [Payment Verification / Webhook]
       │                        │                        │                        │
  RPC: create_              RPC: photographer_    Edge Function:           Edge Function:
  booking_request           respond_booking       create-razorpay-order    verify-razorpay-payment
  (Calculates fee           (Transitions to       (Calls prepare_booking   (Verifies HMAC & amount,
   & commission)             'accepted')           _for_payment)            invokes process_payment
                                                                            _success wrapper)
```

### Stage 1: Booking Request & Fee Calculation
1. The customer selects an approved photographer and submits event details (city, date, event type, customer name, phone).
2. The Flutter client calls `public.create_booking_request(...)`.
3. The database server fetches the photographer's `starting_price_paise` (`photographer_fee_paise`), calculates the 5% platform commission (`commission_paise = round((fee * 5.0) / 100.0)`), and calculates the stored total (`total_amount_paise = fee + commission`).
4. All calculations occur in **integer paise** on the database server to prevent floating-point rounding errors and client-side price tampering.

### Stage 2: Photographer Acceptance
1. The photographer reviews the incoming request on their dashboard.
2. Calling `public.photographer_respond_booking(p_booking_id, true)` transitions the booking status from `'requested'` to `'accepted'`.
3. A realtime notification is issued to the customer.

### Stage 3: Order Creation (`create-razorpay-order` Edge Function)
1. When the customer initiates checkout, the Flutter client calls the `create-razorpay-order` Edge Function.
2. The Edge Function verifies the caller's JWT auth token and calls `public.prepare_booking_for_payment` RPC.
3. `prepare_booking_for_payment` locks the booking row (`FOR UPDATE`), checks that status is `'accepted'`, advances status to `'awaiting_payment'`, and checks for an existing valid pending order.
4. If a valid pending order exists, its order ID is reused. Otherwise, the Edge Function calls Razorpay REST API (`POST /v1/orders`) using `total_amount_paise` and creates a pending record in `public.payments`.
5. The partial unique index `payments_pending_booking_idx` prevents concurrent requests from creating duplicate pending payment orders.

### Stage 4: Payment Verification & Settlement (`verify-razorpay-payment` / `razorpay-webhook`)
1. Upon checkout completion, payment details are verified either via the `verify-razorpay-payment` Edge Function or asynchronously via `razorpay-webhook`.
2. Both functions verify the HMAC SHA-256 signature using `RAZORPAY_KEY_SECRET` or `RAZORPAY_WEBHOOK_SECRET`.
3. Payment details (amount, currency `INR`, status `captured`, order ID match) are validated with the Razorpay API.
4. Upon successful validation, the Edge Function calls the public RPC wrapper:
   ```typescript
   await adminSupabase.rpc("process_payment_success", {
     p_booking_id: bookingId,
     p_provider_order_id: razorpay_order_id,
     p_provider_payment_id: razorpay_payment_id,
     p_amount_paise: amount,
     p_provider: "razorpay"
   }, { schema: "public" });
   ```

---

## 2. Public RPC Wrappers & Security Controls

To allow PostgREST / Supabase JS client inside service-role Edge Functions to invoke payment handlers without exposing the `private` schema through PostgREST, controlled public wrappers exist in `public` schema (`20261016110000_pyp_payment_rpc_wrappers.sql`):

### Function Definition: `public.process_payment_success`
```sql
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
    -- Strict server-role execution check
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
```

### Security Guarantees:
1. **Empty Search Path:** `SET search_path = ''` prevents search path hijacking.
2. **Explicit Role Check:** `IF auth.role() IS DISTINCT FROM 'service_role'` guarantees that even if a logged-in user attempts to call `supabase.rpc('process_payment_success', ...)`, the call is immediately rejected with `'Service role required'`.
3. **Privilege Revocation:** Execution permissions are revoked from `PUBLIC`, `anon`, and `authenticated`, and granted strictly to `service_role`:
   ```sql
   REVOKE ALL ON FUNCTION public.process_payment_success(uuid, text, text, integer, text)
       FROM PUBLIC, anon, authenticated, service_role;
   GRANT EXECUTE ON FUNCTION public.process_payment_success(uuid, text, text, integer, text)
       TO service_role;
   ```

---

## 3. Idempotency & Conflict Hardening

### 1. Webhook Deduplication
- Every incoming Razorpay webhook event is assigned a deterministic event ID (`event_id` or `payment_id_event_type`).
- The `processed_webhook_events` table enforces a primary key on `event_id`. Duplicate webhook deliveries return `200 OK` with status `'already_processed'` without duplicate database writes.

### 2. Payment Table Unique Constraints
- `payments_pending_booking_idx`: Partial unique index on `payments(booking_id)` where `status = 'pending'`, preventing multiple pending orders for the same booking.
- `payments_provider_order_id_key`: Unique constraint on `provider_order_id`. If `process_payment_success` is called multiple times for the same order, it updates the existing record idempotently.

### 3. Row Locking (`FOR UPDATE`)
- `private.process_payment_success` locks the booking row (`FOR UPDATE OF b`) before reading or modifying statuses, serializing concurrent payment callbacks.

---

## 4. Refund Reconciliation & Ledger Processing

### Refund Handling (`private.process_refund_success`)
- Handles `refund.processed` / `payment.refunded` events.
- Updates payment status to `refunded` or `partially_refunded`.
- Updates photographer payout ledger in `public.payouts` to status `reversed` if full refund is issued.

### Late Payment Reconciliation
- If a customer's payment is captured after a booking was already cancelled or rejected, `process_payment_success` records the payment with status `captured` and logs a notice for refund reconciliation, preventing booking status corruption while maintaining audit logs.

---

## 5. Provider Setup Requirements (Razorpay Route)

### Current Implementation State vs. Provider Configuration
- **Database Ledgers:**
  - `public.commission_ledger`: Records PYP 5% platform revenue.
  - `public.payouts`: Records photographer payout amount (`photographer_fee_paise`) with status `pending`.
- **Razorpay Route Integration Setup:**
  - To enable automated transfers to photographer bank accounts upon payment capture:
    1. Onboard photographers as Razorpay Linked Accounts in the Razorpay Merchant Dashboard (`acc_XXXXXXXXXX`).
    2. Store `razorpay_account_id` in `photographer_private_details`.
    3. Pass transfers array in Razorpay Order Creation / Payment Capture.
  - Until Razorpay Route linked accounts are configured in the live merchant account, photographer payouts safely remain in `pending` state in `public.payouts` without claiming fake money transfers.

---

## 6. Verification Status

| Component / Boundary | Verification Method | Local Result |
| :--- | :--- | :---: |
| **Payment Success Wrapper Security** | `supabase/tests/database/09_pyp_payment_success_test.sql` | **PASS (12/12 checks)** |
| **Payment Conflict & Deduplication** | `supabase/tests/database/10_pyp_payment_conflict_test.sql` | **PASS (5/5 checks)** |
| **Payment Input Validation** | `supabase/tests/database/11_pyp_payment_validation_test.sql` | **PASS (4/4 checks)** |
| **Concurrency & Refund Handling** | `supabase/tests/database/03_pyp_concurrency_and_refunds_test.sql` | **PASS (11/11 checks)** |
| **Edge Function Signature Security** | Static inspection of Edge Functions & TypeScript RPC call sites | **VERIFIED (`schema: "public"`)** |
| **Live Production Payment Processing** | Remote Razorpay API & production Edge Function invocation | **Pending Production Setup** |
