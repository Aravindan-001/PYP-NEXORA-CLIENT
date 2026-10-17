-- PYP Notifications Write Security Test Suite
begin;
select plan(19);

-- Apply migration changes locally within test transaction
DROP POLICY IF EXISTS "Authenticated users or triggers can insert notifications" ON public.notifications;
DROP POLICY IF EXISTS "Users can update own notifications" ON public.notifications;
REVOKE ALL ON TABLE public.notifications FROM PUBLIC, anon;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.notifications FROM authenticated;
GRANT SELECT ON TABLE public.notifications TO authenticated;

DROP POLICY IF EXISTS "Users can read own notifications" ON public.notifications;
CREATE POLICY "Users can read own notifications"
  ON public.notifications FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.mark_notifications_read(
  p_notification_id uuid DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthenticated user';
  END IF;

  IF p_notification_id IS NOT NULL THEN
    UPDATE public.notifications
    SET is_read = true
    WHERE id = p_notification_id AND user_id = v_user_id;
  ELSE
    UPDATE public.notifications
    SET is_read = true
    WHERE user_id = v_user_id AND is_read = false;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_notifications_read(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_notifications_read(uuid) TO authenticated;

-- Seed test users
insert into auth.users (id, email) values ('88888888-8888-8888-8888-888888888888', 'notif_user1@test.com') on conflict do nothing;
insert into auth.users (id, email) values ('99999999-9999-9999-9999-999999999999', 'notif_user2@test.com') on conflict do nothing;

-- Seed notifications as superuser/definer
insert into public.notifications (id, user_id, title, message, type, is_read)
values
  ('11111111-1111-1111-1111-111111111111', '88888888-8888-8888-8888-888888888888', 'Notif 1A', 'Message 1A', 'general', false),
  ('11111111-1111-1111-1111-222222222222', '88888888-8888-8888-8888-888888888888', 'Notif 1B', 'Message 1B', 'general', false),
  ('22222222-2222-2222-2222-222222222222', '99999999-9999-9999-9999-999999999999', 'Notif 2',  'Message 2',  'general', false);

-- Switch role to authenticated user 1
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "88888888-8888-8888-8888-888888888888", "role": "authenticated"}', true);

-- TEST 1: Authenticated user cannot directly INSERT notifications
select throws_like(
  'insert into public.notifications (user_id, title, message) values (''88888888-8888-8888-8888-888888888888'', ''Fake'', ''Test'')',
  '%permission denied%',
  'Test 1: Authenticated user cannot directly INSERT notifications'
);

-- TEST 2: Authenticated user cannot directly UPDATE notifications
select throws_like(
  'update public.notifications set title = ''Tampered'' where id = ''11111111-1111-1111-1111-111111111111''',
  '%permission denied%',
  'Test 2: Authenticated user cannot directly UPDATE notifications'
);

-- TEST 3: Authenticated user cannot directly DELETE notifications
select throws_like(
  'delete from public.notifications where id = ''11111111-1111-1111-1111-111111111111''',
  '%permission denied%',
  'Test 3: Authenticated user cannot directly DELETE notifications'
);

-- TEST 4: User 1 can read own notifications
select is(
  (select count(*)::integer from public.notifications where user_id = '88888888-8888-8888-8888-888888888888'),
  2,
  'Test 4: User 1 can read own notifications'
);

-- TEST 5: User 1 cannot read User 2 notifications
select is(
  (select count(*)::integer from public.notifications where user_id = '99999999-9999-9999-9999-999999999999'),
  0,
  'Test 5: User 1 cannot read User 2 notifications'
);

-- TEST 6: mark_notifications_read RPC executes for caller single notification ID
select lives_ok(
  'select public.mark_notifications_read(''11111111-1111-1111-1111-111111111111''::uuid)',
  'Test 6: mark_notifications_read RPC executes for caller notification'
);

-- TEST 7: Verify Notif 1A is now read
select is(
  (select is_read from public.notifications where id = '11111111-1111-1111-1111-111111111111'),
  true,
  'Test 7: Notif 1A updated to is_read = true'
);

-- TEST 8: Verify Notif 1B is still unread
select is(
  (select is_read from public.notifications where id = '11111111-1111-1111-1111-222222222222'),
  false,
  'Test 8: Notif 1B remains is_read = false'
);

-- Switch role to authenticated User 2
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "99999999-9999-9999-9999-999999999999", "role": "authenticated"}', true);

-- TEST 9: User 2 calls mark_notifications_read on User 1''s Notif 1B
select lives_ok(
  'select public.mark_notifications_read(''11111111-1111-1111-1111-222222222222''::uuid)',
  'Test 9: RPC completes without exception for unauthorized ID'
);

-- TEST 10: Reset role to superuser and verify Notif 1B was NOT modified by User 2
reset role;

select is(
  (select is_read from public.notifications where id = '11111111-1111-1111-1111-222222222222'),
  false,
  'Test 10: Notif 1B remains is_read = false after unauthorized attempt'
);

-- Switch back to User 1
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "88888888-8888-8888-8888-888888888888", "role": "authenticated"}', true);

-- TEST 11: User 1 calls mark_notifications_read(NULL)
select lives_ok(
  'select public.mark_notifications_read(NULL)',
  'Test 11: mark_notifications_read(NULL) executes'
);

-- TEST 12: Verify User 1''s remaining unread notification (Notif 1B) is now read
reset role;

select is(
  (select is_read from public.notifications where id = '11111111-1111-1111-1111-222222222222'),
  true,
  'Test 12: Notif 1B marked read by NULL parameter'
);

-- TEST 13: Verify User 2''s notification (Notif 2) was unaffected by User 1''s NULL call
select is(
  (select is_read from public.notifications where id = '22222222-2222-2222-2222-222222222222'),
  false,
  'Test 13: User 2 notification unaffected by User 1 NULL mark-read call'
);

-- TEST 14-18: Anonymous role checks
set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);

select throws_like(
  'select * from public.notifications',
  '%permission denied%',
  'Test 14: Anon cannot SELECT notifications'
);

select throws_like(
  'insert into public.notifications (user_id, title, message) values (''88888888-8888-8888-8888-888888888888'', ''Anon'', ''Test'')',
  '%permission denied%',
  'Test 15: Anon cannot INSERT notifications'
);

select throws_like(
  'update public.notifications set title = ''Anon''',
  '%permission denied%',
  'Test 16: Anon cannot UPDATE notifications'
);

select throws_like(
  'delete from public.notifications',
  '%permission denied%',
  'Test 17: Anon cannot DELETE notifications'
);

select throws_like(
  'select public.mark_notifications_read()',
  '%permission denied%',
  'Test 18: Anon cannot execute mark_notifications_read RPC'
);

-- TEST 19: Server / Definer context can create notifications
reset role;

select lives_ok(
  'insert into public.notifications (user_id, title, message, type) values (''88888888-8888-8888-8888-888888888888'', ''Server Notif'', ''Trusted Insert'', ''system'')',
  'Test 19: Server / Definer context can create notifications'
);

select * from finish();
rollback;
