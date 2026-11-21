-- The client may read its game state, but only these functions may change it.
create table public.game_creature_instances (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  species_id text not null check (species_id in ('pine_fox', 'wave_otter', 'star_crow')),
  level smallint not null default 1 check (level between 1 and 100),
  source text not null check (source in ('starter', 'draw')),
  created_at timestamptz not null default now(),
  unique (user_id, id)
);

create unique index game_one_starter_per_user
  on public.game_creature_instances (user_id) where source = 'starter';

create table public.game_squad_slots (
  user_id uuid not null references auth.users(id) on delete cascade,
  slot smallint not null check (slot between 1 and 5),
  creature_id uuid not null,
  primary key (user_id, slot),
  unique (user_id, creature_id),
  foreign key (user_id, creature_id)
    references public.game_creature_instances (user_id, id) on delete cascade
);

create table public.game_wallets (
  user_id uuid primary key references auth.users(id) on delete cascade,
  draw_shards integer not null default 0 check (draw_shards >= 0)
);

create table public.game_expeditions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  region_id text not null check (region_id = 'pine_forest'),
  started_at timestamptz not null default now(),
  ready_at timestamptz not null,
  claimed_at timestamptz,
  reward_shards integer not null check (reward_shards between 1 and 2),
  check (ready_at > started_at),
  check (claimed_at is null or claimed_at >= ready_at)
);

create unique index game_one_unclaimed_expedition_per_user
  on public.game_expeditions (user_id) where claimed_at is null;
create index game_expedition_history
  on public.game_expeditions (user_id, started_at desc);

alter table public.game_creature_instances enable row level security;
alter table public.game_squad_slots enable row level security;
alter table public.game_wallets enable row level security;
alter table public.game_expeditions enable row level security;

revoke all on public.game_creature_instances from anon, authenticated;
revoke all on public.game_squad_slots from anon, authenticated;
revoke all on public.game_wallets from anon, authenticated;
revoke all on public.game_expeditions from anon, authenticated;
grant select on public.game_creature_instances to authenticated;
grant select on public.game_squad_slots to authenticated;
grant select on public.game_wallets to authenticated;
grant select on public.game_expeditions to authenticated;

create policy "read own game creatures" on public.game_creature_instances
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "read own squad" on public.game_squad_slots
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "read own game wallet" on public.game_wallets
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "read own expeditions" on public.game_expeditions
  for select to authenticated using ((select auth.uid()) = user_id);

create function public.claim_game_starter(p_species_id text) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_creature public.game_creature_instances%rowtype;
begin
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  if p_species_id is null or p_species_id not in
      ('pine_fox', 'wave_otter', 'star_crow') then
    raise exception 'invalid starter species' using errcode = '22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('game:' || v_user_id::text));
  select * into v_creature from public.game_creature_instances
    where user_id = v_user_id and source = 'starter';
  if found then
    return pg_catalog.jsonb_build_object(
      'creatureId', v_creature.id,
      'speciesId', v_creature.species_id,
      'alreadyClaimed', true);
  end if;
  if (select count(*) from public.game_creature_instances
      where user_id = v_user_id) >= 20 then
    raise exception 'collection full' using errcode = '22023';
  end if;
  insert into public.game_creature_instances (user_id, species_id, source)
    values (v_user_id, p_species_id, 'starter') returning * into v_creature;
  insert into public.game_squad_slots (user_id, slot, creature_id)
    values (v_user_id, 1, v_creature.id);
  insert into public.game_wallets (user_id) values (v_user_id)
    on conflict (user_id) do nothing;
  return pg_catalog.jsonb_build_object(
    'creatureId', v_creature.id,
    'speciesId', v_creature.species_id,
    'alreadyClaimed', false);
end;
$$;

create function public.set_game_squad_slot(
  p_creature_id uuid, p_slot smallint) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_old_slot smallint;
  v_displaced uuid;
