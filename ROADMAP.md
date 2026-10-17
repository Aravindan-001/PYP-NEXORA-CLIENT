# PYP — Product & Technical Roadmap

**Project:** PYP — Pick Your Photographer  
**Current Milestone:** Local Feature Complete & Hardened (v1.0.0+1)  

---

## 1. Verified & Completed Features (`v1.0.0+1`)

### 1.1 Core Marketplace & Discovery
- [x] **Editorial Material 3 Design System**: Custom Obsidian Black, Warm Ivory, and Champagne Gold design system.
- [x] **Marketplace Search & Filter**: Search by city, category, or photographer display name; horizontal category chips.
- [x] **Photographer Portfolio Manager**: Image upload, replace, preview dialog, and deletion in `portfolio_images` bucket with folder-ownership RLS.
- [x] **Photographer Approval Lifecycle**: Unpublished profiles (`is_published = false`) default to pending state and are hidden from public discovery until admin approval.

### 1.2 Booking & Financial Engine
- [x] **Server-Authoritative Fee Calculation**: 5% PYP platform fee calculated and stored in integer paise (`total = quote + 5% fee`).
- [x] **Razorpay Checkout Integration**: Deno Edge Functions `create-razorpay-order`, `verify-razorpay-payment`, and `razorpay-webhook`.
- [x] **Service-Role RPC Wrappers**: `public.process_payment_success` and `public.process_refund_success` restricted strictly to `service_role`.
- [x] **Auditable Refund Ledger**: `public.refunds` table tracking refund events, preventing cumulative over-refunds, and reconciling photographer payouts.
- [x] **Authoritative Invoice PDF Export**: `get_booking_invoice_data` RPC and `InvoicePdfService` generating downloadable A4/Mobile tax invoices and receipts.

### 1.3 Communication & Governance
- [x] **Realtime Booking Chat**: Participant-only chat unlocked strictly for confirmed/completed bookings (`chat_messages`).
- [x] **Realtime Notification System**: Event-driven notifications with hardened write policies (`notifications`).
- [x] **Admin Governance Dashboard**: Platform statistics (`admin_get_platform_stats`), photographer moderation, booking monitor, and client directory.

---

## 2. In-Progress & Pending Production Onboarding

- [ ] **Production Supabase Migration Deployment**: Executing `supabase db push` against live production Supabase project.
- [ ] **Production Edge Functions Deployment**: Deploying `create-razorpay-order`, `verify-razorpay-payment`, and `razorpay-webhook` to live Supabase environment.
- [ ] **Razorpay Live Merchant Secret Configuration**: Setting live production `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, and `RAZORPAY_WEBHOOK_SECRET` in Edge Function environment secrets.
- [ ] **Initial Admin Account Provisioning**: Executing `SELECT private.provision_admin('admin@domain.com')` on production database.

---

## 3. Planned Future Roadmap (Post-Launch)

### Phase 2: Automated Payout Settlement & Calendar Sync
- [ ] **Razorpay Route Merchant Onboarding**: Automated split payouts directly to photographer bank accounts via Razorpay Linked Accounts (`acc_XXXXX`).
- [ ] **Photographer Calendar Availability**: Interactive availability calendar for photographers to block out unavailable dates.
- [ ] **FCM Push Notifications**: Firebase Cloud Messaging integration for native background push notifications on Android & iOS.

### Phase 3: Enhanced Marketplace Features
- [ ] **Verified Client Reviews & Ratings**: Post-session rating and review system restricted strictly to confirmed/completed booking clients.
- [ ] **Multi-Currency Support**: Automated currency conversion for international photography bookings.
- [ ] **In-App Media Contracts**: Digital contract signing and PDF agreement storage for session terms.

---

## 4. Documentation References

- [Project Status Report](docs/PROJECT_STATUS.md)
- [System Architecture](docs/ARCHITECTURE.md)
- [Booking Lifecycle](docs/BOOKING_LIFECYCLE.md)
- [Security Model](docs/SECURITY_MODEL.md)
- [Deployment Guide](docs/DEPLOYMENT.md)
