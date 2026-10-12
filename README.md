# PYP — Pick Your Photographer

An editorial photographer discovery, portfolio management, and booking platform built with **Flutter** and **Supabase**.

---

## Role-Based Access Control (RBAC) System Overview

PYP implements a production-minded, server-enforced Role-Based Access Control (RBAC) system with three distinct roles:

### 1. Client / Customer (`customer`)
- **Signup & Login:** Created by default when users register as a client on the mobile/web application.
- **Permissions:**
  - Browse, search, and filter approved/published photographers by city, category, and name.
  - View photographer public profiles and portfolio galleries (`portfolio_images` bucket).
  - Submit booking requests for desired dates, event types, and cities.
  - View and manage their own bookings (cancel pre-payment requests, pay deposit via Razorpay).
  - Access photographer contact information (phone, email) strictly after booking payment confirmation.
- **Security Boundaries:**
  - Cannot access admin tools, moderate listings, or view private contact details of unbooked photographers.
  - RLS policies restrict profile updates and booking views to owned records.

### 2. Photographer (`photographer`)
- **Signup & Onboarding:** Selected during signup (`requested_role: 'photographer'`) or registered via the photographer onboarding portal.
- **Permissions:**
  - Manage public profile details (display name, bio, city, primary photography category, starting price).
  - Manage private contact details (phone, email) made accessible only to clients with confirmed bookings.
  - Upload, replace, and delete portfolio images using Supabase Storage (`portfolio_images` bucket).
  - View incoming booking requests and accept or reject requests.
- **Moderation & Discovery Lifecycle:**
  - Upon signup/registration, photographer profiles default to `is_published = false` (Pending Approval).
  - Pending, rejected, or suspended photographer listings **do not appear** in public discovery search.
  - Only approved photographers with `is_published = true` receive public discovery visibility.

### 3. Administrator (`admin`)
- **Provisioning:**
  - Admin accounts **cannot** be created through public signup, profile updates, or client-side metadata requests.
  - Provisioned exclusively via a secure database procedure run by trusted database administrators.
- **Permissions & Dashboard:**
  - Access to dedicated Admin Platform Governance Dashboard.
  - Real-time platform statistics (Total Clients, Total Photographers, Pending Applications, Approved Listings, Total Bookings, Gross Revenue).
  - Photographer Account Moderation: View pending/approved/suspended photographers and trigger `Approve & Publish`, `Suspend`, `Reactivate`, or `Reject`.
  - Platform Bookings Monitor: Real-time visibility into all bookings across clients and photographers.
  - Registered Client Directory: Overview of all client accounts and booking activity.
- **Security Boundaries:**
  - Role checks are verified server-side via `private.is_admin()` helper functions inside PostgreSQL RLS policies and RPCs.

---

## Secure Procedure for Provisioning the First Admin

Because public signup strictly rejects any request to assign the `admin` role, the initial platform administrator must be provisioned via SQL.

### Steps to Provision an Admin:
1. Register a standard user account in PYP (e.g., `admin@pyp.com`) via the app or Supabase Auth console.
2. Open your local or production Supabase SQL Editor (or run `supabase db query`).
3. Execute the secure provisioning procedure:
   ```sql
   SELECT private.provision_admin('admin@pyp.com');
   ```
4. Upon next sign-in, the user will be assigned the `admin` role in `public.user_roles` and granted full administrative access to the Admin Dashboard.

---

## Database Migrations & Architecture

Database schema, security policies, and RPCs are managed via forward-only Supabase migrations:

- `20261011134024_pyp_initial_schema.sql`: Core schema setup (`profiles`, `user_roles`, `photographer_profiles`, `photographer_private_details`, `bookings`, `payments`, `payouts`, `commission_ledger`).
- `20261011150000_pyp_security_and_functions.sql`: RLS policies, `register_as_photographer`, `create_booking_request`, `photographer_respond_booking`, `get_booking_photographer_contact`, payment success handler.
- `20261011160000_pyp_webhook_events.sql`: Webhook event ledger and idempotency.
- `20261011170000_pyp_concurrency_and_fixes.sql`: Row locking and payment reconciliation enhancements.
- `20261011180000_pyp_admin_moderation.sql`: Admin pending list and moderation RPCs.
- `20261011190000_pyp_portfolio_storage.sql`: `portfolio_images` storage bucket and file ownership RLS policies.
- `20261012000000_pyp_rbac_enhancements.sql`: Recursion-safe role checkers (`private.is_admin`, `private.is_photographer`), admin stats, and bookings RPCs.
- `20261012120000_pyp_rbac_system_complete.sql`: Complete RBAC governance, `private.provision_admin`, client/photographer directories, and account status management (`approve`, `reject`, `suspend`, `reactivate`).

---

## Local Setup & Development Guide

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (v3.19.0 or higher)
- [Supabase CLI](https://supabase.com/docs/guides/cli)

### Running Local Supabase Database
```bash
# Start local Supabase container stack
supabase start

# Check local Supabase migration status
supabase migration list --local
```

### Running Flutter Application
```bash
# Install dependencies
flutter pub get

# Run Flutter static analysis
flutter analyze

# Execute Flutter test suite
flutter test
```

---

## Verification & Test Results

- **Flutter Unit & Widget Tests:** 17/17 tests passing (`flutter test`).
- **Flutter Code Analysis:** `flutter analyze` completed with 0 issues.
- **Database Security Tests:** Verified via pgTAP test scripts in `supabase/tests/database/`.
