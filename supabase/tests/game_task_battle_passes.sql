begin;

insert into auth.users (id) values
  ('00000000-0000-0000-0000-000000000061'),
  ('00000000-0000-0000-0000-000000000062');

do $$
begin
  if has_function_privilege('anon',
       'public.claim_game_task_battle_passes()', 'EXECUTE')
     or has_table_privilege('authenticated',
       'public.game_task_battle_grants', 'INSERT')
     or has_table_privilege('authenticated',
       'public.game_wallets', 'UPDATE') then
    raise exception 'client can forge battle passes';
  end if;
end;
$$;

set role authenticated;
select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000061', false);
select public.claim_game_starter('pine_fox');

do $$
begin
  begin
    perform public.claim_game_task_battle_passes();
    raise exception 'unsynced tasks granted passes';
  exception when sqlstate '22023' then
    if sqlerrm = 'unsynced tasks granted passes' then raise; end if;
  end;
end;
$$;

select public.put_daily_snapshot(
  pg_catalog.jsonb_build_object(
    'version', 1, 'notes', '[]'::jsonb,
    'tasks', pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'id', 'task-1',
        'completedDay', (now() at time zone 'Asia/Seoul')::date::text,
        'roadmapLinked', false),
      pg_catalog.jsonb_build_object(
        'id', 'roadmap-1',
        'completedDay', (now() at time zone 'Asia/Seoul')::date::text,
        'roadmapLinked', true))), 0);

do $$
declare
  v_first jsonb;
  v_again jsonb;
begin
  v_first := public.claim_game_task_battle_passes();
  v_again := public.claim_game_task_battle_passes();
  if v_first->>'addedPasses' <> '2' or
      v_first->>'battlePasses' <> '4' or
      v_again->>'addedPasses' <> '0' or
      v_again->>'battlePasses' <> '4' or
      (select count(*) from public.game_task_battle_grants
        where user_id = auth.uid()) <> 1 then
    raise exception 'task completion was credited twice or roadmap task credited';
  end if;
end;
$$;

select public.begin_game_forest_battle(
  '50000000-0000-0000-0000-000000000061', 'forest_moss_gate');
do $$
begin
  perform public.begin_game_forest_battle(
    '50000000-0000-0000-0000-000000000061', 'forest_moss_gate');
  if (select battle_passes from public.game_wallets
      where user_id = auth.uid()) <> 3 then
    raise exception 'idempotent battle charged twice';
  end if;
end;
$$;
reset role;

set role service_role;
select public.finish_game_forest_battle(
  '50000000-0000-0000-0000-000000000061', false,
  0::smallint, 1::smallint);
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000061', false);
select public.begin_game_forest_battle(
  '50000000-0000-0000-0000-000000000062', 'forest_moss_gate');
reset role;
set role service_role;
select public.finish_game_forest_battle(
  '50000000-0000-0000-0000-000000000062', false,
  0::smallint, 1::smallint);
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000061', false);
select public.begin_game_forest_battle(
  '50000000-0000-0000-0000-000000000063', 'forest_moss_gate');
reset role;
set role service_role;
select public.finish_game_forest_battle(
  '50000000-0000-0000-0000-000000000063', false,
  0::smallint, 1::smallint);
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000061', false);
select public.begin_game_forest_battle(
  '50000000-0000-0000-0000-000000000064', 'forest_moss_gate');
reset role;
set role service_role;
select public.finish_game_forest_battle(
  '50000000-0000-0000-0000-000000000064', false,
  0::smallint, 1::smallint);
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000061', false);
do $$
begin
  if (select battle_passes from public.game_wallets
      where user_id = auth.uid()) <> 0 then
    raise exception 'battle passes did not decrement';
  end if;
  begin
    perform public.begin_game_forest_battle(
      '50000000-0000-0000-0000-000000000065', 'forest_moss_gate');
    raise exception 'battle without passes accepted';
  exception when sqlstate '22023' then
    if sqlerrm = 'battle without passes accepted' then raise; end if;
  end;
end;
$$;

select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000062', false);
do $$
begin
  if exists (select 1 from public.game_task_battle_grants) then
    raise exception 'other account grants visible';
  end if;
end;
$$;
reset role;

rollback;
