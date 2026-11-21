-- Account battle passes are earned from synced, self-reported task completions.
-- Two transition passes let existing players enter the new system.
alter table public.game_wallets
  add column battle_passes integer not null default 2
    check (battle_passes between 0 and 30);

create table public.game_task_battle_grants (
  user_id uuid not null references auth.users(id) on delete cascade,
  task_id text not null check (length(task_id) between 1 and 80),
  completed_day text not null check (completed_day ~ '^\d{4}-\d{2}-\d{2}$'),
  passes smallint not null default 2 check (passes = 2),
  granted_at timestamptz not null default now(),
  primary key (user_id, task_id, completed_day)
);
alter table public.game_task_battle_grants enable row level security;
revoke all on public.game_task_battle_grants from anon, authenticated, service_role;
grant select on public.game_task_battle_grants to authenticated;
create policy "read own task battle grants"
  on public.game_task_battle_grants for select to authenticated
  using ((select auth.uid()) = user_id);

create function public.claim_game_task_battle_passes() returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_snapshot jsonb;
  v_balance integer;
  v_added integer := 0;
  v_task record;
  v_today text := (now() at time zone 'Asia/Seoul')::date::text;
  v_earliest text := ((now() at time zone 'Asia/Seoul')::date - 30)::text;
begin
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('game:' || v_user_id::text));
  select snapshot into v_snapshot from public.user_daily_snapshots
    where user_id = v_user_id;
  if v_snapshot is null then
    raise exception 'sync tasks before claiming passes' using errcode = '22023';
  end if;
  insert into public.game_wallets (user_id) values (v_user_id)
    on conflict (user_id) do nothing;
  select battle_passes into v_balance from public.game_wallets
    where user_id = v_user_id for update;

  for v_task in
    with task_rows as (
      select item from pg_catalog.jsonb_array_elements(v_snapshot->'tasks') as item
      where pg_catalog.jsonb_typeof(item) = 'object'
        and item->>'roadmapLinked' is distinct from 'true'
        and pg_catalog.length(item->>'id') between 1 and 80
    ), completions as (
      select item->>'id' as task_id, item->>'completedDay' as day
        from task_rows
      union all
      select item->>'id' as task_id, occurrence.day
        from task_rows,
          lateral pg_catalog.jsonb_array_elements_text(
            case when pg_catalog.jsonb_typeof(item->'completedOccurrences') = 'array'
              then item->'completedOccurrences' else '[]'::jsonb end)
            as occurrence(day)
    )
    select distinct task_id, day from completions
      where day ~ '^\d{4}-\d{2}-\d{2}$'
        and day between v_earliest and v_today
      order by day desc, task_id
  loop
    exit when v_balance > 28;
    insert into public.game_task_battle_grants
      (user_id, task_id, completed_day)
      values (v_user_id, v_task.task_id, v_task.day)
      on conflict do nothing;
    if found then
      v_balance := v_balance + 2;
      v_added := v_added + 2;
    end if;
  end loop;
  if v_added > 0 then
    update public.game_wallets set battle_passes = v_balance
      where user_id = v_user_id;
  end if;
  return pg_catalog.jsonb_build_object(
    'addedPasses', v_added, 'battlePasses', v_balance);
end;
$$;

revoke all on function public.claim_game_task_battle_passes()
  from public, anon, authenticated;
grant execute on function public.claim_game_task_battle_passes()
  to authenticated;

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

revoke all on function public.begin_game_forest_battle(uuid, text)
  from public, anon, authenticated;
grant execute on function public.begin_game_forest_battle(uuid, text)
  to authenticated;
