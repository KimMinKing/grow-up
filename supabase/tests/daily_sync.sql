begin;
insert into auth.users (id) values
  ('00000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-000000000002');

do $$
begin
  if has_table_privilege('authenticated', 'public.user_daily_snapshots', 'INSERT')
     or has_table_privilege('authenticated', 'public.user_daily_snapshots', 'UPDATE')
     or has_table_privilege('anon', 'public.user_daily_snapshots', 'SELECT')
     or has_function_privilege('anon',
       'public.put_daily_snapshot(jsonb,bigint)', 'EXECUTE') then
    raise exception 'daily snapshot privileges are too broad';
  end if;
end;
$$;

set role authenticated;
select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000001', false);

do $$
declare
  v_first jsonb := '{"version":1,"tasks":[{"id":"task-1","title":"test","createdDay":"2026-11-01","completedDay":null}],"notes":[]}';
  v_deleted jsonb := '{"version":1,"tasks":[],"notes":[]}';
begin
  if public.put_daily_snapshot(v_first, 0) <> 1 then
    raise exception 'first upload failed';
  end if;
  if public.put_daily_snapshot(v_first, 0) is not null then
    raise exception 'duplicate create replaced the snapshot';
  end if;
  if public.put_daily_snapshot(v_deleted, 1) <> 2 then
    raise exception 'deletion snapshot did not advance';
  end if;
  if public.put_daily_snapshot(v_first, 1) is not null then
    raise exception 'stale revision resurrected a deleted task';
  end if;
  if (select snapshot->'tasks' from public.user_daily_snapshots) <> '[]'::jsonb then
    raise exception 'deleted task reappeared';
  end if;
end;
$$;

do $$
declare
  v_bad jsonb;
begin
  foreach v_bad in array array[
    '{"version":"1","tasks":[],"notes":[]}'::jsonb,
    '{"version":1,"tasks":{},"notes":[]}'::jsonb,
    '{"version":1,"tasks":[],"notes":{}}'::jsonb
  ] loop
    begin
      perform public.put_daily_snapshot(v_bad, 0);
      raise exception 'invalid snapshot was accepted';
    exception when sqlstate '22023' then
      null;
    end;
  end loop;
end;
$$;

select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000002', false);
do $$
begin
  if (select count(*) from public.user_daily_snapshots) <> 0 then
    raise exception 'another user can read daily data';
  end if;
  if public.put_daily_snapshot('{"version":1,"tasks":[],"notes":[]}', 0) <> 1 then
    raise exception 'other user could not create their own snapshot';
  end if;
end;
$$;
rollback;
