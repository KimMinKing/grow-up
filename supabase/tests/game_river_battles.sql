begin;

insert into auth.users (id) values
  ('00000000-0000-0000-0000-000000000061'),
  ('00000000-0000-0000-0000-000000000062');

set role authenticated;
select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000061', false);
select public.claim_game_starter('pine_fox');
select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000062', false);
select public.claim_game_starter('star_crow');
do $$
begin
  begin
    perform public.begin_game_forest_battle(
      '60000000-0000-0000-0000-000000000021', 'river_mist_entry');
    raise exception 'other account bypassed forest prerequisite';
  exception when sqlstate '22023' then
    if sqlerrm = 'other account bypassed forest prerequisite' then raise; end if;
  end;
end;
$$;
reset role;

set role service_role;
insert into public.game_verified_battles
  (battle_ref, user_id, stage_id, won, stars) values
  ('60000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000061', 'forest_moss_gate', true, 3),
  ('60000000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-000000000061', 'forest_firefly_path', true, 3),
  ('60000000-0000-0000-0000-000000000003',
   '00000000-0000-0000-0000-000000000061', 'forest_dawn_lookout', true, 2);
select public.award_verified_game_stage_first_clear(
  '00000000-0000-0000-0000-000000000061', 'forest_moss_gate',
  '60000000-0000-0000-0000-000000000001', 3::smallint);
select public.award_verified_game_stage_first_clear(
  '00000000-0000-0000-0000-000000000061', 'forest_firefly_path',
  '60000000-0000-0000-0000-000000000002', 3::smallint);
select public.award_verified_game_stage_first_clear(
  '00000000-0000-0000-0000-000000000061', 'forest_dawn_lookout',
  '60000000-0000-0000-0000-000000000003', 2::smallint);
reset role;

update public.game_wallets set battle_passes = 10
  where user_id = '00000000-0000-0000-0000-000000000061';

set role authenticated;
select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000061', false);
do $$
begin
  begin
    perform public.begin_game_forest_battle(
      '60000000-0000-0000-0000-000000000012', 'river_shallow_crossing');
    raise exception 'crossing bypassed river entry';
  exception when sqlstate '22023' then
    if sqlerrm = 'crossing bypassed river entry' then raise; end if;
  end;
end;
$$;
select public.begin_game_forest_battle(
  '60000000-0000-0000-0000-000000000011', 'river_mist_entry');
reset role;

set role service_role;
select public.finish_game_forest_battle(
  '60000000-0000-0000-0000-000000000011', true, 2::smallint, 6::smallint);
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000061', false);
do $$
begin
  begin
    perform public.begin_game_forest_battle(
      '60000000-0000-0000-0000-000000000013', 'river_moon_ferry');
    raise exception 'ferry bypassed crossing';
  exception when sqlstate '22023' then
    if sqlerrm = 'ferry bypassed crossing' then raise; end if;
  end;
end;
$$;
select public.begin_game_forest_battle(
  '60000000-0000-0000-0000-000000000012', 'river_shallow_crossing');
reset role;

set role service_role;
do $$
declare
  v_result jsonb;
begin
  v_result := public.finish_game_forest_battle(
    '60000000-0000-0000-0000-000000000012', true, 2::smallint, 7::smallint);
  if v_result->>'companionSpeciesId' <> 'pebble_newt' or
      (v_result->>'firstClearShards')::integer <> 0 or
      (v_result->>'experienceAwarded')::integer <> 3 then
    raise exception 'crossing first victory reward was wrong';
  end if;
end;
$$;
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000061', false);
do $$
begin
  if (select companion_species_id from public.game_battle_attempts
      where request_id = '60000000-0000-0000-0000-000000000012')
      is distinct from 'pebble_newt' then
    raise exception 'crossing retry lost its companion';
  end if;
end;
$$;
select public.begin_game_forest_battle(
  '60000000-0000-0000-0000-000000000013', 'river_moon_ferry');
reset role;
set role service_role;
select public.finish_game_forest_battle(
  '60000000-0000-0000-0000-000000000013', true, 1::smallint, 9::smallint);
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000061', false);
select public.begin_game_forest_battle(
  '60000000-0000-0000-0000-000000000014', 'river_shallow_crossing');
reset role;
set role service_role;
do $$
declare
  v_result jsonb;
begin
  v_result := public.finish_game_forest_battle(
    '60000000-0000-0000-0000-000000000014', true, 3::smallint, 5::smallint);
  if v_result->>'companionSpeciesId' is not null or
      (v_result->>'firstClearShards')::integer <> 0 then
    raise exception 'crossing retry paid a second companion';
  end if;
  v_result := public.finish_game_forest_battle(
    '60000000-0000-0000-0000-000000000014', true, 3::smallint, 5::smallint);
  if v_result->>'alreadyResolved' <> 'true' then
    raise exception 'resolved river battle was not idempotent';
  end if;
