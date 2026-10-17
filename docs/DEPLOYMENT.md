# PYP — Production Deployment & Environment Setup Guide

**Project:** PYP (Pick Your Photographer)  
**Target Environments:** Staging & Production (Supabase Cloud & Mobile App Stores)  

---

## 1. Prerequisites & Required Tools

Before deploying PYP to production, ensure you have the following CLI tools installed:
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (v3.19+)
- [Supabase CLI](https://supabase.com/docs/guides/cli) (`v2.117.0` or higher)
- [Firebase CLI](https://firebase.google.com/docs/cli) (for Crashlytics symbol uploads)

---

## 2. Environment Variables & Secret Configuration

Create production environment secrets in Supabase Edge Functions using the Supabase CLI. **Never commit raw secret values to Git repositories.**

```bash
# Link local CLI project to production Supabase project
supabase link --project-ref <your_production_project_ref>

# Set production Edge Function secrets
supabase secrets set --env-file .env.production
```

### Required Secret Variables:

| Variable Name | Scope | Description |
| :--- | :--- | :--- |
| `SUPABASE_URL` | Edge Functions & Flutter | Production Supabase URL (`https://<ref>.supabase.co`). |
| `SUPABASE_ANON_KEY` | Flutter Client | Publishable anon key used in Flutter client code. |
| `SUPABASE_SERVICE_ROLE_KEY` | Edge Functions | Privileged service-role key. **Never expose in Flutter.** |
| `RAZORPAY_KEY_ID` | Edge Functions | Production Razorpay Key ID (`rzp_live_XXXXX`). |
| `RAZORPAY_KEY_SECRET` | Edge Functions | Production Razorpay Secret Key. |
| `RAZORPAY_WEBHOOK_SECRET` | Edge Functions | HMAC secret for verifying Razorpay webhook signatures. |

---

## 3. Database Migration Deployment

All database changes are managed via **17 forward-only SQL migrations** in `supabase/migrations/`.

```bash
# Verify local migration history
supabase migration list --local

# Apply pending forward migrations to production database
supabase db push
```

### Safety Rules for Migration Deployment:
1. **Forward-Only**: Never edit or delete applied historical migration files (`20261011134024` through `20261016120000`).
2. **Schema Reload**: Migrations emit `NOTIFY pgrst, 'reload schema'` to update PostgREST schema caches immediately.
3. **No Reset**: Never run `supabase db reset` against staging or production database instances.

---

## 4. Edge Functions Deployment

Deploy the three serverless TypeScript Edge Functions to Supabase:

```bash
# Deploy Order Creation Edge Function
supabase functions deploy create-razorpay-order

# Deploy Payment Verification Edge Function
supabase functions deploy verify-razorpay-payment

# Deploy Webhook Event Handler Edge Function
supabase functions deploy razorpay-webhook
```

### Webhook Endpoint Configuration:
In your Razorpay Merchant Dashboard -> Settings -> Webhooks, add the production webhook URL:
`https://<project_ref>.supabase.co/functions/v1/razorpay-webhook`

**Enabled Webhook Events:**
- `payment.captured`
- `payment.failed`
- `refund.processed`
- `refund.created`

---

## 5. Provisioning the Initial Administrator Account

Because public signup strictly rejects `admin` role self-assignment, the initial platform administrator must be provisioned via SQL:

1. Register a standard user account in the app or Supabase Auth console.
2. In Supabase Dashboard -> SQL Editor, execute:
   ```sql
   SELECT private.provision_admin('admin@yourdomain.com');
   ```
3. Upon sign-in, the user will receive the `admin` role in `public.user_roles` and access to the Admin Dashboard.

---

## 6. Application Build Commands

### 6.1 Android Build (Release APK / App Bundle)
```bash
# Build Android App Bundle for Google Play Store
flutter build appbundle --release

# Build Release APK
flutter build apk --release
```

### 6.2 iOS Build
```bash
# Build iOS Release Archive
flutter build ipa --release
```

### 6.3 Web Build
```bash
# Build Web Release Bundle
flutter build web --release
```

---

## 7. Rollback & Disaster Recovery Strategy

1. **Database Rollbacks**: Since migrations are forward-only, rollbacks are performed by executing compensating forward migrations (e.g. revoking a policy or dropping an RPC via a new timestamped migration file).
2. **Edge Function Rollbacks**: Re-deploy the previously verified function commit using `supabase functions deploy <function_name>`.
3. **Flutter App Rollbacks**: Re-publish the prior signed build version to Google Play Console or Apple App Store Connect.

---

## 8. Documentation References

- [System Architecture](ARCHITECTURE.md)
- [Security Model](SECURITY_MODEL.md)
- [Database Schema & ER Diagram](DATABASE_SCHEMA.md)
- [Testing & Quality Assurance](TESTING.md)
