# PYP — Security Architecture & Threat Mitigation Model

**Project:** PYP (Pick Your Photographer)  
**Security Standard:** Server-Authoritative Zero-Trust Security Model  
**Audit Status:** Hardened & Tested (128 pgTAP DB Security Checks + 42 Flutter Tests)  

---

## 1. Security Principles & Architecture

The PYP platform is engineered around three non-negotiable security principles:

1. **Zero Client Trust**: The Flutter mobile/web/desktop app is treated as an untrusted client environment. Client-supplied amounts, user metadata roles, or status flags are never trusted for authorization.
2. **Database-Level Authorization**: PostgreSQL Row Level Security (RLS) policies and `SECURITY DEFINER` RPCs enforce all access controls directly in the database engine.
3. **Privileged Function Isolation**: Internal payment processors live in the `private` schema. Public RPC wrappers in the `public` schema enforce `auth.role() = 'service_role'` and are granted strictly to the `service_role`.

---

## 2. Authentication & Identity Management

- **Provider:** Supabase Auth (GoTrue).
- **Tokens:** Short-lived JWTs passed in `Authorization: Bearer <token>` headers.
- **Identity Propagation:** Functions extract authenticated caller ID via `auth.uid()`. Unauthenticated requests (`auth.uid() IS NULL`) raise immediate database exceptions.

---

## 3. Authorization & Role-Based Access Control (RBAC)

User roles are stored in `public.user_roles(user_id, role)`. Supported roles:
- `customer`: Base client role granted on signup.
- `photographer`: Granted upon photographer registration or onboarding.
- `admin`: Provisioned strictly via SQL procedure (`private.provision_admin('email')`).

### 3.1 Recursion-Safe Role Check Helpers
To prevent infinite recursion loops in RLS policies, helper functions in the `private` schema inspect roles securely:

```sql
CREATE OR REPLACE FUNCTION private.is_admin_user(p_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = p_user_id AND role = 'admin'
  );
$$;
```

### 3.2 Metadata Self-Assignment Prevention
Public signups passing `requested_role: 'admin'` in `raw_user_meta_data` are strictly filtered by the database trigger `private.handle_new_user()`, which assigns only the `customer` role and ignores `'admin'`.

---

## 4. PostgreSQL Row Level Security (RLS) Reference

RLS is enabled on **100% of application tables**:

| Table | RLS Status | Permitted Operations | RLS Policy Rule |
| :--- | :---: | :--- | :--- |
| `public.profiles` | Enabled | `SELECT`, `UPDATE` | Users read/update own profile; clients read published photographer/booking counterparties; admins read all. |
| `public.user_roles` | Enabled | `SELECT` | Users read own roles; admins read all roles. Direct client `INSERT`/`UPDATE`/`DELETE` revoked. |
| `public.photographer_profiles` | Enabled | `SELECT`, `UPDATE` | Public reads `is_published = true`; photographers manage own profile; admins read/manage all. |
| `public.photographer_private_details` | Enabled | None (RPC Only) | Direct client `SELECT`/`INSERT`/`UPDATE` revoked. Released only via `get_booking_photographer_contact` for confirmed bookings. |
| `public.bookings` | Enabled | `SELECT` | Booking participants (customer or photographer) and admins can view relevant bookings. |
| `public.payments` | Enabled | `SELECT` | Booking participants and admins can view payment records. Direct client writes revoked. |
| `public.payouts` | Enabled | `SELECT` | Assigned photographer and admins can view payout records. Direct client writes revoked. |
| `public.commission_ledger` | Enabled | None (Admin Only) | Direct client access revoked. Read via admin RPC `admin_get_platform_stats`. |
| `public.refunds` | Enabled | `SELECT` | Booking participants and admins can view refund records. Direct client writes revoked. |
| `public.chat_messages` | Enabled | `SELECT`, `INSERT` | Participants of confirmed or completed bookings can read and send messages. |
| `public.notifications` | Enabled | `SELECT` | Users read own notifications (`user_id = auth.uid()`). Direct client writes revoked. |

---

## 5. Storage Security & Folder Ownership RLS

The `portfolio_images` storage bucket is protected by storage RLS policies on `storage.objects`:

```sql
-- Upload Policy: Photographers can upload only to their own folder
CREATE POLICY "Photographers can upload portfolio images to own folder"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'portfolio_images'
    AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
    AND private.is_photographer((SELECT auth.uid()))
  );
```

- **Path Enforcement:** Files must be uploaded to `<user_id>/<timestamp>_<filename>`.
- **Cross-User Overwrites:** Attempts by User A to upload or delete files under `UserB/...` are rejected by Storage RLS.

---

## 6. Privileged RPC Wrappers & Service Role Isolation

Payment processing functions (`process_payment_success`, `process_refund_success`) live in the `private` schema and are not exposed over PostgREST.

Public wrapper functions in the `public` schema delegate execution while enforcing service-role authorization:

```sql
CREATE FUNCTION public.process_payment_success(
    p_booking_id uuid,
    p_provider_order_id text,
    p_provider_payment_id text,
    p_amount_paise integer,
    p_provider text
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
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
$$;
```

---

## 7. Threat Matrix & Countermeasures

| Potential Threat / Attack Vector | Mitigation Strategy | Verification Evidence |
| :--- | :--- | :--- |
| **Client Price Tampering** | Booking amounts and fees calculated server-side in integer paise (`create_booking_request`). | `01_pyp_security.sql` Test 6 |
| **Admin Self-Assignment** | Metadata signup trigger ignores `'admin'` role requests. | `06_pyp_rbac_complete_test.sql` Test 3 |
| **Notification Forgery** | Direct client `INSERT`/`UPDATE` revoked on `notifications` table. | `08_pyp_notifications_security_test.sql` Test 1-3 |
| **Unpublished Profile Leak** | Public SELECT RLS enforces `is_published = true`. | `06_pyp_rbac_complete_test.sql` Test 5 |
| **Duplicate Payment Orders** | `payments_pending_booking_idx` partial unique constraint. | `10_pyp_payment_conflict_test.sql` Test 1-5 |
| **Duplicate Webhook Processing** | `processed_webhook_events` primary key deduplication. | `02_pyp_edge_functions_test.sql` Test 4 |
| **Over-Refund / Excess Refund** | Cumulative refund check in `private.process_refund_success`. | `12_pyp_refund_security_and_ledger_test.sql` Test 3 |
| **Search Path Hijacking** | All `SECURITY DEFINER` functions specify `SET search_path = ''`. | `01_pyp_security.sql` Test 12 |

---

## 8. Documentation References

- [System Architecture](ARCHITECTURE.md)
- [Booking Lifecycle](BOOKING_LIFECYCLE.md)
- [Database Schema & ER Diagram](DATABASE_SCHEMA.md)
- [Testing Evidence & Procedures](TESTING.md)
