begin;
insert into auth.users (id) values
  ('00000000-0000-0000-0000-000000000011'),
  ('00000000-0000-0000-0000-000000000012');

do $$
begin
  if has_table_privilege('anon', 'public.game_creature_instances', 'SELECT')
     or has_table_privilege('authenticated', 'public.game_wallets', 'UPDATE')
     or has_table_privilege('authenticated', 'public.game_expeditions', 'INSERT')
     or has_function_privilege('anon', 'public.claim_game_starter(text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.claim_game_expedition(uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.get_game_status()', 'EXECUTE') then
    raise exception 'game privileges are too broad';
  end if;
end;
$$;

set role authenticated;
select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000011', false);

do $$
declare
  v_starter jsonb;
  v_expedition jsonb;
  v_status jsonb;
begin
  v_starter := public.claim_game_starter('pine_fox');
  if v_starter->>'speciesId' <> 'pine_fox'
     or (v_starter->>'alreadyClaimed')::boolean then
    raise exception 'first starter claim failed';
  end if;
  v_starter := public.claim_game_starter('wave_otter');
  if v_starter->>'speciesId' <> 'pine_fox'
     or not (v_starter->>'alreadyClaimed')::boolean
     or (select count(*) from public.game_creature_instances) <> 1 then
    raise exception 'second starter claim minted another creature';
  end if;
  perform public.set_game_squad_slot(
    (v_starter->>'creatureId')::uuid, 5::smallint);
  if (select count(*) from public.game_squad_slots) <> 1
     or (select slot from public.game_squad_slots) <> 5 then
    raise exception 'squad move failed';
  end if;
  v_expedition := public.start_game_expedition('pine_forest');
  if (v_expedition->>'rewardShards')::integer <> 1
     or (v_expedition->>'alreadyStarted')::boolean then
    raise exception 'first expedition failed';
  end if;
  v_status := public.get_game_status();
  if (v_status->>'todayStarts')::integer <> 1
     or (v_status->>'serverNow')::timestamptz is null then
    raise exception 'server game status was incorrect';
  end if;
  if (public.start_game_expedition('pine_forest')->>'expeditionId')
      <> v_expedition->>'expeditionId' then
    raise exception 'duplicate start created another expedition';
  end if;
  begin
    perform public.claim_game_expedition(
      (v_expedition->>'expeditionId')::uuid);
    raise exception 'early claim was accepted';
  exception when sqlstate '22023' then
    null;
  end;
  if (select draw_shards from public.game_wallets) <> 0 then
    raise exception 'early claim granted a reward';
  end if;
end;
$$;

reset role;
update public.game_expeditions
  set id = '10000000-0000-0000-0000-000000000001',
      started_at = now() - interval '11 minutes',
      ready_at = now() - interval '1 minute'
  where user_id = '00000000-0000-0000-0000-000000000011';

set role authenticated;
select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000011', false);
do $$
declare
  v_id uuid;
  v_first jsonb;
  v_second jsonb;
begin
  select id into v_id from public.game_expeditions;
  v_first := public.claim_game_expedition(v_id);
  v_second := public.claim_game_expedition(v_id);
  if (v_first->>'awardedShards')::integer <> 1
     or (v_second->>'awardedShards')::integer <> 0
     or (select draw_shards from public.game_wallets) <> 1 then
    raise exception 'expedition reward was not idempotent';
  end if;
end;
$$;

reset role;
insert into public.game_expeditions
  (user_id, region_id, started_at, ready_at, claimed_at, reward_shards)
select '00000000-0000-0000-0000-000000000011', 'pine_forest',
  now(), now() + interval '1 minute', now() + interval '2 minutes', 1
from generate_series(1, 3);
set role authenticated;
select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000011', false);
do $$
begin
  begin
    perform public.start_game_expedition('pine_forest');
    raise exception 'daily expedition limit was ignored';
  exception when sqlstate '22023' then
    null;
  end;
end;
$$;

reset role;
update public.game_expeditions
  set started_at =
    date_trunc('day', now() at time zone 'Asia/Seoul')
      at time zone 'Asia/Seoul' - interval '1 minute'
  where user_id = '00000000-0000-0000-0000-000000000011';
set role authenticated;
select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000011', false);
do $$
declare
  v_next jsonb;
begin
  if (public.get_game_status()->>'todayStarts')::integer <> 0 then
    raise exception 'previous KST day counted in server status';
  end if;
  v_next := public.start_game_expedition('pine_forest');
  if (v_next->>'alreadyStarted')::boolean is not false then
    raise exception 'previous KST day still counted toward the daily limit';
  end if;
  if (public.get_game_status()->>'todayStarts')::integer <> 1 then
    raise exception 'new KST day start missing from server status';
  end if;
end;
$$;

select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000012', false);
do $$
declare
begin
  if (select count(*) from public.game_creature_instances) <> 0
     or (select count(*) from public.game_squad_slots) <> 0
     or (select count(*) from public.game_expeditions) <> 0
     or (select count(*) from public.game_wallets) <> 0 then
    raise exception 'another user can read game data';
  end if;
  begin
    perform public.claim_game_expedition(
      '10000000-0000-0000-0000-000000000001');
    raise exception 'foreign expedition claim was accepted';
  exception when sqlstate '22023' then
    null;
  end;
  perform public.claim_game_starter('star_crow');
  if (select count(*) from public.game_creature_instances) <> 1 then
    raise exception 'second user could not claim their own starter';
  end if;
end;
$$;
rollback;
