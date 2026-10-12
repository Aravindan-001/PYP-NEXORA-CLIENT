-- PYP: Pick Your Photographer
-- Stage 1 Migration (Audited & Security-Hardened v2): Security Policies, RPC Functions & Ledger Processing

-- Ensure payouts has a unique constraint on booking_id for idempotent ledger insertion
alter table public.payouts add constraint payouts_booking_id_key unique (booking_id);

-- ==========================================
-- 1. USER ROLES & PROFILES PRIVACY
-- ==========================================
grant select on public.user_roles to authenticated;

create policy "Users can read their own roles"
  on public.user_roles for select to authenticated
  using ((select auth.uid()) = user_id);

-- Least-privilege profile read policy:
-- Allows reading own profile, published photographer profiles, and active booking counterparties.
create policy "Users can read profiles of booking participants or published photographers"
  on public.profiles for select to authenticated
  using (
    id = (select auth.uid())
    or exists (
      select 1 from public.photographer_profiles pp
      where pp.user_id = profiles.id
        and pp.is_published = true
    )
    or exists (
      select 1 from public.bookings b
      left join public.photographer_profiles pp on pp.id = b.photographer_id
      where (b.customer_id = (select auth.uid()) and pp.user_id = profiles.id)
         or (pp.user_id = (select auth.uid()) and b.customer_id = profiles.id)
    )
  );

-- Helper function to fetch current authenticated user's roles
create or replace function public.get_my_roles()
returns table (role public.app_role)
language sql security definer
set search_path = ''
stable
as $$
  select role
  from public.user_roles
  where user_id = auth.uid();
$$;

revoke all on function public.get_my_roles() from public, anon, authenticated;
grant execute on function public.get_my_roles() to authenticated;

-- ==========================================
-- 2. PHOTOGRAPHER PROFILES & ONBOARDING
-- ==========================================
-- Strictly limit client update permissions. is_published is excluded to prevent unmoderated publication.
grant update (display_name, bio, city, category, starting_price_paise, portfolio_urls)
  on public.photographer_profiles to authenticated;

create policy "Photographers can read their own profile"
  on public.photographer_profiles for select to authenticated
  using (user_id = (select auth.uid()));

create policy "Photographers can update their own profile"
  on public.photographer_profiles for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- Onboarding / Update Photographer Profile Function
-- New profiles default to is_published = false requiring moderation/approval workflow
create or replace function public.register_as_photographer(
  p_display_name text,
  p_bio text,
  p_city text,
  p_category text,
  p_starting_price_paise integer,
  p_phone text,
  p_email text
) returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_profile_id uuid;
  v_clean_display_name text := trim(coalesce(p_display_name, ''));
  v_clean_city text := trim(coalesce(p_city, ''));
  v_clean_category text := trim(coalesce(p_category, ''));
  v_clean_bio text := trim(coalesce(p_bio, ''));
  v_clean_phone text := trim(coalesce(p_phone, ''));
  v_clean_email text := trim(coalesce(p_email, ''));
begin
  if v_user_id is null then
    raise exception 'Unauthenticated user';
  end if;

  if length(v_clean_display_name) < 2 or length(v_clean_display_name) > 100 then
    raise exception 'Display name must be between 2 and 100 characters';
  end if;

  if length(v_clean_city) < 2 or length(v_clean_city) > 100 then
    raise exception 'City must be between 2 and 100 characters';
  end if;

  if length(v_clean_category) < 2 or length(v_clean_category) > 50 then
    raise exception 'Category must be between 2 and 50 characters';
  end if;

  if p_starting_price_paise < 0 or p_starting_price_paise > 100000000 then
    raise exception 'Starting price must be between 0 and 1,000,000 INR';
  end if;

  if length(v_clean_phone) < 8 or length(v_clean_phone) > 20 then
    raise exception 'Phone number must be valid';
  end if;

  if v_clean_email !~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' then
    raise exception 'Valid email address is required';
  end if;

  -- 1. Create or update photographer profile (is_published defaults to false on insert; unchanged on update)
  insert into public.photographer_profiles (
    user_id, display_name, bio, city, category, starting_price_paise, is_published
  )
  values (
    v_user_id, v_clean_display_name, v_clean_bio, v_clean_city, v_clean_category, p_starting_price_paise, false
  )
  on conflict (user_id) do update set
    display_name = excluded.display_name,
    bio = excluded.bio,
    city = excluded.city,
    category = excluded.category,
    starting_price_paise = excluded.starting_price_paise,
    updated_at = now()
  returning id into v_profile_id;

  -- 2. Add photographer role to user_roles
  insert into public.user_roles (user_id, role)
  values (v_user_id, 'photographer')
  on conflict (user_id, role) do nothing;

  -- 3. Upsert private details
  insert into public.photographer_private_details (photographer_id, phone, email)
  values (v_profile_id, v_clean_phone, v_clean_email)
  on conflict (photographer_id) do update set
    phone = excluded.phone,
    email = excluded.email,
    updated_at = now();

  return v_profile_id;
