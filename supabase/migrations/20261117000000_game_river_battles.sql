-- Add river account battles while preserving forest payouts and records.
-- River first-clear badges grant no draw shards.
alter table public.game_creature_instances
  drop constraint game_creature_instances_species_id_check;
alter table public.game_creature_instances
  add constraint game_creature_instances_species_id_check
    check (species_id in ('pine_fox', 'wave_otter', 'star_crow', 'pebble_newt'));

alter table public.game_stage_first_clears
  drop constraint game_stage_first_clears_stage_id_check,
  drop constraint game_stage_first_clears_badge_id_check,
  drop constraint game_stage_first_clears_awarded_shards_check;
alter table public.game_stage_first_clears
  add constraint game_stage_first_clears_stage_id_check
    check (stage_id in ('forest_moss_gate', 'forest_firefly_path', 'forest_dawn_lookout',
        'river_mist_entry', 'river_shallow_crossing', 'river_moon_ferry')),
  add constraint game_stage_first_clears_badge_id_check
    check (badge_id in ('first_footprint', 'forest_lantern', 'forest_dawn',
      'river_entry', 'river_crossing', 'river_ferry')),
  add constraint game_stage_first_clears_awarded_shards_check
    check (awarded_shards between 0 and 2);

alter table public.game_verified_battles
  drop constraint game_verified_battles_stage_id_check;
alter table public.game_verified_battles
  add constraint game_verified_battles_stage_id_check
    check (stage_id in ('forest_moss_gate', 'forest_firefly_path', 'forest_dawn_lookout',
        'river_mist_entry', 'river_shallow_crossing', 'river_moon_ferry'));

alter table public.game_battle_attempts
  drop constraint game_battle_attempts_stage_id_check;
alter table public.game_battle_attempts
  add constraint game_battle_attempts_stage_id_check
    check (stage_id in ('forest_moss_gate', 'forest_firefly_path', 'forest_dawn_lookout',
        'river_mist_entry', 'river_shallow_crossing', 'river_moon_ferry'));

create or replace function public.award_verified_game_stage_first_clear(
  p_user_id uuid, p_stage_id text, p_battle_ref uuid, p_stars smallint)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_existing public.game_stage_first_clears%rowtype;
  v_badge_id text;
  v_shards smallint;
  v_prerequisite text;
  v_wallet integer;
begin
  if p_user_id is null or p_battle_ref is null or
      p_stars is null or p_stars not between 1 and 3 then
    raise exception 'invalid verified battle' using errcode = '22023';
  end if;
  case p_stage_id
    when 'forest_moss_gate' then
      v_badge_id := 'first_footprint';
      v_shards := 1;
    when 'forest_firefly_path' then
      v_badge_id := 'forest_lantern';
      v_shards := 1;
      v_prerequisite := 'forest_moss_gate';
    when 'forest_dawn_lookout' then
      v_badge_id := 'forest_dawn';
      v_shards := 2;
      v_prerequisite := 'forest_firefly_path';
    when 'river_mist_entry' then
      v_badge_id := 'river_entry';
      v_shards := 0;
      v_prerequisite := 'forest_dawn_lookout';
    when 'river_shallow_crossing' then
      v_badge_id := 'river_crossing';
      v_shards := 0;
      v_prerequisite := 'river_mist_entry';
    when 'river_moon_ferry' then
      v_badge_id := 'river_ferry';
      v_shards := 0;
      v_prerequisite := 'river_shallow_crossing';
    else
      raise exception 'unknown stage' using errcode = '22023';
  end case;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('game:' || p_user_id::text));
  select * into v_existing from public.game_stage_first_clears
    where user_id = p_user_id and stage_id = p_stage_id;
  if found then
    select draw_shards into v_wallet from public.game_wallets
      where user_id = p_user_id;
    return pg_catalog.jsonb_build_object(
      'stageId', p_stage_id,
      'badgeId', v_existing.badge_id,
      'awardedShards', 0,
      'totalShards', v_wallet,
      'alreadyGranted', true);
  end if;
  if not exists (select 1 from public.game_creature_instances
      where user_id = p_user_id and source = 'starter') then
    raise exception 'starter required' using errcode = '22023';
  end if;
  if v_prerequisite is not null and not exists (
      select 1 from public.game_stage_first_clears
      where user_id = p_user_id and stage_id = v_prerequisite) then
    raise exception 'previous stage required' using errcode = '22023';
  end if;
  if exists (select 1 from public.game_stage_first_clears
      where user_id = p_user_id and battle_ref = p_battle_ref) then
    raise exception 'battle already used' using errcode = '22023';
  end if;

  insert into public.game_stage_first_clears
    (user_id, stage_id, battle_ref, stars, badge_id, awarded_shards)
    values (p_user_id, p_stage_id, p_battle_ref, p_stars, v_badge_id, v_shards);
  insert into public.game_wallets (user_id, draw_shards)
    values (p_user_id, v_shards)
    on conflict (user_id) do update
    set draw_shards = game_wallets.draw_shards + excluded.draw_shards
    returning draw_shards into v_wallet;
  return pg_catalog.jsonb_build_object(
    'stageId', p_stage_id,
    'badgeId', v_badge_id,
    'awardedShards', v_shards,
    'totalShards', v_wallet,
    'alreadyGranted', false);
