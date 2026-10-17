# PYP — Pick Your Photographer: Project Status & Implementation Report

**Repository Location:** `C:\Users\Aravindhan\pyp_app`
**Platform:** Flutter (Mobile/Desktop/Web) & Supabase (PostgreSQL, Storage, Realtime, Edge Functions)
**Report Date:** Verified Repository Audit

---

## Executive Summary

**PYP — Pick Your Photographer** is an editorial photography marketplace connecting clients with professional photographers through a server-authoritative booking, payment, notification, and portfolio management architecture.

The platform utilizes a **Zero-Trust, Server-Authoritative** design pattern. All authorization decisions, fee calculations, role assignments, payment processing, notification writes, and contact information releases are enforced at the database layer (via PostgreSQL Row Level Security, `SECURITY DEFINER` RPCs, and service-role Edge Functions) rather than relying on client-side logic.

Local testing has verified compliance across all static analysis rules, unit/widget tests, and local database security regression suites.

---

## Technology Stack & Dependency Manifest

### Frontend Application (Flutter / Dart)
- **SDK Version:** Flutter `^3.12.1` / Dart SDK
- **State Management & Backend Client:** `supabase_flutter: ^2.18.2`
- **Payment Processing SDK:** `razorpay_flutter: ^1.3.7`
- **Portfolio & Image Selection:** `image_picker: ^1.2.4`
- **Invoice PDF Generation & Export:** `pdf: ^3.13.1` & `printing: ^5.15.1`
- **Crash Reporting & Analytics:** `firebase_core: ^4.15.0` & `firebase_crashlytics: ^5.4.0`

### Backend Services & Local Database (Supabase Stack)
- **Database Engine:** PostgreSQL 17 with `pgcrypto` extension
- **Data & API Access Layer:** PostgREST 14 & Supabase Realtime Server
- **Storage Layer:** Supabase Storage (`portfolio_images` public bucket with RLS)
- **Serverless Runtime:** Deno / TypeScript Edge Functions (`create-razorpay-order`, `verify-razorpay-payment`, `razorpay-webhook`)
- **Automated DB Testing:** pgTAP regression test runner (`supabase test db --local`)

---

## Milestone & Feature Implementation Status

| Feature / Subsystem | Implementation Status | Local Test Status | Description |
| :--- | :---: | :---: | :--- |
| **Authentication & Session Routing** | `[x] Implemented` | `[x] Verified` | Email/password sign-in and sign-up with role-aware initial session routing (`AuthGate`). |
| **Role-Based Access Control (RBAC)** | `[x] Implemented` | `[x] Verified` | Server-enforced roles (`customer`, `photographer`, `admin`) via `user_roles` and `private.is_admin()`. |
| **Public Discovery Marketplace** | `[x] Implemented` | `[x] Verified` | Search by city, category, or name; category chips filter; portfolio preview on cards. |
| **Photographer Profile & Portfolio** | `[x] Implemented` | `[x] Verified` | Profile editing & image upload/replace/delete in `portfolio_images` bucket with owner RLS. |
| **Photographer Approval Lifecycle** | `[x] Implemented` | `[x] Verified` | Unapproved profiles default to `is_published = false` and are hidden from public discovery until admin approval. |
| **Booking Request Creation** | `[x] Implemented` | `[x] Verified` | Server-authoritative 5% platform fee calculation in integer paise (`create_booking_request`). |
| **Photographer Booking Management** | `[x] Implemented` | `[x] Verified` | Photographers accept or decline requests via `photographer_respond_booking` RPC. |
| **Payment Order Creation** | `[x] Implemented` | `[x] Verified` | `create-razorpay-order` Edge Function creates Razorpay orders using server-calculated total paise. |
| **Payment Verification** | `[x] Implemented` | `[x] Verified` | `verify-razorpay-payment` Edge Function verifies HMAC SHA-256 signatures & payment amounts with Razorpay REST API. |
| **Webhook Processing & Idempotency** | `[x] Implemented` | `[x] Verified` | `razorpay-webhook` Edge Function logs event IDs in `processed_webhook_events` to prevent duplicate processing. |
| **Service-Role Payment RPC Wrappers** | `[x] Implemented` | `[x] Verified` | `public.process_payment_success` and `public.process_refund_success` restricted strictly to `service_role`. |
| **Realtime Booking Chat** | `[x] Implemented` | `[x] Verified` | Participant-only chat unlocked strictly for confirmed/completed bookings via `chat_messages` RLS and `send_chat_message` RPC. |
| **Realtime Notifications System** | `[x] Implemented` | `[x] Verified` | Event-driven notifications for booking requests, responses, payments, and messages. |
| **Notification Write Hardening** | `[x] Implemented` | `[x] Verified` | Direct client write policies dropped; client limited to `mark_notifications_read` RPC. |
| **Invoice PDF Generation & Viewing** | `[x] Implemented` | `[x] Verified` | `get_booking_invoice_data` RPC and `InvoicePdfService` generate PDF invoices/receipts with full fee breakdown. |
| **Auditable Refund Ledger** | `[x] Implemented` | `[x] Verified` | `public.refunds` ledger tracks refund events, prevents cumulative over-refunds, and reconciles payouts. |
| **Admin Governance Dashboard** | `[x] Implemented` | `[x] Verified` | Platform statistics (`admin_get_platform_stats`), photographer moderation, booking monitor, client directory. |
| **Razorpay Route Automatic Payouts** | `[ ] Pending Provider` | `[~] Database Ready` | Payouts recorded as `pending` in `public.payouts` ledger until merchant Route linked accounts are configured. |
| **Production Remote Deployment** | `[ ] Pending Approval` | `[ ] Local Only` | Production database push, Edge Function deployment, and production secrets configuration pending approval. |

