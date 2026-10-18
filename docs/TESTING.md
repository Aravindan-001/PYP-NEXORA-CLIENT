# PYP — Verification, Quality Assurance & Test Suite Guide

**Project:** PYP (Pick Your Photographer)  
**Verification Coverage:** 42 Flutter Tests + 128 Local Database pgTAP Security Checks  
**Status:** All Automated Local Tests Passing & GitHub Actions CI Configured

---

## 1. Test Suite Architecture Overview

Testing for PYP spans four verification layers:

```
┌────────────────────────────────────────────────────────────────────────┐
│                   GITHUB ACTIONS AUTOMATED CI                          │
│  .github/workflows/ci.yml (Flutter Analyze, Widget Tests, DB pgTAP)    │
└────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                        FLUTTER TEST SUITE                              │
│  42 Unit & Widget Tests (State Routing, UI Widgets, Fee Calculations)  │
└────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                   LOCAL DATABASE pgTAP SECURITY SUITE                   │
│  128 Security & RLS Checks across 13 SQL Files (pgTAP Test Runner)     │
└────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                     POWERSHELL TEST AUTOMATION                         │
│  .\tool\run_pyp_tests.ps1 (Executes Analyzer & Widget Tests)           │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. GitHub Actions CI Pipeline (`.github/workflows/ci.yml`)

The repository includes an automated GitHub Actions CI workflow for pull requests and branch pushes:

- **`flutter-quality-ci` Job**:
  - Sets up Java 17 and Flutter `stable`.
  - Runs `flutter pub get`.
  - Verifies Dart formatting via `dart format --output=none --set-exit-if-changed .`.
  - Runs static analysis via `flutter analyze`.
  - Runs unit and widget tests via `flutter test test`.
  - Performs a dry-run release build via `flutter build web --release`.
- **`supabase-database-ci` Job**:
  - Sets up Supabase CLI.
  - Starts local Supabase container stack (`supabase start`).
  - Executes all 13 local pgTAP database security test suites (`supabase test db --local`).

---

## 3. Flutter Analysis & Test Results

### 3.1 Static Analysis (`flutter analyze`)
- **Command:** `flutter analyze`
- **Result:** **PASSED — 0 issues found**

### 3.2 Flutter Unit & Widget Tests (`flutter test test`)
- **Command:** `flutter test test`
- **Result:** **PASSED — 42 / 42 tests passed**
- **Test File Manifest:**
  - `test/widget_test.dart` — App initialization & auth entry
  - `test/auth_test.dart` — Authentication form state & submit validation
  - `test/pyp_header_test.dart` — Header user badge, role tags, and role switcher widget
  - `test/marketplace_workflow_test.dart` — Marketplace discovery, search filter, category chips & cards
  - `test/portfolio_test.dart` — Portfolio manager grid, upload validation, path generation, viewer & preview dialog
  - `test/rbac_test.dart` — Role-based initial routing & protected access controls
  - `test/financial_and_invoice_test.dart` — Fee calculations (₹1,000 → ₹50 → ₹1,050), `InvoiceData` parsing, PDF byte generation & `InvoiceDialog` rendering

---

## 4. Database Security Test Suite (pgTAP)

Database security, RLS policies, RPC authorization, refund accounting, and idempotency are tested locally using **pgTAP** via `supabase test db --local`.

- **Total Execution Result:** **128 / 128 pgTAP assertions PASSED across 13 test files**.

### 4.1 pgTAP Test File Breakdown:

| Test File | Checks | Primary Focus & Coverage Area | Status |
| :--- | :---: | :--- | :---: |
| `01_pyp_security.sql` | 16 | RPC security, booking fee calculations, status transition checks | `PASS` |
| `02_pyp_edge_functions_test.sql` | 6 | `processed_webhook_events` ledger & event deduplication | `PASS` |
| `03_pyp_concurrency_and_refunds_test.sql` | 11 | Concurrent payment row locking (`FOR UPDATE`) & refund reconciliation | `PASS` |
| `04_pyp_admin_moderation_test.sql` | 6 | Admin pending photographer listing & moderation RPC authorization | `PASS` |
| `05_pyp_portfolio_storage_test.sql` | 6 | `portfolio_images` storage bucket RLS policies | `PASS` |
| `06_pyp_rbac_complete_test.sql` | 12 | Complete RBAC lifecycle & metadata signup tampering immunity | `PASS` |
| `07_pyp_storage_hardening_test.sql` | 11 | Hardened storage folder ownership RLS (`foldername[1] = auth.uid()`) | `PASS` |
| `08_pyp_notifications_security_test.sql` | 19 | Notification write security revocation & `mark_notifications_read` RPC | `PASS` |
| `09_pyp_invoice_and_settlement_test.sql` | 7 | Authoritative invoice data RPC (`get_booking_invoice_data`) authorization | `PASS` |
| `09_pyp_payment_success_test.sql` | 12 | `public.process_payment_success` wrapper `service_role` enforcement | `PASS` |
| `10_pyp_payment_conflict_test.sql` | 5 | Pending order conflict blocking & order reuse verification | `PASS` |
| `11_pyp_payment_validation_test.sql` | 4 | Payment input validation & error handling | `PASS` |
| `12_pyp_refund_security_and_ledger_test.sql` | 13 | `public.refunds` ledger, duplicate webhook idempotency, refund ceiling checks & wrapper authorization | `PASS` |

---

## 5. Test Commands & How to Run Locally

### 5.1 Execute Local Database Security Tests
Requires local Supabase container stack running (`supabase start`):
```bash
# Run all 13 database security test suites
supabase test db --local

# Run a specific database test file
supabase test db --local "supabase/tests/database/12_pyp_refund_security_and_ledger_test.sql"
```

### 5.2 Execute Flutter Static Analysis & Tests
```bash
# Install dependencies
flutter pub get

# Run static analysis
flutter analyze

# Run unit and widget tests
flutter test test
```

### 5.3 Automated PowerShell Test Script
```powershell
# Run static analysis and widget tests
.\tool\run_pyp_tests.ps1 -SkipIntegration
```

---

## 6. Integration & Mobile Device Testing Status

- **Integration Tests Available:** `integration_test/app_smoke_test.dart` and `integration_test/auth_marketplace_test.dart`.
- **Status:** **Skipped in automated CLI run** (No active physical mobile device or Android ADB emulator attached during CLI verification).
- **Desktop/Web Compilation:** Windows desktop and Chrome web compilation verified.

---

## 7. Documentation References

- [System Architecture](ARCHITECTURE.md)
- [Booking Lifecycle](BOOKING_LIFECYCLE.md)
- [Security Model](SECURITY_MODEL.md)
- [Deployment Guide](DEPLOYMENT.md)
