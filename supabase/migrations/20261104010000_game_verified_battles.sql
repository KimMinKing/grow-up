-- A future server battle engine writes immutable evidence before a first-clear
-- reward can be paid. Client battle saves are never inserted here.
create table public.game_verified_battles (
  battle_ref uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  stage_id text not null check (stage_id in (
    'forest_moss_gate', 'forest_firefly_path', 'forest_dawn_lookout')),
  won boolean not null,
  stars smallint not null,
  verified_at timestamptz not null default now(),
  check ((won and stars between 1 and 3) or (not won and stars = 0))
);

create index game_verified_battles_user_history
  on public.game_verified_battles (user_id, verified_at desc);

alter table public.game_verified_battles enable row level security;
revoke all on public.game_verified_battles from anon, authenticated, service_role;
grant select on public.game_verified_battles to authenticated;
grant select, insert on public.game_verified_battles to service_role;
create policy "read own verified battles" on public.game_verified_battles
  for select to authenticated using ((select auth.uid()) = user_id);

-- This protects the first-clear ledger even if a future service accidentally
-- calls the payout RPC with a fabricated or mismatched battle reference.
create function public.require_verified_game_stage_first_clear()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.game_verified_battles verified
    where verified.battle_ref = new.battle_ref
      and verified.user_id = new.user_id
      and verified.stage_id = new.stage_id
      and verified.stars = new.stars
      and verified.won
  ) then
    raise exception 'matching verified battle required' using errcode = '22023';
  end if;
  return new;
end;
$$;

revoke all on function public.require_verified_game_stage_first_clear()
  from public, anon, authenticated;

create trigger require_verified_game_stage_first_clear
before insert on public.game_stage_first_clears
for each row execute function public.require_verified_game_stage_first_clear();
