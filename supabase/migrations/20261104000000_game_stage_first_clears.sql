-- A server battle verifier may award each first-forest stage exactly once.
-- The current local battle result is not proof and must never call this RPC.
create table public.game_stage_first_clears (
  user_id uuid not null references auth.users(id) on delete cascade,
  stage_id text not null check (stage_id in (
    'forest_moss_gate', 'forest_firefly_path', 'forest_dawn_lookout')),
  battle_ref uuid not null,
  stars smallint not null check (stars between 1 and 3),
  badge_id text not null check (badge_id in (
    'first_footprint', 'forest_lantern', 'forest_dawn')),
  awarded_shards smallint not null check (awarded_shards between 1 and 2),
  awarded_at timestamptz not null default now(),
  primary key (user_id, stage_id),
  unique (user_id, battle_ref),
  unique (user_id, badge_id)
);

alter table public.game_stage_first_clears enable row level security;
revoke all on public.game_stage_first_clears from anon, authenticated, service_role;
grant select on public.game_stage_first_clears to authenticated;
grant select on public.game_stage_first_clears, public.game_wallets to service_role;
create policy "read own first clears" on public.game_stage_first_clears
  for select to authenticated using ((select auth.uid()) = user_id);

create function public.award_verified_game_stage_first_clear(
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

revoke all on function public.award_verified_game_stage_first_clear(
  uuid, text, uuid, smallint) from public, anon, authenticated;
grant execute on function public.award_verified_game_stage_first_clear(
  uuid, text, uuid, smallint) to service_role;

create function public.get_game_stage_reward_status() returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  return (
    select pg_catalog.jsonb_build_object(
      'draw_shards', coalesce(wallet.draw_shards, 0),
      'first_clears', coalesce(clears.items, '[]'::jsonb))
    from (select 1) anchor
    left join public.game_wallets wallet on wallet.user_id = v_user_id
    left join lateral (
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'stage_id', stage_id,
        'badge_id', badge_id,
        'awarded_shards', awarded_shards)
        order by awarded_at, stage_id) as items
      from public.game_stage_first_clears
      where user_id = v_user_id
    ) clears on true
  );
end;
$$;

revoke all on function public.get_game_stage_reward_status()
  from public, anon, authenticated;
grant execute on function public.get_game_stage_reward_status()
  to authenticated;