end;
$$;

revoke all on function public.register_as_photographer from public, anon, authenticated;
grant execute on function public.register_as_photographer to authenticated;

-- ==========================================
-- 3. BOOKING CREATION, WORKFLOW & CANCELLATION
-- ==========================================

-- Secure booking creation (Server calculates fees & 5% commission)
create or replace function public.create_booking_request(
  p_photographer_id uuid,
  p_event_date date,
  p_event_city text,
  p_event_type text,
  p_customer_note text default null
) returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  v_customer_id uuid := auth.uid();
  v_fee_paise integer;
  v_commission_paise integer;
  v_booking_id uuid;
  v_photographer_user_id uuid;
  v_clean_event_city text := trim(coalesce(p_event_city, ''));
  v_clean_event_type text := trim(coalesce(p_event_type, ''));
  v_clean_note text := nullif(trim(coalesce(p_customer_note, '')), '');
begin
  if v_customer_id is null then
    raise exception 'Unauthenticated user';
  end if;

  if length(v_clean_event_city) < 2 or length(v_clean_event_city) > 100 then
    raise exception 'Event city must be specified';
  end if;

  if length(v_clean_event_type) < 2 or length(v_clean_event_type) > 50 then
    raise exception 'Event type must be specified';
  end if;

  if p_event_date < (now() at time zone 'UTC')::date then
    raise exception 'Event date cannot be in the past';
  end if;

  select starting_price_paise, user_id
  into v_fee_paise, v_photographer_user_id
  from public.photographer_profiles
  where id = p_photographer_id and is_published = true;

  if v_fee_paise is null then
    raise exception 'Photographer profile not found or inactive';
  end if;

  if v_photographer_user_id = v_customer_id then
    raise exception 'Photographers cannot book themselves';
  end if;

  -- Standard 5% platform commission calculation with precision rounding
  v_commission_paise := round((v_fee_paise * 5.0) / 100.0)::integer;

  insert into public.bookings (
    customer_id,
    photographer_id,
    event_date,
    event_city,
    event_type,
    customer_note,
    status,
    photographer_fee_paise,
    commission_paise
  )
  values (
    v_customer_id,
    p_photographer_id,
    p_event_date,
    v_clean_event_city,
    v_clean_event_type,
    v_clean_note,
    'requested',
    v_fee_paise,
    v_commission_paise
  )
  returning id into v_booking_id;

  return v_booking_id;
end;
$$;

revoke all on function public.create_booking_request from public, anon, authenticated;
grant execute on function public.create_booking_request to authenticated;

-- Booking response function for photographers
create or replace function public.photographer_respond_booking(
  p_booking_id uuid,
  p_accept boolean
) returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_booking record;
begin
  if v_user_id is null then
    raise exception 'Unauthenticated user';
  end if;

  select b.*, pp.user_id as photo_user_id into v_booking
  from public.bookings b
  join public.photographer_profiles pp on pp.id = b.photographer_id
  where b.id = p_booking_id
  for update;

  if v_booking.id is null then
    raise exception 'Booking not found';
  end if;

  if v_booking.photo_user_id != v_user_id then
    raise exception 'Unauthorized to manage this booking';
  end if;

  if v_booking.status != 'requested' then
    raise exception 'Booking status % cannot be responded to', v_booking.status;
  end if;

  if p_accept then
    update public.bookings
    set status = 'accepted', updated_at = now()
    where id = p_booking_id;
  else
    update public.bookings
    set status = 'rejected', updated_at = now()
    where id = p_booking_id;
  end if;
