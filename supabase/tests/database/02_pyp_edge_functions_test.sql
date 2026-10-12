-- PYP Stage 2 Edge Functions & Webhook Deduplication Test Suite
begin;
select plan(6);

-- TEST 1: processed_webhook_events table RLS blocks client direct access
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}', true);

select throws_like(
  'select count(*) from public.processed_webhook_events',
  '%permission denied%',
  'Test 1: Authenticated user cannot query processed_webhook_events'
);

select throws_like(
  'insert into public.processed_webhook_events (event_id, event_type) values (''evt_123'', ''payment.captured'')',
  '%permission denied%',
  'Test 2: Authenticated user cannot insert into processed_webhook_events'
);

-- TEST 3: Superuser / Service Role can insert and deduplicate webhook events
reset role;

insert into public.processed_webhook_events (event_id, event_type)
values ('evt_test_001', 'payment.captured');

select is(
  (select count(*)::integer from public.processed_webhook_events where event_id = 'evt_test_001'),
  1,
  'Test 3: Service role can record webhook event'
);

-- TEST 4: Duplicate event insertion ignores conflict cleanly
insert into public.processed_webhook_events (event_id, event_type)
values ('evt_test_001', 'payment.captured')
on conflict (event_id) do nothing;

select is(
  (select count(*)::integer from public.processed_webhook_events where event_id = 'evt_test_001'),
  1,
  'Test 4: Duplicate webhook event insertion is deduplicated'
);

-- TEST 5: Verify payments table default provider is razorpay
select is(
  (select (column_default like '%razorpay%') from information_schema.columns where table_name = 'payments' and column_name = 'provider'),
  true,
  'Test 5: Payments default provider is razorpay'
);

-- TEST 6: Verify processed_webhook_events primary key on event_id
select is(
  (select count(*)::integer from information_schema.table_constraints where table_name = 'processed_webhook_events' and constraint_type = 'PRIMARY KEY'),
  1,
  'Test 6: processed_webhook_events has primary key constraint'
);

select * from finish();
rollback;
