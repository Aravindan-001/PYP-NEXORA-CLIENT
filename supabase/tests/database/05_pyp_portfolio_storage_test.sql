-- PYP Portfolio Storage & RLS Security Test Suite
begin;
select plan(6);

-- Seed auth users
insert into auth.users (id, email) values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'photo_port@test.com');
insert into auth.users (id, email) values ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'hacker_port@test.com');

-- Register photographer with portfolio_urls
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", "role": "authenticated"}', true);

select is(
  (
    select public.register_as_photographer(
      'Portfolio Photo',
      'Bio',
      'Chennai',
      'Wedding',
      250000,
      '9876511111',
      'photo_port@test.com',
      array['http://127.0.0.1:54321/storage/v1/object/public/portfolio_images/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/sample1.jpg']
    ) is not null
  ),
  true,
  'Test 1: Registration with portfolio_urls succeeds'
);

select is(
  (select portfolio_urls[1] from public.photographer_profiles where user_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
  'http://127.0.0.1:54321/storage/v1/object/public/portfolio_images/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/sample1.jpg',
  'Test 2: Portfolio URL is saved in photographer_profiles.portfolio_urls'
);

-- TEST 3: Photographer can insert object under their own user_id folder in storage.objects
insert into storage.objects (
  id, bucket_id, name, owner, metadata
) values (
  gen_random_uuid(),
  'portfolio_images',
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/my_photo.jpg',
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  '{"mimetype": "image/jpeg", "size": 1024}'
);

select is(
  (select count(*)::integer from storage.objects where name = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/my_photo.jpg'),
  1,
  'Test 3: Photographer can insert file into their own folder in portfolio_images bucket'
);

-- TEST 4: Hacker/unauthorized user cannot insert file into another photographer folder
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "cccccccc-cccc-cccc-cccc-cccccccccccc", "role": "authenticated"}', true);

select throws_like(
  'insert into storage.objects (id, bucket_id, name, owner, metadata) values (gen_random_uuid(), ''portfolio_images'', ''bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/hacked.jpg'', ''cccccccc-cccc-cccc-cccc-cccccccccccc'', ''{"mimetype": "image/jpeg"}'')',
  '%violates row-level security policy%',
  'Test 4: Unauthorized user cannot insert file into another photographer folder'
);

-- TEST 5: Unauthorized user cannot delete another photographer file
select is(
  (
    with deleted as (
      delete from storage.objects
      where name = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/my_photo.jpg'
      returning *
    )
    select count(*)::integer from deleted
  ),
  0,
  'Test 5: Unauthorized user deletion returns 0 rows deleted'
);

-- TEST 6: Owner photographer can delete their own portfolio file
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", "role": "authenticated"}', true);

select is(
  (
    with deleted as (
      delete from storage.objects
      where name = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/my_photo.jpg'
      returning *
    )
    select count(*)::integer from deleted
  ),
  1,
  'Test 6: Photographer can delete their own portfolio file'
);

select * from finish();
rollback;