end;
$$;

revoke all on function public.photographer_respond_booking from public, anon, authenticated;
grant execute on function public.photographer_respond_booking to authenticated;

-- Prepare booking for payment transition function
create or replace function public.prepare_booking_for_payment(
  p_booking_id uuid
) returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_booking record;
begin
  if v_user_id is null then
    raise exception 'Unauthenticated user';
  end if;

  select * into v_booking
  from public.bookings
  where id = p_booking_id
  for update;

  if v_booking.id is null then
    raise exception 'Booking not found';
  end if;

  if v_booking.customer_id != v_user_id then
    raise exception 'Unauthorized';
  end if;

  if v_booking.status != 'accepted' then
    raise exception 'Booking status % cannot transition to awaiting_payment', v_booking.status;
  end if;

  update public.bookings
  set status = 'awaiting_payment', updated_at = now()
  where id = p_booking_id;
end;
$$;

revoke all on function public.prepare_booking_for_payment from public, anon, authenticated;
grant execute on function public.prepare_booking_for_payment to authenticated;

-- Customer cancellation function for pre-payment bookings with row locking
create or replace function public.customer_cancel_booking(
  p_booking_id uuid
) returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_booking record;
begin
  if v_user_id is null then
    raise exception 'Unauthenticated user';
  end if;

  select * into v_booking
  from public.bookings
  where id = p_booking_id
  for update;

  if v_booking.id is null then
    raise exception 'Booking not found';
  end if;

  if v_booking.customer_id != v_user_id then
    raise exception 'Unauthorized to cancel this booking';
  end if;

  -- Only pre-payment states 'requested' and 'accepted' can be cancelled directly by customer
  if v_booking.status not in ('requested', 'accepted') then
    raise exception 'Booking with status % cannot be cancelled directly by customer', v_booking.status;
  end if;

  update public.bookings
  set status = 'cancelled', updated_at = now()
  where id = p_booking_id;
end;
$$;

revoke all on function public.customer_cancel_booking from public, anon, authenticated;
grant execute on function public.customer_cancel_booking to authenticated;

-- ==========================================
-- 4. PROTECTED CONTACT INFORMATION
-- ==========================================
create or replace function public.get_booking_photographer_contact(
  p_booking_id uuid
) returns table (phone text, email text)
language plpgsql security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_photographer_id uuid;
  v_customer_id uuid;
  v_status public.booking_status;
begin
  if v_user_id is null then
    raise exception 'Unauthenticated user';
  end if;

  select b.customer_id, b.photographer_id, b.status
  into v_customer_id, v_photographer_id, v_status
  from public.bookings b
  where b.id = p_booking_id;

  if v_customer_id is null then
    raise exception 'Booking not found';
  end if;

  -- Ensure caller is either the customer or the photographer
  if v_customer_id != v_user_id and not exists (
    select 1 from public.photographer_profiles pp
    where pp.id = v_photographer_id and pp.user_id = v_user_id
  ) then
    raise exception 'Access denied to booking contact information';
  end if;

  -- Ensure booking is in confirmed or completed state
  if v_status not in ('confirmed', 'completed') then
    raise exception 'Contact details are restricted until booking payment is confirmed';
  end if;

  return query
    select pd.phone, pd.email
    from public.photographer_private_details pd
    where pd.photographer_id = v_photographer_id;
end;
$$;

revoke all on function public.get_booking_photographer_contact from public, anon, authenticated;
grant execute on function public.get_booking_photographer_contact to authenticated;

-- ==========================================
-- 5. IDEMPOTENT PAYMENT VERIFICATION & LEDGER (SERVER-SIDE / PRIVATE SCHEMA)
-- ==========================================