begin
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  if p_creature_id is null or p_slot is null or p_slot not between 1 and 5 then
    raise exception 'invalid squad slot' using errcode = '22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('game:' || v_user_id::text));
  if not exists (select 1 from public.game_creature_instances
      where user_id = v_user_id and id = p_creature_id) then
    raise exception 'creature not owned' using errcode = '22023';
  end if;
  if exists (select 1 from public.game_expeditions
      where user_id = v_user_id and claimed_at is null) then
    raise exception 'expedition in progress' using errcode = '22023';
  end if;
  select slot into v_old_slot from public.game_squad_slots
    where user_id = v_user_id and creature_id = p_creature_id;
  if v_old_slot = p_slot then return; end if;
  select creature_id into v_displaced from public.game_squad_slots
    where user_id = v_user_id and slot = p_slot;
  delete from public.game_squad_slots
    where user_id = v_user_id and (slot = p_slot or slot = v_old_slot);
  insert into public.game_squad_slots (user_id, slot, creature_id)
    values (v_user_id, p_slot, p_creature_id);
  if v_old_slot is not null and v_displaced is not null then
    insert into public.game_squad_slots (user_id, slot, creature_id)
      values (v_user_id, v_old_slot, v_displaced);
  end if;
end;
$$;

create function public.start_game_expedition(p_region_id text) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_expedition public.game_expeditions%rowtype;
begin
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  if p_region_id is distinct from 'pine_forest' then
    raise exception 'unknown region' using errcode = '22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('game:' || v_user_id::text));
  select * into v_expedition from public.game_expeditions
    where user_id = v_user_id and claimed_at is null;
  if found then
    return pg_catalog.jsonb_build_object(
      'expeditionId', v_expedition.id,
      'readyAt', v_expedition.ready_at,
      'rewardShards', v_expedition.reward_shards,
      'alreadyStarted', true);
  end if;
  if not exists (select 1 from public.game_squad_slots
      where user_id = v_user_id) then
    raise exception 'squad empty' using errcode = '22023';
  end if;
  if (select count(*) from public.game_expeditions
      where user_id = v_user_id
        and started_at >= date_trunc('day', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul') >= 3 then
    raise exception 'daily expedition limit reached' using errcode = '22023';
  end if;
  insert into public.game_expeditions
    (user_id, region_id, ready_at, reward_shards)
    values (v_user_id, p_region_id, now() + interval '10 minutes', 1)
    returning * into v_expedition;
  return pg_catalog.jsonb_build_object(
    'expeditionId', v_expedition.id,
    'readyAt', v_expedition.ready_at,
    'rewardShards', v_expedition.reward_shards,
    'alreadyStarted', false);
end;
$$;

create function public.claim_game_expedition(p_expedition_id uuid) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_expedition public.game_expeditions%rowtype;
  v_shards integer;
begin
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  if p_expedition_id is null then
    raise exception 'expedition required' using errcode = '22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('game:' || v_user_id::text));
  select * into v_expedition from public.game_expeditions
    where user_id = v_user_id and id = p_expedition_id for update;
  if not found then
    raise exception 'expedition not found' using errcode = '22023';
  end if;
  if v_expedition.claimed_at is null then
    if v_expedition.ready_at > now() then
      raise exception 'expedition not ready' using errcode = '22023';
    end if;
    update public.game_expeditions set claimed_at = now()
      where id = p_expedition_id;
    insert into public.game_wallets (user_id, draw_shards)
      values (v_user_id, v_expedition.reward_shards)
      on conflict (user_id) do update
      set draw_shards = game_wallets.draw_shards + excluded.draw_shards;
  end if;
  select draw_shards into v_shards from public.game_wallets
    where user_id = v_user_id;
  return pg_catalog.jsonb_build_object(
    'expeditionId', v_expedition.id,
    'awardedShards', case when v_expedition.claimed_at is null
      then v_expedition.reward_shards else 0 end,
    'totalShards', v_shards,
    'alreadyClaimed', v_expedition.claimed_at is not null);
end;
$$;

create function public.get_game_status() returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  return pg_catalog.jsonb_build_object(
    'serverNow', now(),
    'todayStarts', (
      select count(*) from public.game_expeditions
      where user_id = v_user_id
        and started_at >= pg_catalog.date_trunc(
          'day', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul'
    )
  );
end;
$$;

revoke all on function public.claim_game_starter(text)
  from public, anon, authenticated;
revoke all on function public.set_game_squad_slot(uuid, smallint)
  from public, anon, authenticated;
revoke all on function public.start_game_expedition(text)
  from public, anon, authenticated;
revoke all on function public.claim_game_expedition(uuid)
  from public, anon, authenticated;
revoke all on function public.get_game_status()
  from public, anon, authenticated;
grant execute on function public.claim_game_starter(text) to authenticated;
grant execute on function public.set_game_squad_slot(uuid, smallint) to authenticated;
grant execute on function public.start_game_expedition(text) to authenticated;
grant execute on function public.claim_game_expedition(uuid) to authenticated;
grant execute on function public.get_game_status() to authenticated;