end;
$$;

create or replace function public.begin_game_forest_battle(
  p_request_id uuid, p_stage_id text) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_attempt public.game_battle_attempts%rowtype;
  v_snapshot jsonb;
  v_prerequisite text;
  v_expired integer;
begin
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  if p_request_id is null then
    raise exception 'battle request required' using errcode = '22023';
  end if;
  case p_stage_id
    when 'forest_moss_gate' then v_prerequisite := null;
    when 'forest_firefly_path' then v_prerequisite := 'forest_moss_gate';
    when 'forest_dawn_lookout' then v_prerequisite := 'forest_firefly_path';
    when 'river_mist_entry' then v_prerequisite := 'forest_dawn_lookout';
    when 'river_shallow_crossing' then v_prerequisite := 'river_mist_entry';
    when 'river_moon_ferry' then v_prerequisite := 'river_shallow_crossing';
    else raise exception 'unknown stage' using errcode = '22023';
  end case;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('game:' || v_user_id::text));
  select * into v_attempt from public.game_battle_attempts
    where request_id = p_request_id;
  if found then
    if v_attempt.user_id <> v_user_id or v_attempt.stage_id <> p_stage_id then
      raise exception 'battle request already used' using errcode = '22023';
    end if;
    return pg_catalog.jsonb_build_object(
      'requestId', v_attempt.request_id,
      'stageId', v_attempt.stage_id,
      'squad', v_attempt.squad_snapshot,
      'status', v_attempt.status,
      'won', v_attempt.won,
      'stars', v_attempt.stars,
      'turns', v_attempt.turns,
      'experienceAwarded', v_attempt.experience_awarded,
      'firstClearShards', v_attempt.first_clear_shards);
  end if;
  with expired as (
    update public.game_battle_attempts set status = 'expired'
      where user_id = v_user_id and status = 'pending'
        and started_at < now() - interval '5 minutes'
      returning request_id
  ) select count(*) into v_expired from expired;
  if v_expired > 0 then
    update public.game_wallets set
      battle_passes = least(30, battle_passes + v_expired)
      where user_id = v_user_id;
  end if;
  if exists (select 1 from public.game_battle_attempts
      where user_id = v_user_id and status = 'pending') then
    raise exception 'battle already in progress' using errcode = '22023';
  end if;
  if (select count(*) from public.game_battle_attempts
      where user_id = v_user_id and
        started_at >= pg_catalog.date_trunc(
          'day', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul') >= 15 then
    raise exception 'daily battle limit reached' using errcode = '22023';
  end if;
  if v_prerequisite is not null and not exists (
      select 1 from public.game_stage_first_clears
      where user_id = v_user_id and stage_id = v_prerequisite) then
    raise exception 'previous stage required' using errcode = '22023';
  end if;
  select pg_catalog.jsonb_agg(
      case when creature.id is null then 'null'::jsonb else
        pg_catalog.jsonb_build_object(
          'id', creature.id,
          'speciesId', creature.species_id,
          'level', creature.level) end order by slots.slot)
    into v_snapshot
    from pg_catalog.generate_series(1, 5) as slots(slot)
    left join public.game_squad_slots squad
      on squad.user_id = v_user_id and squad.slot = slots.slot
    left join public.game_creature_instances creature
      on creature.user_id = v_user_id and creature.id = squad.creature_id;
  if v_snapshot is null or v_snapshot = '[null,null,null,null,null]'::jsonb then
    raise exception 'squad empty' using errcode = '22023';
  end if;
  update public.game_wallets set battle_passes = battle_passes - 1
    where user_id = v_user_id and battle_passes > 0;
  if not found then
    raise exception 'no battle passes' using errcode = '22023';
  end if;
  insert into public.game_battle_attempts
    (request_id, user_id, stage_id, squad_snapshot)
    values (p_request_id, v_user_id, p_stage_id, v_snapshot);
  return pg_catalog.jsonb_build_object(
    'requestId', p_request_id, 'stageId', p_stage_id,
    'squad', v_snapshot, 'status', 'pending');
end;
$$;

create or replace function public.finish_game_forest_battle(
  p_request_id uuid, p_won boolean, p_stars smallint, p_turns smallint)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_attempt public.game_battle_attempts%rowtype;
  v_reward jsonb;
  v_xp smallint := 0;
  v_daily_wins integer;
  v_first_shards smallint := 0;
  v_companion_species text;
begin
  if p_request_id is null or p_won is null or p_stars is null or
      p_turns is null or p_turns not between 0 and 30 or
      (p_won and (p_stars not between 1 and 3 or p_turns = 0)) or
      (not p_won and p_stars <> 0) then
    raise exception 'invalid battle result' using errcode = '22023';
  end if;
  select * into v_attempt from public.game_battle_attempts
    where request_id = p_request_id;
  if not found then
    raise exception 'battle request not found' using errcode = '22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('game:' || v_attempt.user_id::text));
  select * into v_attempt from public.game_battle_attempts
    where request_id = p_request_id for update;
  if v_attempt.status = 'resolved' then
    if v_attempt.won is distinct from p_won or
        v_attempt.stars is distinct from p_stars or
        v_attempt.turns is distinct from p_turns then
      raise exception 'battle result mismatch' using errcode = '22023';
    end if;
    return pg_catalog.jsonb_build_object(
      'requestId', p_request_id, 'alreadyResolved', true,
      'won', v_attempt.won, 'stars', v_attempt.stars,
      'turns', v_attempt.turns,
      'experienceAwarded', v_attempt.experience_awarded,
      'firstClearShards', v_attempt.first_clear_shards);
  end if;
  if v_attempt.status <> 'pending' then
    raise exception 'battle request expired' using errcode = '22023';
  end if;
  if p_won then
    select count(*) into v_daily_wins from public.game_battle_attempts
      where user_id = v_attempt.user_id and stage_id = v_attempt.stage_id
        and status = 'resolved' and experience_awarded > 0
        and started_at >= pg_catalog.date_trunc(
          'day', v_attempt.started_at at time zone 'Asia/Seoul')
          at time zone 'Asia/Seoul';
    if v_daily_wins < 5 then
      v_xp := case v_attempt.stage_id
        when 'forest_moss_gate' then 1
        when 'forest_firefly_path' then 2
        else 3 end;
    end if;
  end if;
  insert into public.game_verified_battles
    (battle_ref, user_id, stage_id, won, stars)
    values (p_request_id, v_attempt.user_id, v_attempt.stage_id,
      p_won, p_stars);
  if p_won then
    v_reward := public.award_verified_game_stage_first_clear(
      v_attempt.user_id, v_attempt.stage_id, p_request_id, p_stars);
    v_first_shards := (v_reward->>'awardedShards')::smallint;
    if v_first_shards > 0 and v_attempt.stage_id = 'forest_moss_gate'
        and (select count(*) from public.game_creature_instances
          where user_id = v_attempt.user_id) < 20 then
      select case species_id
        when 'pine_fox' then 'wave_otter'
        when 'wave_otter' then 'star_crow'
        else 'pine_fox' end into v_companion_species
        from public.game_creature_instances
        where user_id = v_attempt.user_id and source = 'starter';
      insert into public.game_creature_instances
        (user_id, species_id, source)
        values (v_attempt.user_id, v_companion_species, 'battle');
    end if;
    if not (v_reward->>'alreadyGranted')::boolean and
        v_attempt.stage_id = 'river_shallow_crossing' and
        (select count(*) from public.game_creature_instances
          where user_id = v_attempt.user_id) < 20 then
      v_companion_species := 'pebble_newt';
      insert into public.game_creature_instances
        (user_id, species_id, source, level)
        values (v_attempt.user_id, v_companion_species, 'battle', 3);
    end if;
    if v_xp > 0 then
      update public.game_creature_instances creature set
        level = least(6,
          creature.level + (creature.battle_experience + v_xp) / 3),
        battle_experience = case when
          creature.level + (creature.battle_experience + v_xp) / 3 >= 6
          then 0 else (creature.battle_experience + v_xp) % 3 end
        from pg_catalog.jsonb_array_elements(v_attempt.squad_snapshot)
          as member(value)
        where member.value <> 'null'::jsonb
          and creature.user_id = v_attempt.user_id
          and creature.id = (member.value->>'id')::uuid;
    end if;
  end if;
  update public.game_battle_attempts set
    status = 'resolved', won = p_won, stars = p_stars, turns = p_turns,
    experience_awarded = v_xp,
    first_clear_shards = v_first_shards,
    resolved_at = now()
    where request_id = p_request_id;
  return pg_catalog.jsonb_build_object(
    'requestId', p_request_id, 'alreadyResolved', false,
    'won', p_won, 'stars', p_stars, 'turns', p_turns,
    'experienceAwarded', v_xp,
    'firstClearShards', v_first_shards,
    'companionSpeciesId', v_companion_species);
end;
$$;
