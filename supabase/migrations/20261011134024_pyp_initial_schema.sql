
-- PYP: Pick Your Photographer
-- Initial database schema
-- All monetary amounts are stored in paise.

create extension if not exists pgcrypto;

-- 1. User roles
create type public.app_role as enum (
  'customer',
  'photographer',
  'admin'
);

create type public.booking_status as enum (
  'requested',
  'accepted',
  'awaiting_payment',
  'confirmed',
  'completed',
  'cancelled',
  'rejected'
);

create type public.payment_status as enum (
  'pending',
  'captured',
  'failed',
  'refunded'
);

create type public.payout_status as enum (
  'pending',
  'processing',
  'paid',
  'failed',
  'reversed'
);

-- 2. Basic user profiles
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  avatar_url text,
  city text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 3. Roles: clients must not be able to assign themselves roles.
create table public.user_roles (
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.app_role not null default 'customer',
  created_at timestamptz not null default now(),
  primary key (user_id, role)
);

-- 4. Public photographer listing
create table public.photographer_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  display_name text not null,
  bio text,
  city text not null,
  category text not null,
  starting_price_paise integer not null default 100000
    check (starting_price_paise >= 0),
  portfolio_urls text[] not null default '{}',
  is_published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 5. Private contact information
-- No direct client access is granted to this table.
create table public.photographer_private_details (
  photographer_id uuid primary key
    references public.photographer_profiles(id) on delete cascade,
  phone text,
  email text,
  updated_at timestamptz not null default now()
);

-- 6. Booking requests
create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references auth.users(id),
  photographer_id uuid not null
    references public.photographer_profiles(id),
  event_date date not null,
  event_city text not null,
  event_type text not null,
  customer_note text,
  status public.booking_status not null default 'requested',
  photographer_fee_paise integer not null default 100000
    check (photographer_fee_paise >= 0),
  commission_paise integer not null default 5000
    check (commission_paise >= 0),
  total_amount_paise integer generated always as
    (photographer_fee_paise + commission_paise) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 7. Payment records
-- Payment creation and status changes must happen server-side.
create table public.payments (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id),
  provider text not null default 'razorpay',
  provider_order_id text unique,
  provider_payment_id text unique,
  amount_paise integer not null check (amount_paise >= 0),
  status public.payment_status not null default 'pending',
  verified_at timestamptz,
  created_at timestamptz not null default now()
);

-- 8. Commission ledger
create table public.commission_ledger (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null unique references public.bookings(id),
  amount_paise integer not null check (amount_paise >= 0),
  created_at timestamptz not null default now()
);

-- 9. Photographer payouts
create table public.payouts (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id),
  photographer_id uuid not null
    references public.photographer_profiles(id),
  amount_paise integer not null check (amount_paise >= 0),
  status public.payout_status not null default 'pending',
  provider_payout_id text unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 10. Indexes
create index photographer_city_category_idx
  on public.photographer_profiles(city, category)
  where is_published = true;

create index bookings_customer_idx
  on public.bookings(customer_id, created_at desc);

create index bookings_photographer_idx
  on public.bookings(photographer_id, created_at desc);

create index payments_booking_idx
  on public.payments(booking_id);

create index payouts_photographer_idx
  on public.payouts(photographer_id, created_at desc);

-- 11. Automatically create a basic profile and customer role.
-- This trigger never accepts a role from user-supplied metadata.
create schema if not exists private;

revoke all on schema private from public, anon, authenticated;

create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name)
  values (
    new.id,
    coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
      null
    )
  );

  insert into public.user_roles (user_id, role)
  values (new.id, 'customer');

  return new;
end;
$$;

revoke all on function private.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- 12. Enable Row Level Security on every application table.
alter table public.profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.photographer_profiles enable row level security;
alter table public.photographer_private_details enable row level security;
alter table public.bookings enable row level security;
alter table public.payments enable row level security;
alter table public.commission_ledger enable row level security;
alter table public.payouts enable row level security;

-- Start with no table privileges for client roles.
revoke all on public.profiles from anon, authenticated;
revoke all on public.user_roles from anon, authenticated;
revoke all on public.photographer_profiles from anon, authenticated;
revoke all on public.photographer_private_details from anon, authenticated;
revoke all on public.bookings from anon, authenticated;
revoke all on public.payments from anon, authenticated;
revoke all on public.commission_ledger from anon, authenticated;
revoke all on public.payouts from anon, authenticated;

-- 13. Explicitly grant only required client access.
grant select on public.photographer_profiles to anon, authenticated;

grant select on public.profiles to authenticated;
grant update (full_name, avatar_url, city)
  on public.profiles to authenticated;

grant select on public.bookings to authenticated;
grant select on public.payments to authenticated;
grant select on public.payouts to authenticated;

-- 14. RLS policies

create policy "Users can read their own profile"
  on public.profiles for select to authenticated
  using ((select auth.uid()) = id);

create policy "Users can update their own profile"
  on public.profiles for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

create policy "Published photographer listings are public"
  on public.photographer_profiles for select
  to anon, authenticated
  using (is_published = true);

create policy "Booking participants can read their bookings"
  on public.bookings for select to authenticated
  using (
    customer_id = (select auth.uid())
    or exists (
      select 1
      from public.photographer_profiles pp
      where pp.id = bookings.photographer_id
        and pp.user_id = (select auth.uid())
    )
  );

create policy "Booking participants can read payment records"
  on public.payments for select to authenticated
  using (
    exists (
      select 1
      from public.bookings b
      left join public.photographer_profiles pp
        on pp.id = b.photographer_id
      where b.id = payments.booking_id
        and (
          b.customer_id = (select auth.uid())
          or pp.user_id = (select auth.uid())
        )
    )
  );

create policy "Photographers can read their payout records"
  on public.payouts for select to authenticated
  using (
    exists (
      select 1
      from public.photographer_profiles pp
      where pp.id = payouts.photographer_id
        and pp.user_id = (select auth.uid())
    )
  );

-- Deliberately no client policies or grants for:
-- user_roles, photographer_private_details, commission_ledger.
-- Booking creation/status changes and payment/payout writes will
-- be implemented through validated server-side functions.