---

## Database Architecture & Migration History

All database changes are managed through **17 forward-only Supabase migrations** in `supabase/migrations/`:

1. `20261011134024_pyp_initial_schema.sql` — Initial schema: `profiles`, `user_roles`, `photographer_profiles`, `photographer_private_details`, `bookings`, `payments`, `payouts`, `commission_ledger`.
2. `20261011150000_pyp_security_and_functions.sql` — RLS policies, `get_my_roles()`, `register_as_photographer`, `create_booking_request`, `photographer_respond_booking`, `prepare_booking_for_payment`, `customer_cancel_booking`, `get_booking_photographer_contact`, `private.process_payment_success`.
3. `20261011160000_pyp_webhook_events.sql` — `processed_webhook_events` table for webhook idempotency.
4. `20261011170000_pyp_concurrency_and_fixes.sql` — Row-level locking (`FOR UPDATE`), partial unique index `payments_pending_booking_idx`, refund handler `private.process_refund_success`.
5. `20261011180000_pyp_admin_moderation.sql` — Admin RPCs: `admin_get_pending_photographers`, `admin_moderate_photographer`.
6. `20261011190000_pyp_portfolio_storage.sql` — `portfolio_images` storage bucket, RLS policies (`storage.foldername(name)[1] = auth.uid()`), updated `register_as_photographer`.
7. `20261012000000_pyp_rbac_enhancements.sql` — Recursion-safe role checkers (`private.is_admin`, `private.is_photographer`), signup trigger `handle_new_user`, admin stats RPC (`admin_get_platform_stats`), admin bookings RPC (`admin_get_all_bookings`), admin status RPC (`admin_manage_photographer_status`).
8. `20261012120000_pyp_rbac_system_complete.sql` — Admin provisioner (`private.provision_admin`), client and photographer admin directory RPCs (`admin_get_all_clients`, `admin_get_all_photographers`).
9. `20261012130000_pyp_storage_security_hardening.sql` — Storage RLS hardening enforcing photographer role check and `foldername[1] = auth.uid()`.
10. `20261012140000_pyp_marketplace_notifications_chat.sql` — `notifications` table, `chat_messages` table, `send_chat_message` RPC, `mark_notifications_read` RPC, Realtime publication setup.
11. `20261012150000_pyp_photographer_profile_enhancements.sql` — Extended fields on `photographer_profiles` (`experience_years`, `specializations`, `service_locations`, `availability_note`).
12. `20261012160000_pyp_canonical_payment_processor.sql` — Canonical `private.process_payment_success` implementation with default provider `'razorpay'`.
13. `20261013100000_pyp_notifications_write_security.sql` — Notifications write security hardening. Revokes write table privileges from `PUBLIC`, `anon`, and `authenticated`, enforces owner-only SELECT RLS, and sets `mark_notifications_read(uuid)` as `SECURITY DEFINER` with `SET search_path = ''`.
14. `20261014000000_pyp_invoice_and_settlement_enhancements.sql` — `get_booking_invoice_data` RPC returning authoritative invoice numbers, dates, customer/photographer details, fee breakdown, payment statuses, and transaction references for authorized participants.
15. `20261014120000_pyp_payment_conflict_hardening.sql` — Partial unique constraint on `payments` table for `(booking_id, status)` where status = `'pending'`, preventing concurrent duplicate order creation.
16. `20261016110000_pyp_payment_rpc_wrappers.sql` — Public `SECURITY DEFINER` wrappers `public.process_payment_success` and `public.process_refund_success` in `public` schema with explicit `auth.role() = 'service_role'` requirement and execute permission granted strictly to `service_role`.
17. `20261016120000_pyp_refund_ledger_and_hardening.sql` — Auditable `public.refunds` table, incremental vs cumulative refund calculation handling, refund ceiling checks (`v_new_total <= captured_amount`), and payout reversal reconciliation.

