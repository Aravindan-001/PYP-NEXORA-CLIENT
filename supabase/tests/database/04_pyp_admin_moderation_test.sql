-- PYP Admin Moderation Security & RPC Test Suite
begin;
select plan(6);

-- Seed auth users
insert into auth.users (id, email) values ('88888888-8888-8888-8888-888888888888', 'admin_mod@test.com');
insert into auth.users (id, email) values ('99999999-9999-9999-9999-999999999999', 'cust_mod@test.com');
insert into auth.users (id, email) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'photo_mod@test.com');

-- Assign admin role to admin_user
insert into public.user_roles (user_id, role) values ('88888888-8888-8888-8888-888888888888', 'admin');

-- Photographer registers (defaults to is_published = false)
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "role": "authenticated"}', true);

select public.register_as_photographer(
  'Pending Photo',
  'Pending Bio',
  'Hyderabad',
  'Portrait',
  180000,
  '9876500000',
  'photo_mod@test.com'
);

-- TEST 1: Non-admin customer is denied listing pending photographers
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "99999999-9999-9999-9999-999999999999", "role": "authenticated"}', true);

select throws_like(
  'select * from public.admin_get_pending_photographers()',
  '%Access denied: Admin role required%',
  'Test 1: Non-admin customer cannot access admin_get_pending_photographers'
);

-- TEST 2: Non-admin customer is denied approving photographers
select throws_like(
  'select public.admin_manage_photographer_status(''aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa''::uuid, ''approve'')',
  '%Access denied: Admin role required%',
  'Test 2: Non-admin customer cannot access admin_manage_photographer_status'
);

-- TEST 3: Admin user can list pending photographers
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "88888888-8888-8888-8888-888888888888", "role": "authenticated"}', true);

select is(
  (select count(*)::integer from public.admin_get_pending_photographers()),
  1,
  'Test 3: Admin user retrieves 1 pending photographer profile'
);

-- TEST 4: Admin user can approve/publish pending photographer using ID from admin_get_pending_photographers
select public.admin_manage_photographer_status(
  (select out_id from public.admin_get_pending_photographers() limit 1),
  'approve'
);

reset role;

select is(
  (select is_published from public.photographer_profiles where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  true,
  'Test 4: Photographer is_published is set to true after admin approval'
);

-- TEST 5: After approval, pending photographer list count drops to 0
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "88888888-8888-8888-8888-888888888888", "role": "authenticated"}', true);

select is(
  (select count(*)::integer from public.admin_get_pending_photographers()),
  0,
  'Test 5: Pending list count is 0 after approval'
);

-- TEST 6: Admin user can unpublish / reject a photographer
select public.admin_manage_photographer_status(
  (select id from public.photographer_profiles where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  'reject'
);

reset role;

select is(
  (select is_published from public.photographer_profiles where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  false,
  'Test 6: Photographer is_published is set to false after admin unpublishing'
);

select * from finish();
rollback;
