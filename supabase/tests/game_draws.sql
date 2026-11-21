begin;
insert into auth.users (id) values
  ('00000000-0000-0000-0000-000000000021'),
  ('00000000-0000-0000-0000-000000000022'),
  ('00000000-0000-0000-0000-000000000023');

do $$
begin
  if has_table_privilege('anon', 'public.game_draw_requests', 'SELECT')
     or has_table_privilege('authenticated', 'public.game_draw_requests', 'INSERT')
     or has_function_privilege('anon', 'public.draw_game_creature(uuid)', 'EXECUTE') then
    raise exception 'draw privileges are too broad';
  end if;
end;
$$;

set role authenticated;
select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000021', false);
select public.claim_game_starter('pine_fox');
reset role;
update public.game_wallets set draw_shards = 3
  where user_id = '00000000-0000-0000-0000-000000000021';
set role authenticated;
do $$
declare
  v_first jsonb;
  v_replay jsonb;
begin
  v_first := public.draw_game_creature(
    '20000000-0000-0000-0000-000000000001');
  v_replay := public.draw_game_creature(
    '20000000-0000-0000-0000-000000000001');
  if v_first->>'speciesId' = 'pine_fox'
     or not (v_first->>'guaranteed')::boolean
     or (v_first->>'remainingShards')::integer <> 0
     or v_replay->>'creatureId' <> v_first->>'creatureId'
     or not (v_replay->>'alreadyDrawn')::boolean
     or (select count(*) from public.game_creature_instances) <> 2
     or (select count(*) from public.game_draw_requests) <> 1 then
    raise exception 'first guaranteed draw or replay failed';
  end if;
  begin
    perform public.draw_game_creature(
      '20000000-0000-0000-0000-000000000002');
    raise exception 'draw without shards was accepted';
  exception when sqlstate '22023' then
    null;
  end;
  if (select count(*) from public.game_creature_instances) <> 2 then
    raise exception 'failed draw granted a creature';
  end if;
end;
$$;

select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000022', false);
do $$
begin
  if (select count(*) from public.game_creature_instances) <> 0
     or (select count(*) from public.game_draw_requests) <> 0 then
    raise exception 'another user can read draws';
  end if;
  perform public.claim_game_starter('pine_fox');
end;
$$;
reset role;
insert into public.game_creature_instances (user_id, species_id, source)
select '00000000-0000-0000-0000-000000000022', 'wave_otter', 'draw'
from generate_series(1, 4);
insert into public.game_draw_requests
  (user_id, request_id, creature_id, guaranteed)
select user_id, gen_random_uuid(), id, false
from public.game_creature_instances
where user_id = '00000000-0000-0000-0000-000000000022'
  and source = 'draw';
update public.game_wallets set draw_shards = 3
  where user_id = '00000000-0000-0000-0000-000000000022';
set role authenticated;
do $$
declare
  v_fifth jsonb;
begin
  v_fifth := public.draw_game_creature(
    '20000000-0000-0000-0000-000000000005');
  if v_fifth->>'speciesId' <> 'star_crow'
     or not (v_fifth->>'guaranteed')::boolean
     or (select count(*) from public.game_creature_instances) <> 6 then
    raise exception 'fifth draw did not find undiscovered species';
  end if;
end;
$$;

select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000023', false);
select public.claim_game_starter('pine_fox');
reset role;
insert into public.game_creature_instances (user_id, species_id, source)
select '00000000-0000-0000-0000-000000000023', 'pine_fox', 'draw'
from generate_series(1, 19);
update public.game_wallets set draw_shards = 3
  where user_id = '00000000-0000-0000-0000-000000000023';
set role authenticated;
do $$
begin
  begin
    perform public.draw_game_creature(
      '20000000-0000-0000-0000-000000000020');
    raise exception 'full collection draw was accepted';
  exception when sqlstate '22023' then
    null;
  end;
  if (select draw_shards from public.game_wallets) <> 3
     or (select count(*) from public.game_creature_instances) <> 20 then
    raise exception 'full collection consumed shards';
  end if;
end;
$$;
rollback;
