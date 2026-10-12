-- PYP Complete Role-Based Access Control (RBAC) Security & Policy Suite
begin;
select plan(12);

-- Seed base auth users
insert into auth.users (id, email) values ('10000000-0000-0000-0000-000000000001', 'admin_rbac@test.com');
insert into auth.users (id, email, raw_user_meta_data) values ('10000000-0000-0000-0000-000000000002', 'client_rbac@test.com', '{"full_name": "Client Test", "requested_role": "customer"}'::jsonb);
insert into auth.users (id, email) values ('10000000-0000-0000-0000-000000000003', 'photo_rbac@test.com');

-- TEST 1: Provision Admin safely using private.provision_admin
reset role;
select is(
  (select private.provision_admin('admin_rbac@test.com') is not null),
  true,
  'Test 1: Provisioning admin via private function succeeds'
);

select is(
  (select count(*)::integer from public.user_roles where user_id = '10000000-0000-0000-0000-000000000001' and role = 'admin'),
  1,
  'Test 1b: User has admin role in user_roles'
);

-- TEST 2: Client signup via trigger creates client profile and customer role
select is(
  (select count(*)::integer from public.user_roles where user_id = '10000000-0000-0000-0000-000000000002' and role = 'customer'),
  1,
  'Test 2: Client user granted customer role'
);

-- TEST 3: Attempt to self-assign admin via requested_role metadata strictly fails/ignores admin
insert into auth.users (id, email, raw_user_meta_data)
values ('10000000-0000-0000-0000-000000000004', 'hacker@test.com', '{"full_name": "Hacker", "requested_role": "admin"}'::jsonb);

select is(
  (select count(*)::integer from public.user_roles where user_id = '10000000-0000-0000-0000-000000000004' and role = 'admin'),
  0,
  'Test 3: Self-assigning admin via user metadata is ignored'
);

-- TEST 4: Photographer signup creates pending photographer profile (is_published = false)
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "10000000-0000-0000-0000-000000000003", "role": "authenticated"}', true);

select public.register_as_photographer(
  'Photographer Test',
  'Passionate photographer',
  'Bangalore',
  'Fashion',
  250000,
  '9876543210',
  'photo_rbac@test.com'
);

select is(
  (select is_published from public.photographer_profiles where user_id = '10000000-0000-0000-0000-000000000003'),
  false,
  'Test 4: Photographer profile starts as pending/unpublished'
);

-- TEST 5: Client cannot see unpublished photographer in public marketplace
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "10000000-0000-0000-0000-000000000002", "role": "authenticated"}', true);

select is(
  (select count(*)::integer from public.photographer_profiles where user_id = '10000000-0000-0000-0000-000000000003'),
  0,
  'Test 5: Client cannot query unpublished photographer profile directly'
);

-- TEST 6: Client is denied admin stats RPC
select throws_like(
  'select * from public.admin_get_platform_stats()',
  '%Access denied: Admin role required%',
  'Test 6: Client denied access to admin_get_platform_stats'
);

-- TEST 7: Client is denied admin photographer listing
select throws_like(
  'select * from public.admin_get_all_photographers()',
  '%Access denied: Admin role required%',
  'Test 7: Client denied access to admin_get_all_photographers'
);

-- TEST 8: Admin can retrieve platform statistics
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "10000000-0000-0000-0000-000000000001", "role": "authenticated"}', true);

select is(
  (select count(*)::integer from public.admin_get_platform_stats()),
  1,
  'Test 8: Admin successfully retrieves platform stats'
);

-- TEST 9: Admin can list all photographers including pending ones
select is(
  (select count(*)::integer from public.admin_get_all_photographers()),
  1,
  'Test 9: Admin retrieves pending photographer in all-photographers list'
);

-- TEST 10: Admin approves photographer using admin_manage_photographer_status
select public.admin_manage_photographer_status(
  (select id from public.photographer_profiles where user_id = '10000000-0000-0000-0000-000000000003'),
  'approve'
);

reset role;

select is(
  (select is_published from public.photographer_profiles where user_id = '10000000-0000-0000-0000-000000000003'),
  true,
  'Test 10: Photographer is_published is true after admin approval'
);

-- TEST 11: Now client can see approved photographer in public marketplace
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "10000000-0000-0000-0000-000000000002", "role": "authenticated"}', true);

select is(
  (select count(*)::integer from public.photographer_profiles where user_id = '10000000-0000-0000-0000-000000000003'),
  1,
  'Test 11: Client can query published photographer profile'
);

select * from finish();
rollback;
