begin;

insert into auth.users (id) values
  ('00000000-0000-0000-0000-000000000051'),
  ('00000000-0000-0000-0000-000000000052');

do $$
begin
  if has_function_privilege('anon',
       'public.begin_game_forest_battle(uuid,text)', 'EXECUTE')
     or has_function_privilege('anon',
       'public.finish_game_forest_battle(uuid,boolean,smallint,smallint)',
       'EXECUTE')
     or has_function_privilege('authenticated',
       'public.finish_game_forest_battle(uuid,boolean,smallint,smallint)',
       'EXECUTE')
     or not has_function_privilege('service_role',
       'public.finish_game_forest_battle(uuid,boolean,smallint,smallint)',
       'EXECUTE')
     or has_table_privilege('authenticated',
       'public.game_battle_attempts', 'INSERT')
     or has_table_privilege('authenticated',
       'public.game_battle_attempts', 'UPDATE')
     or has_table_privilege('service_role',
       'public.game_battle_attempts', 'INSERT') then
    raise exception 'client can forge server battle state';
  end if;
end;
$$;

set role authenticated;
select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000051', false);
select public.claim_game_starter('pine_fox');
select public.begin_game_forest_battle(
  '50000000-0000-0000-0000-000000000001', 'forest_moss_gate');

do $$
declare
  v_attempt jsonb;
begin
  v_attempt := public.begin_game_forest_battle(
    '50000000-0000-0000-0000-000000000001', 'forest_moss_gate');
  if v_attempt->>'status' <> 'pending' or
      jsonb_array_length(v_attempt->'squad') <> 5 or
      v_attempt->'squad'->0->>'speciesId' <> 'pine_fox' or
      v_attempt->'squad'->0->>'level' <> '1' or
      v_attempt->'squad'->1 <> 'null'::jsonb then
    raise exception 'battle snapshot or idempotent begin is wrong';
  end if;
  begin
    perform public.begin_game_forest_battle(
      '50000000-0000-0000-0000-000000000002', 'forest_moss_gate');
    raise exception 'second pending battle was accepted';
  exception when sqlstate '22023' then
    if sqlerrm = 'second pending battle was accepted' then raise; end if;
  end;
  begin
    perform public.begin_game_forest_battle(
      '50000000-0000-0000-0000-000000000002', 'forest_firefly_path');
    raise exception 'locked second stage was accepted';
  exception when sqlstate '22023' then
    if sqlerrm = 'locked second stage was accepted' then raise; end if;
  end;
end;
$$;
reset role;

set role service_role;
select public.finish_game_forest_battle(
  '50000000-0000-0000-0000-000000000001', true, 2::smallint, 4::smallint);
reset role;
do $$
declare
  v_retry jsonb;
  v_user uuid := '00000000-0000-0000-0000-000000000051';
begin
  v_retry := public.finish_game_forest_battle(
    '50000000-0000-0000-0000-000000000001', true, 2::smallint, 4::smallint);
  if v_retry->>'alreadyResolved' <> 'true' or
      (select draw_shards from public.game_wallets
        where user_id = v_user) <> 1 or
      (select battle_experience from public.game_creature_instances
        where user_id = v_user and source = 'starter') <> 1 or
      (select count(*) from public.game_creature_instances
        where user_id = v_user and source = 'battle'
          and species_id = 'wave_otter') <> 1 or
      (select companion_species_id from public.game_battle_attempts
        where request_id = '50000000-0000-0000-0000-000000000001')
          is distinct from 'wave_otter' or
      (select count(*) from public.game_verified_battles
        where user_id = v_user) <> 1 then
    raise exception 'battle resolution was duplicated or growth is wrong';
  end if;
  begin
    perform public.finish_game_forest_battle(
      '50000000-0000-0000-0000-000000000001', true, 3::smallint, 4::smallint);
    raise exception 'mismatched retry was accepted';
  exception when sqlstate '22023' then
    if sqlerrm = 'mismatched retry was accepted' then raise; end if;
  end;
end;
$$;

set role authenticated;
select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000051', false);
select public.begin_game_forest_battle(
  '50000000-0000-0000-0000-000000000002', 'forest_firefly_path');
select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000052', false);
select public.claim_game_starter('star_crow');
do $$
begin
  if (select count(*) from public.game_battle_attempts) <> 0 then
    raise exception 'another account can see battle attempts';
  end if;
  begin
    perform public.begin_game_forest_battle(
      '50000000-0000-0000-0000-000000000001', 'forest_moss_gate');
    raise exception 'another account reused battle request';
  exception when sqlstate '22023' then
    if sqlerrm = 'another account reused battle request' then raise; end if;
  end;
end;
$$;
reset role;

rollback;