create or replace function private.process_payment_success(
  p_booking_id uuid,
  p_provider_order_id text,
  p_provider_payment_id text,
  p_amount_paise integer
) returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_booking record;
  v_existing_payment record;
  v_clean_order_id text := trim(coalesce(p_provider_order_id, ''));
  v_clean_payment_id text := trim(coalesce(p_provider_payment_id, ''));
begin
  if v_clean_order_id = '' or v_clean_payment_id = '' then
    raise exception 'Provider order ID and payment ID are required';
  end if;

  -- Lock booking row to prevent race conditions during payment completion
  select * into v_booking
  from public.bookings
  where id = p_booking_id
  for update;

  if v_booking.id is null then
    raise exception 'Booking not found';
  end if;

  if v_booking.total_amount_paise != p_amount_paise then
    raise exception 'Payment amount mismatch: expected %, got %',
      v_booking.total_amount_paise, p_amount_paise;
  end if;

  -- Check existing payment for order ID or payment ID match
  select * into v_existing_payment
  from public.payments
  where provider_order_id = v_clean_order_id
     or provider_payment_id = v_clean_payment_id;

  if v_existing_payment.id is not null then
    -- Verify the order belongs to this exact booking
    if v_existing_payment.booking_id != p_booking_id then
      raise exception 'Provider order ID % belongs to a different booking', v_clean_order_id;
    end if;

    if v_existing_payment.status = 'captured' then
      -- Idempotent retry: verify payment ID matches
      if v_existing_payment.provider_payment_id = v_clean_payment_id then
        return;
      else
        raise exception 'Conflicting payment ID % for order %', v_clean_payment_id, v_clean_order_id;
      end if;
    end if;
  end if;

  -- Handle captured payment for cancelled or ineligible bookings (Refund Reconciliation)
  if v_booking.status in ('cancelled', 'rejected') then
    insert into public.payments (
      booking_id,
      provider,
      provider_order_id,
      provider_payment_id,
      amount_paise,
      status,
      verified_at
    )
    values (
      p_booking_id,
      'razorpay',
      v_clean_order_id,
      v_clean_payment_id,
      p_amount_paise,
      'captured',
      now()
    )
    on conflict (provider_order_id) do update set
      provider_payment_id = excluded.provider_payment_id,
      status = 'captured',
      verified_at = now();

    raise notice 'Payment captured for % booking %. Recorded for refund reconciliation.',
      v_booking.status, p_booking_id;
    return;
  end if;

  if v_booking.status not in ('requested', 'accepted', 'awaiting_payment', 'confirmed') then
    raise exception 'Booking status % cannot transition to confirmed', v_booking.status;
  end if;

  -- Insert or update payment entry
  insert into public.payments (
    booking_id,
    provider,
    provider_order_id,
    provider_payment_id,
    amount_paise,
    status,
    verified_at
  )
  values (
    p_booking_id,
    'razorpay',
    v_clean_order_id,
    v_clean_payment_id,
    p_amount_paise,
    'captured',
    now()
  )
  on conflict (provider_order_id) do update set
    provider_payment_id = excluded.provider_payment_id,
    status = 'captured',
    verified_at = now();

  -- Advance booking status to confirmed
  update public.bookings
  set status = 'confirmed', updated_at = now()
  where id = p_booking_id;

  -- Post to commission ledger (idempotent)
  insert into public.commission_ledger (booking_id, amount_paise)
  values (p_booking_id, v_booking.commission_paise)
  on conflict (booking_id) do nothing;

  -- Post to payouts ledger for photographer (idempotent)
  insert into public.payouts (
    booking_id,
    photographer_id,
    amount_paise,
    status
  )
  values (
    p_booking_id,
    v_booking.photographer_id,
    v_booking.photographer_fee_paise,
    'pending'
  )
  on conflict (booking_id) do nothing;
end;
$$;

-- Keep private.process_payment_success completely inaccessible to public/authenticated users.
revoke all on function private.process_payment_success from public, anon, authenticated;