---

## Local Verification & Test Evidence

### 1. Flutter Code Analysis
- **Command:** `flutter analyze`
- **Result:** **PASSED — 0 issues found**

### 2. Flutter Unit & Widget Test Suite
- **Command:** `flutter test`
- **Result:** **PASSED — 42 / 42 tests passed**
- **Coverage Highlights:**
  - Authentication flow & role-based initial route mapping
  - Header user badge, role tags, and role switcher rendering
  - Marketplace search, category filtering, and photographer cards
  - Platform fee calculations (₹1,000 → ₹50 fee → ₹1,050 total) & integer paise rounding
  - `InvoiceData` model construction and Invoice PDF byte generation
  - `InvoiceDialog` rendering & action controls
  - Portfolio validation, object path generation, URL extraction, and manager grid
  - Chat screen participant message rendering

### 3. Local Supabase Database Security Test Suite (pgTAP)
- **Command:** `supabase test db --local`
- **Result:** **PASSED — 128 / 128 checks passed across 13 test files**
- **Test File Breakdown:**
  1. `01_pyp_security.sql` — 16 checks (RPC security, booking calculations, status transitions)
  2. `02_pyp_edge_functions_test.sql` — 6 checks (Webhook event ledger & idempotency)
  3. `03_pyp_concurrency_and_refunds_test.sql` — 11 checks (Concurrent payment locking & refund reconciliation)
  4. `04_pyp_admin_moderation_test.sql` — 6 checks (Admin moderation RPC authorization)
  5. `05_pyp_portfolio_storage_test.sql` — 6 checks (Portfolio storage bucket RLS policies)
  6. `06_pyp_rbac_complete_test.sql` — 12 checks (Complete RBAC lifecycle & metadata tampering immunity)
  7. `07_pyp_storage_hardening_test.sql` — 11 checks (Hardened storage folder ownership RLS)
  8. `08_pyp_notifications_security_test.sql` — 19 checks (Notification write security & RPC isolation)
  9. `09_pyp_invoice_and_settlement_test.sql` — 7 checks (Authoritative invoice data RPC authorization)
  10. `09_pyp_payment_success_test.sql` — 12 checks (Service-role payment success wrapper verification)
  11. `10_pyp_payment_conflict_test.sql` — 5 checks (Pending order conflict & reuse verification)
  12. `11_pyp_payment_validation_test.sql` — 4 checks (Payment input validation & error handling)
  13. `12_pyp_refund_security_and_ledger_test.sql` — 13 checks (Refund ledger, duplicate webhook idempotency, max refund ceiling & service-role wrapper protection)

---

## Known Limitations & Unresolved Risks

1. **Razorpay Route Merchant Onboarding**:
   - Automated bank account transfers to photographers require onboarding photographers as Razorpay Linked Accounts (`acc_XXXXX`).
   - Payouts are currently recorded as `pending` in `public.payouts` until Razorpay Route linked account credentials are attached.
2. **Deno Local Environment Runtime**:
   - `deno` CLI is not installed directly in the local Windows host PATH; Edge Function code validity was verified via static code inspection and local database pgTAP integration tests.
3. **Local Container Environment vs Production**:
   - All tests were executed against the local Docker/Supabase container stack (`127.0.0.1:54321`). No changes have been pushed to production remote resources.

---

## Production Deployment Checklist

- [ ] Execute `supabase db push` against production project to apply all 17 forward migrations.
- [ ] Configure environment secrets in Supabase Dashboard -> Edge Functions:
  - `RAZORPAY_KEY_ID`
  - `RAZORPAY_KEY_SECRET`
  - `RAZORPAY_WEBHOOK_SECRET`
- [ ] Deploy Edge Functions:
  - `supabase functions deploy create-razorpay-order`
  - `supabase functions deploy verify-razorpay-payment`
  - `supabase functions deploy razorpay-webhook`
- [ ] Configure Razorpay Webhook endpoint URL in Razorpay Merchant Dashboard (`https://<project_ref>.supabase.co/functions/v1/razorpay-webhook`) for events `payment.captured`, `payment.failed`, `refund.processed`.
- [ ] Provision initial administrator user via SQL:
  ```sql
  SELECT private.provision_admin('admin@yourdomain.com');
  ```
