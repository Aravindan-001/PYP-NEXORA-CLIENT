# PYP — Pick Your Photographer

<div align="center">

  <h3>Pick Your Photographer — Premium Editorial Marketplace</h3>
  <p>An editorial photography marketplace connecting clients with vetted professional photographers through server-authoritative booking, payment, notification, and portfolio management workflows.</p>

  [![Flutter](https://img.shields.io/badge/Flutter-3.19+-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
  [![Supabase](https://img.shields.io/badge/Supabase-PostgreSQL%2017-3FCF8E?style=for-the-badge&logo=supabase&logoColor=white)](https://supabase.com)
  [![Dart](https://img.shields.io/badge/Dart-3.3+-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
  [![License](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge)](LICENSE)

  [![Analysis](https://img.shields.io/badge/Flutter_Analyze-0_Issues-brightgreen?style=flat-square)](https://flutter.dev)
  [![Flutter Tests](https://img.shields.io/badge/Flutter_Tests-42%2F42_Passed-success?style=flat-square)](https://flutter.dev)
  [![Database Tests](https://img.shields.io/badge/Database_pgTAP-128%2F128_Passed-success?style=flat-square)](https://supabase.com)
  [![Migrations](https://img.shields.io/badge/Migrations-17_Forward_Only-blue?style=flat-square)](supabase/migrations)

</div>

---

## 📚 Technical Documentation Index

| Document | Primary Focus & Contents |
| :--- | :--- |
| 📊 **[Project Status](docs/PROJECT_STATUS.md)** | Executive summary, tech stack manifest, milestone checklist, test evidence & deployment status. |
| 🏗️ **[System Architecture](docs/ARCHITECTURE.md)** | High-level component design, Flutter layers, Supabase backend, Edge Functions, trust boundaries. |
| 🔄 **[Booking Lifecycle](docs/BOOKING_LIFECYCLE.md)** | Booking state machine, transition matrix, financial fee formulas, chat unlocking & refund settlement. |
| 🛡️ **[Security Model](docs/SECURITY_MODEL.md)** | RBAC enforcement, PostgreSQL RLS policies, storage folder RLS, service-role RPC wrappers, threat matrix. |
| 🗄️ **[Database Schema](docs/DATABASE_SCHEMA.md)** | Mermaid ER diagram, table references, custom ENUM types, key indexes, 17 chronological migrations. |
| 🧪 **[Testing Strategy](docs/TESTING.md)** | Flutter analyze, 42 widget tests, 128 pgTAP DB checks, PowerShell runner, integration test setup. |
| 🚀 **[Deployment Guide](docs/DEPLOYMENT.md)** | Supabase migration push, Edge Function deployment, secret configuration, release builds & rollback steps. |
| 💳 **[Payment & Security Flow](docs/PAYMENT_FLOW_AND_SECURITY.md)** | End-to-end Razorpay integration, HMAC verification, webhook deduplication, refund ledger processing. |
| 🗺️ **[Product Roadmap](ROADMAP.md)** | Completed features, in-progress onboarding, and planned post-launch enhancements. |

---

## ⚡ Verified Status Dashboard

| Verification Layer | Local Test Command | Execution Result | Verification Scope |
| :--- | :--- | :---: | :--- |
| **Flutter Static Analysis** | `flutter analyze` | **PASSED (0 issues)** | Zero lint, type, or static analysis warnings across `lib/` and `test/`. |
| **Flutter Test Suite** | `flutter test test` | **PASSED (42 / 42)** | Auth routing, marketplace search, fee calculations, PDF invoice export & chat. |
| **Database Security (pgTAP)** | `supabase test db --local` | **PASSED (128 / 128)** | RLS policies, RBAC, RPC authorization, refund ceiling, notification write security. |
| **Automated Test Runner** | `.\tool\run_pyp_tests.ps1` | **PASSED (2 / 2 tasks)** | Combined analyzer and widget test execution script. |
| **Local Migrations** | `supabase migration list` | **17 Applied** | 17 forward-only SQL migrations applied to local container database. |

---

## 🏛️ System Architecture

PYP utilizes a **Zero-Trust, Server-Authoritative Architecture**. Authorization decisions, 5% fee calculations, role checks, and contact detail releases are enforced at the database layer.

```mermaid
graph TD
    ClientApp[Flutter Cross-Platform App<br/>Android / iOS / Web / Windows] <-->|Restricted PostgREST API| SupabaseData[Supabase PostgreSQL 17]
    ClientApp <-->|Realtime Subscriptions| SupabaseRealtime[Supabase Realtime]
    ClientApp <-->|Public Bucket RLS| SupabaseStorage[Supabase Storage: portfolio_images]

    ClientApp -->|JWT Auth Token| EdgeFunctions[Supabase Deno Edge Functions]

    subgraph "Serverless Edge Layer (Deno Runtime)"
        EF1[create-razorpay-order]
        EF2[verify-razorpay-payment]
        EF3[razorpay-webhook]
    end

    EdgeFunctions <-->|HMAC & REST Verification| RazorpayGateway[Razorpay Payment Gateway]
    EdgeFunctions -->|Service-Role Key| PublicWrappers[Public RPC Wrappers<br/>public.process_payment_success<br/>public.process_refund_success]

    subgraph "Database Isolation & Security Core"
        PublicWrappers -->|Service-Role Check| PrivateSchema[Private Schema<br/>private.process_payment_success<br/>private.process_refund_success]
        PrivateSchema --> BookingsTable[(public.bookings)]
        PrivateSchema --> PaymentsTable[(public.payments)]
        PrivateSchema --> LedgerTable[(public.commission_ledger)]
        PrivateSchema --> PayoutsTable[(public.payouts)]
        PrivateSchema --> RefundsTable[(public.refunds)]
    end
```

---

## 🔄 Booking & Settlement Journey

```mermaid
sequenceDiagram
    autonumber
    actor Customer
    participant FlutterApp as Flutter App
    participant DB as Supabase DB (PostgreSQL)
    actor Photographer
    participant Edge as Deno Edge Functions
    participant Razorpay as Razorpay API

    Customer->>FlutterApp: Selects photographer & fills event details
    FlutterApp->>DB: rpc('create_booking_request', params)
    Note over DB: Calculates 5% platform fee in integer paise<br/>total = quote + 5% fee
    DB-->>FlutterApp: Returns booking_id (status: 'requested')

    Photographer->>FlutterApp: Reviews request on dashboard
    FlutterApp->>DB: rpc('photographer_respond_booking', accept=true)
    DB-->>FlutterApp: Status transitions to 'accepted'

    Customer->>FlutterApp: Initiates deposit checkout
    FlutterApp->>Edge: POST /create-razorpay-order (booking_id)
    Edge->>DB: rpc('prepare_booking_for_payment')
    Note over DB: Row locked FOR UPDATE<br/>status -> 'awaiting_payment'
    Edge->>Razorpay: POST /v1/orders (amount_paise)
    Razorpay-->>Edge: Returns order_id
    Edge-->>FlutterApp: Order ID & checkout parameters

    Customer->>Razorpay: Completes payment checkout
    Razorpay-->>Edge: Webhook or client verification request
    Note over Edge: Verifies HMAC SHA-256 signature<br/>& payment details
    Edge->>DB: rpc('process_payment_success') [service_role]
    Note over DB: Status -> 'confirmed'<br/>Commission posted to ledger<br/>Payout recorded as pending<br/>Participant chat unlocked
```

---

## 💡 Role-Based Feature Matrix

| Capability / Feature | Customer (`customer`) | Photographer (`photographer`) | Administrator (`admin`) |
| :--- | :---: | :---: | :---: |
| **Marketplace Search & Category Filter** | ✅ | ✅ | ✅ |
| **View Published Portfolios** | ✅ | ✅ | ✅ |
| **Submit Booking Requests** | ✅ | ❌ | ❌ |
| **Accept / Decline Booking Requests** | ❌ | ✅ | ❌ |
| **Upload / Manage Portfolio Images** | ❌ | ✅ | ❌ |
| **Pay Booking Deposit via Razorpay** | ✅ | ❌ | ❌ |
| **Realtime Chat (Confirmed Bookings)** | ✅ | ✅ | ❌ |
| **Generate & Export PDF Invoices** | ✅ | ✅ | ✅ |
| **View Private Contact Details** | ✅ (Confirmed Only) | ✅ (Confirmed Only) | ✅ |
| **Approve / Suspend Photographers** | ❌ | ❌ | ✅ |
| **View Platform Revenue & Stats** | ❌ | ❌ | ✅ |

---

## 💰 Financial Logic & Platform Fee Breakdown

PYP charges customers a transparent **5% platform service fee** on top of the photographer's quoted price:

- **Formula**:
  $$\text{platform\_fee\_paise} = \text{round}\left(\frac{\text{photographer\_quote\_paise} \times 5.0}{100.0}\right)$$
  $$\text{customer\_total\_paise} = \text{photographer\_quote\_paise} + \text{platform\_fee\_paise}$$
- **Example Breakdown**:
  - Photographer Quotation: **₹1,000** (100,000 paise)
  - PYP Platform Fee (5%): **₹50** (5,000 paise)
  - Customer Total Payable: **₹1,050** (105,000 paise)
  - Photographer Payout: **₹1,000** (100,000 paise)
  - PYP Retained Platform Revenue: **₹50** (5,000 paise)
- **Monetary Precision**: All monetary values are handled strictly in integer paise across database RPCs, Edge Functions, and Flutter UI, avoiding floating-point currency rounding errors.

---

## 🛡️ Security Architecture Summary

- **Server-Side Authorization**: Roles are stored in `public.user_roles` and checked using recursion-safe functions (`private.is_admin()`).
- **Metadata Tampering Immunity**: Public signups passing `requested_role: 'admin'` in user metadata are strictly overridden to `customer` by the `private.handle_new_user()` trigger.
- **Row Level Security (RLS)**: Active on 100% of tables. Direct client write privileges on `payments`, `payouts`, `commission_ledger`, `refunds`, and `notifications` are revoked.
- **Service Role RPC Wrappers**: `public.process_payment_success` and `public.process_refund_success` specify `SECURITY DEFINER`, `SET search_path = ''`, and enforce `auth.role() = 'service_role'`.
- **Storage Ownership RLS**: Files in `portfolio_images` bucket are strictly bound to `<user_id>/...` folders using `(storage.foldername(name))[1] = auth.uid()`.

---

## 🗄️ Database & Edge Functions Overview

- **Database Engine**: PostgreSQL 17 with 17 forward-only SQL migrations (`20261011134024` through `20261016120000`).
- **Edge Functions**:
  - `create-razorpay-order`: Generates Razorpay checkout orders.
  - `verify-razorpay-payment`: Validates payment signatures and confirms bookings.
  - `razorpay-webhook`: Asynchronous webhook handler for captured payments, failures, and refunds with event deduplication (`processed_webhook_events`).

---

## 📂 Repository Directory Tree

```
pyp_app/
├── docs/                               # Comprehensive Technical Documentation
│   ├── ARCHITECTURE.md                 # System architecture & component design
│   ├── BOOKING_LIFECYCLE.md            # Booking state machine & financial formulas
│   ├── DATABASE_SCHEMA.md              # Database ER diagram & 17 migrations
│   ├── DEPLOYMENT.md                   # Migration, Edge Function & build setup
│   ├── PAYMENT_FLOW_AND_SECURITY.md    # Razorpay, HMAC & RPC wrapper security
│   ├── PROJECT_STATUS.md               # Executive status report & test evidence
│   ├── SECURITY_MODEL.md               # RLS policies & threat mitigation
│   └── TESTING.md                      # Flutter & pgTAP testing guide
├── lib/
│   ├── main.dart                       # Core app entry, routing & screens
│   ├── firebase_options.dart           # FlutterFire configuration options
│   ├── theme/
│   │   └── app_theme.dart              # Material 3 dark editorial design system
│   ├── services/
│   │   ├── portfolio_service.dart      # Storage bucket image manager
│   │   └── invoice_pdf_service.dart    # Authoritative PDF invoice generator
│   └── widgets/
│       ├── booking_card.dart           # Booking card with actions & status badges
│       ├── booking_chat_screen.dart    # Realtime confirmed booking chat
│       ├── booking_dialog.dart         # Booking request modal & date picker
│       ├── empty_state_widget.dart     # Reusable loading, error & empty states
│       ├── image_preview_dialog.dart   # Interactive photo preview dialog
│       ├── invoice_dialog.dart         # Invoice viewer & PDF export sheet
│       ├── notifications_widget.dart   # Realtime notification center
│       ├── photographer_card.dart      # Marketplace photographer card
│       ├── portfolio_manager_widget.dart  # Photographer portfolio uploader
│       ├── portfolio_viewer_widget.dart  # Customer portfolio showcase
│       └── pyp_header.dart             # Responsive header & role switcher
├── test/                               # 42 Flutter unit & widget tests
├── integration_test/                   # Mobile & web integration tests
├── supabase/
│   ├── functions/                      # Deno Edge Functions
│   │   ├── create-razorpay-order/
│   │   ├── verify-razorpay-payment/
│   │   └── razorpay-webhook/
│   ├── migrations/                     # 17 forward-only SQL migrations
│   └── tests/database/                 # 13 pgTAP database security test suites
├── tool/
│   └── run_pyp_tests.ps1               # Automated PowerShell test runner
├── ROADMAP.md                          # Product roadmap & feature milestones
├── pubspec.yaml
└── README.md
```

---

## 🛠️ Local Setup & Development Instructions

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (`^3.19.0` or higher)
- [Supabase CLI](https://supabase.com/docs/guides/cli) (`v2.117.0` or higher)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/)

### 1. Environment Configuration
Create a `.env` file in the project root or configure environment secrets in Supabase Edge Functions:

```env
# Flutter Client Variables
SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_ANON_KEY=your_publishable_anon_key_here

# Supabase Edge Function Secrets (Set via 'supabase secrets set')
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key_here
RAZORPAY_KEY_ID=your_razorpay_key_id_here
RAZORPAY_KEY_SECRET=your_razorpay_key_secret_here
RAZORPAY_WEBHOOK_SECRET=your_razorpay_webhook_secret_here
```

### 2. Running Local Supabase Stack
```bash
# Start local Supabase containers
supabase start

# Run all 128 local pgTAP database security tests
supabase test db --local
```

### 3. Running Flutter Application
```bash
# Install Flutter dependencies
flutter pub get

# Run static code analysis
flutter analyze

# Run unit and widget tests
flutter test test
```

---

## 📄 License & Contribution

This project is maintained for the **PYP — Pick Your Photographer** marketplace. Contributions and security improvements should follow forward-only database migration standards and include accompanying pgTAP security tests.
