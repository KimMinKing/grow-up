begin;
insert into auth.users (id) values
  ('00000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-000000000002');

do $$
begin
  if has_table_privilege('authenticated', 'public.user_goal_snapshots', 'INSERT')
     or has_table_privilege('authenticated', 'public.user_goal_snapshots', 'UPDATE')
     or has_table_privilege('anon', 'public.user_goal_snapshots', 'SELECT')
     or has_function_privilege('anon',
       'public.put_goal_snapshot(text,jsonb,bigint)', 'EXECUTE') then
    raise exception 'goal snapshot privileges are too broad';
  end if;
end;
$$;

set role authenticated;
select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000001', false);

do $$
declare
  v_snapshot jsonb := '{"id":"goal-1","completions":{},"restDays":[],"milestones":[]}';
begin
  if public.put_goal_snapshot('goal-1', v_snapshot, 0) <> 1 then
    raise exception 'first upload failed';
  end if;
  if public.put_goal_snapshot('goal-1', v_snapshot, 0) is not null then
    raise exception 'duplicate create replaced a goal';
  end if;
  if public.put_goal_snapshot('goal-1', v_snapshot, 1) <> 2 then
    raise exception 'matching revision did not advance';
  end if;
  if public.put_goal_snapshot('goal-1', v_snapshot, 1) is not null then
    raise exception 'stale revision replaced a goal';
  end if;
end;
$$;

select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000002', false);
do $$
begin
  if (select count(*) from public.user_goal_snapshots) <> 0 then
    raise exception 'another user can read goal data';
  end if;
  if public.put_goal_snapshot('goal-1',
    '{"id":"goal-1","completions":{},"restDays":[],"milestones":[]}', 0) <> 1 then
    raise exception 'other user could not create their own goal';
  end if;
end;
$$;

rollback;