end;
$$;
reset role;

do $$
declare
  v_user uuid := '00000000-0000-0000-0000-000000000061';
begin
  if (select companion_species_id from public.game_battle_attempts
      where request_id = '60000000-0000-0000-0000-000000000014')
      is not null then
    raise exception 'repeated crossing recorded a second companion';
  end if;
  if (select count(*) from public.game_stage_first_clears
       where user_id = v_user) <> 6 or
     (select count(*) from public.game_battle_attempts
       where user_id = v_user and status = 'resolved') <> 4 or
     (select count(*) from public.game_creature_instances
       where user_id = v_user and species_id = 'pebble_newt'
         and source = 'battle' and level = 3) <> 1 or
     (select draw_shards from public.game_wallets
       where user_id = v_user) <> 4 or
     (select battle_passes from public.game_wallets
       where user_id = v_user) <> 6 or
     (select count(*) from public.game_stage_first_clears
       where user_id = v_user and stage_id like 'river_%'
         and awarded_shards = 0) <> 3 then
    raise exception 'river battle ledger or first-clear rewards are wrong';
  end if;
end;
$$;

set role authenticated;
select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000062', false);
do $$
begin
  if (select count(*) from public.game_battle_attempts) <> 0 or
     (select count(*) from public.game_stage_first_clears) <> 0 or
     pg_catalog.jsonb_array_length(
       public.get_game_stage_reward_status()->'first_clears') <> 0 then
    raise exception 'river account records leaked';
  end if;
end;
$$;
reset role;

-- A full collection still records the river clear without minting a 21st creature.
insert into auth.users (id) values
  ('00000000-0000-0000-0000-000000000063');
set role authenticated;
select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000063', false);
select public.claim_game_starter('wave_otter');
reset role;
set role service_role;
insert into public.game_verified_battles
  (battle_ref, user_id, stage_id, won, stars) values
  ('60000000-0000-0000-0000-000000000031',
   '00000000-0000-0000-0000-000000000063', 'forest_moss_gate', true, 3),
  ('60000000-0000-0000-0000-000000000032',
   '00000000-0000-0000-0000-000000000063', 'forest_firefly_path', true, 3),
  ('60000000-0000-0000-0000-000000000033',
   '00000000-0000-0000-0000-000000000063', 'forest_dawn_lookout', true, 3);
select public.award_verified_game_stage_first_clear(
  '00000000-0000-0000-0000-000000000063', 'forest_moss_gate',
  '60000000-0000-0000-0000-000000000031', 3::smallint);
select public.award_verified_game_stage_first_clear(
  '00000000-0000-0000-0000-000000000063', 'forest_firefly_path',
  '60000000-0000-0000-0000-000000000032', 3::smallint);
select public.award_verified_game_stage_first_clear(
  '00000000-0000-0000-0000-000000000063', 'forest_dawn_lookout',
  '60000000-0000-0000-0000-000000000033', 3::smallint);
reset role;
insert into public.game_creature_instances (user_id, species_id, source)
  select '00000000-0000-0000-0000-000000000063', 'pine_fox', 'draw'
    from generate_series(1, 19);
update public.game_wallets set battle_passes = 2
  where user_id = '00000000-0000-0000-0000-000000000063';

set role authenticated;
select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000063', false);
select public.begin_game_forest_battle(
  '60000000-0000-0000-0000-000000000034', 'river_mist_entry');
reset role;
set role service_role;
select public.finish_game_forest_battle(
  '60000000-0000-0000-0000-000000000034', true, 2::smallint, 6::smallint);
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000063', false);
select public.begin_game_forest_battle(
  '60000000-0000-0000-0000-000000000035', 'river_shallow_crossing');
reset role;
set role service_role;
do $$
declare
  v_result jsonb;
begin
  v_result := public.finish_game_forest_battle(
    '60000000-0000-0000-0000-000000000035', true, 2::smallint, 7::smallint);
  if v_result->>'companionSpeciesId' is not null then
    raise exception 'full collection received a companion';
  end if;
end;
$$;
reset role;
do $$
declare
  v_user uuid := '00000000-0000-0000-0000-000000000063';
begin
  if (select companion_species_id from public.game_battle_attempts
      where request_id = '60000000-0000-0000-0000-000000000035')
      is not null then
    raise exception 'full collection retry recorded a companion';
  end if;
  if (select count(*) from public.game_creature_instances
       where user_id = v_user) <> 20 or
     (select count(*) from public.game_stage_first_clears
       where user_id = v_user and stage_id = 'river_shallow_crossing'
         and badge_id = 'river_crossing' and awarded_shards = 0) <> 1 or
     (select battle_passes from public.game_wallets
       where user_id = v_user) <> 0 then
    raise exception 'full collection river reward was wrong';
  end if;
end;
$$;

rollback;
