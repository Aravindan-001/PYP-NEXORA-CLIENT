-- PYP Storage Security Hardening & Behavioral Authorization Test Suite
begin;
select plan(11);

-- Seed auth users:
-- User 1 (dddd...): Regular Customer (no photographer role)
-- User 2 (eeee...): Photographer A (has photographer role)
-- User 3 (ffff...): Photographer B (has photographer role)
insert into auth.users (id, email) values ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'customer_storage@test.com');
insert into auth.users (id, email) values ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'photographer_a@test.com');
insert into auth.users (id, email) values ('ffffffff-ffff-ffff-ffff-ffffffffffff', 'photographer_b@test.com');

-- Assign photographer roles in user_roles
insert into public.user_roles (user_id, role) values ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'photographer');
insert into public.user_roles (user_id, role) values ('ffffffff-ffff-ffff-ffff-ffffffffffff', 'photographer');

-- ============================================================================
-- 1. INSERT TESTS
-- ============================================================================

-- TEST 1: Regular customer CANNOT upload file to portfolio_images bucket
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "dddddddd-dddd-dddd-dddd-dddddddddddd", "role": "authenticated"}', true);

select throws_like(
  'insert into storage.objects (id, bucket_id, name, owner, metadata) values (gen_random_uuid(), ''portfolio_images'', ''dddddddd-dddd-dddd-dddd-dddddddddddd/cust_photo.jpg'', ''dddddddd-dddd-dddd-dddd-dddddddddddd'', ''{"mimetype": "image/jpeg"}'')',
  '%violates row-level security policy%',
  'Test 1: Customer without photographer role is blocked from uploading to portfolio_images'
);

-- TEST 2: Photographer A CAN upload file to their own folder in portfolio_images
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee", "role": "authenticated"}', true);

insert into storage.objects (
  id, bucket_id, name, owner, metadata
) values (
  '11111111-1111-1111-1111-111111111111'::uuid,
  'portfolio_images',
  'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee/photo1.jpg',
  'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
  '{"mimetype": "image/jpeg", "size": 2048}'
);

select is(
  (select count(*)::integer from storage.objects where name = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee/photo1.jpg'),
  1,
  'Test 2: Photographer A successfully uploads file to their own folder'
);

-- TEST 3: Photographer A CANNOT upload file into Photographer B''s folder
select throws_like(
  'insert into storage.objects (id, bucket_id, name, owner, metadata) values (gen_random_uuid(), ''portfolio_images'', ''ffffffff-ffff-ffff-ffff-ffffffffffff/cross_upload.jpg'', ''eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'', ''{"mimetype": "image/jpeg"}'')',
  '%violates row-level security policy%',
  'Test 3: Photographer A blocked from uploading into Photographer B folder'
);

-- ============================================================================
-- 2. UPDATE TESTS
-- ============================================================================

-- TEST 4: Regular customer CANNOT update Photographer A''s object
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "dddddddd-dddd-dddd-dddd-dddddddddddd", "role": "authenticated"}', true);

update storage.objects
set metadata = '{"mimetype": "image/jpeg", "size": 9999}'
where name = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee/photo1.jpg';

select is(
  (select (metadata->>'size')::integer from storage.objects where name = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee/photo1.jpg'),
  2048,
  'Test 4: Customer update attempt filtered by RLS (metadata unchanged)'
);

-- TEST 5: Photographer B CANNOT update Photographer A''s object
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "ffffffff-ffff-ffff-ffff-ffffffffffff", "role": "authenticated"}', true);

update storage.objects
set metadata = '{"mimetype": "image/jpeg", "size": 8888}'
where name = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee/photo1.jpg';

select is(
  (select (metadata->>'size')::integer from storage.objects where name = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee/photo1.jpg'),
  2048,
  'Test 5: Photographer B update attempt filtered by RLS (metadata unchanged)'
);

-- TEST 6: Photographer A CAN update their own object
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee", "role": "authenticated"}', true);

update storage.objects
set metadata = '{"mimetype": "image/jpeg", "size": 3072}'
where name = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee/photo1.jpg';

select is(
  (select (metadata->>'size')::integer from storage.objects where name = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee/photo1.jpg'),
  3072,
  'Test 6: Photographer A successfully updates their own object metadata'
);

-- ============================================================================
-- 3. DELETE BEHAVIORAL TESTS (SIMULATING STORAGE API DELETION SESSION)
-- ============================================================================

-- TEST 7: Customer CANNOT delete Photographer A''s object via Storage API session
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "dddddddd-dddd-dddd-dddd-dddddddddddd", "role": "authenticated"}', true);
select set_config('storage.allow_delete_query', 'true', true);

delete from storage.objects
where name = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee/photo1.jpg';

select is(
  (select count(*)::integer from storage.objects where name = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee/photo1.jpg'),
  1,
  'Test 7: Customer delete blocked by Storage RLS policy (object remains intact)'
);

-- TEST 8: Photographer B CANNOT delete Photographer A''s object via Storage API session
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "ffffffff-ffff-ffff-ffff-ffffffffffff", "role": "authenticated"}', true);
select set_config('storage.allow_delete_query', 'true', true);

delete from storage.objects
where name = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee/photo1.jpg';

select is(
  (select count(*)::integer from storage.objects where name = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee/photo1.jpg'),
  1,
  'Test 8: Photographer B delete blocked by Storage RLS policy (object remains intact)'
);

-- TEST 9: Photographer A CAN delete their own object via Storage API session
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee", "role": "authenticated"}', true);
select set_config('storage.allow_delete_query', 'true', true);

delete from storage.objects
where name = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee/photo1.jpg';

select is(
  (select count(*)::integer from storage.objects where name = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee/photo1.jpg'),
  0,
  'Test 9: Photographer A successfully deletes their own object under Storage RLS policy'
);

-- ============================================================================
-- 4. PUBLIC READ / SPECIFIC OBJECT ACCESS TEST
-- ============================================================================

-- Seed a new specific object for Photographer A to test public read access
insert into storage.objects (
  id, bucket_id, name, owner, metadata
) values (
  '22222222-2222-2222-2222-222222222222'::uuid,
  'portfolio_images',
  'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee/photo_public.jpg',
  'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
  '{"mimetype": "image/jpeg", "size": 4096}'
);

-- TEST 10: Public (anon role) can SELECT specific seeded portfolio object
set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);

select is(
  (
    select count(*)::integer
    from storage.objects
    where id = '22222222-2222-2222-2222-222222222222'::uuid
      and name = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee/photo_public.jpg'
  ),
  1,
  'Test 10: Anonymous public user can read specific seeded portfolio object'
);

-- TEST 11: Verify active storage RLS policies enforce photographer role across INSERT, UPDATE, DELETE
reset role;

select is(
  (
    select count(*)::integer from pg_policies
    where tablename = 'objects'
      and policyname in (
        'Photographers can upload portfolio images to own folder',
        'Photographers can update own portfolio images',
        'Photographers can delete own portfolio images'
      )
  ),
  3,
  'Test 11: All three hardened photographer policies active on storage.objects'
);

select * from finish();
rollback;
