-- Three expedition shards buy one free draw. Requests are idempotent per user.
create table public.game_draw_requests (
  user_id uuid not null references auth.users(id) on delete cascade,
  request_id uuid not null,
  creature_id uuid not null,
  guaranteed boolean not null,
  shards_spent smallint not null default 3 check (shards_spent = 3),
  created_at timestamptz not null default now(),
  primary key (user_id, request_id),
  unique (user_id, creature_id),
  foreign key (user_id, creature_id)
    references public.game_creature_instances (user_id, id) on delete cascade
);

create index game_draw_history
  on public.game_draw_requests (user_id, created_at desc);

alter table public.game_draw_requests enable row level security;
revoke all on public.game_draw_requests from anon, authenticated;
grant select on public.game_draw_requests to authenticated;
create policy "read own game draws" on public.game_draw_requests
  for select to authenticated using ((select auth.uid()) = user_id);

create function public.draw_game_creature(p_request_id uuid) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_previous public.game_draw_requests%rowtype;
  v_creature public.game_creature_instances%rowtype;
  v_shards integer;
  v_draw_count integer;
  v_species_id text;
  v_guaranteed boolean := false;
  v_roll integer;
begin
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  if p_request_id is null then
    raise exception 'draw request required' using errcode = '22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('game:' || v_user_id::text));

  select * into v_previous from public.game_draw_requests
    where user_id = v_user_id and request_id = p_request_id;
  if found then
    select * into v_creature from public.game_creature_instances
      where user_id = v_user_id and id = v_previous.creature_id;
    select draw_shards into v_shards from public.game_wallets
      where user_id = v_user_id;
    return pg_catalog.jsonb_build_object(
      'creatureId', v_creature.id,
      'speciesId', v_creature.species_id,
      'remainingShards', v_shards,
      'guaranteed', v_previous.guaranteed,
      'alreadyDrawn', true);
  end if;

  if not exists (select 1 from public.game_creature_instances
      where user_id = v_user_id and source = 'starter') then
    raise exception 'starter required' using errcode = '22023';
  end if;
  if (select count(*) from public.game_creature_instances
      where user_id = v_user_id) >= 20 then
    raise exception 'collection full' using errcode = '22023';
  end if;
  select draw_shards into v_shards from public.game_wallets
    where user_id = v_user_id for update;
  if v_shards is null or v_shards < 3 then
    raise exception 'not enough draw shards' using errcode = '22023';
  end if;

  select count(*) into v_draw_count from public.game_draw_requests
    where user_id = v_user_id;
  if v_draw_count = 0 or (v_draw_count + 1) % 5 = 0 then
    select candidate.species_id into v_species_id
    from (values ('pine_fox'), ('wave_otter'), ('star_crow'))
      as candidate(species_id)
    where not exists (
      select 1 from public.game_creature_instances owned
      where owned.user_id = v_user_id
        and owned.species_id = candidate.species_id)
    order by pg_catalog.random()
    limit 1;
    v_guaranteed := v_species_id is not null;
  end if;
  if v_species_id is null then
    v_roll := pg_catalog.floor(pg_catalog.random() * 100)::integer;
    v_species_id := case
      when v_roll < 50 then 'pine_fox'
      when v_roll < 80 then 'wave_otter'
      else 'star_crow'
    end;
  end if;

  insert into public.game_creature_instances (user_id, species_id, source)
    values (v_user_id, v_species_id, 'draw') returning * into v_creature;
  update public.game_wallets set draw_shards = draw_shards - 3
    where user_id = v_user_id returning draw_shards into v_shards;
  insert into public.game_draw_requests
    (user_id, request_id, creature_id, guaranteed)
    values (v_user_id, p_request_id, v_creature.id, v_guaranteed);
  return pg_catalog.jsonb_build_object(
    'creatureId', v_creature.id,
    'speciesId', v_creature.species_id,
    'remainingShards', v_shards,
    'guaranteed', v_guaranteed,
    'alreadyDrawn', false);
end;
$$;

revoke all on function public.draw_game_creature(uuid)
  from public, anon, authenticated;
grant execute on function public.draw_game_creature(uuid) to authenticated;
