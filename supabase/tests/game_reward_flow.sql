-- Full path from three server expeditions to one free draw.
-- Time is advanced only inside this rolled-back test transaction.
begin;
insert into auth.users (id) values
  ('00000000-0000-0000-0000-000000000031');

set role authenticated;
select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000031', false);
select public.claim_game_starter('pine_fox');

select public.start_game_expedition('pine_forest');
reset role;
update public.game_expeditions
  set started_at = now() - interval '11 minutes',
      ready_at = now() - interval '1 minute'
  where user_id = '00000000-0000-0000-0000-000000000031'
    and claimed_at is null;
set role authenticated;
select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000031', false);
select public.claim_game_expedition(
  (select id from public.game_expeditions where claimed_at is null));

select public.start_game_expedition('pine_forest');
reset role;
update public.game_expeditions
  set started_at = now() - interval '11 minutes',
      ready_at = now() - interval '1 minute'
  where user_id = '00000000-0000-0000-0000-000000000031'
    and claimed_at is null;
set role authenticated;
select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000031', false);
select public.claim_game_expedition(
  (select id from public.game_expeditions where claimed_at is null));

select public.start_game_expedition('pine_forest');
reset role;
update public.game_expeditions
  set started_at = now() - interval '11 minutes',
      ready_at = now() - interval '1 minute'
  where user_id = '00000000-0000-0000-0000-000000000031'
    and claimed_at is null;
set role authenticated;
select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000031', false);
select public.claim_game_expedition(
  (select id from public.game_expeditions where claimed_at is null));

do $$
declare
  v_first jsonb;
  v_retry jsonb;
begin
  if (select count(*) from public.game_expeditions
      where claimed_at is not null) <> 3
     or (select draw_shards from public.game_wallets) <> 3 then
    raise exception 'three expeditions did not earn three shards';
  end if;

  v_first := public.draw_game_creature(
    '30000000-0000-0000-0000-000000000001');
  if (v_first->>'guaranteed')::boolean is not true
     or v_first->>'speciesId' = 'pine_fox'
     or (v_first->>'remainingShards')::integer <> 0
     or (select count(*) from public.game_creature_instances) <> 2 then
    raise exception 'first draw did not grant an unseen creature';
  end if;

  v_retry := public.draw_game_creature(
    '30000000-0000-0000-0000-000000000001');
  if v_retry->>'creatureId' <> v_first->>'creatureId'
     or (v_retry->>'alreadyDrawn')::boolean is not true
     or (select count(*) from public.game_draw_requests) <> 1
     or (select draw_shards from public.game_wallets) <> 0 then
    raise exception 'draw retry changed the result or spent shards twice';
  end if;

  begin
    perform public.draw_game_creature(
      '30000000-0000-0000-0000-000000000002');
    raise exception 'draw without shards was accepted';
  exception when sqlstate '22023' then
    null;
  end;
end;
$$;
rollback;
