create table public.user_goal_snapshots (
  user_id uuid not null references auth.users(id) on delete cascade,
  goal_id text not null check (length(goal_id) between 1 and 80),
  snapshot jsonb not null,
  revision bigint not null default 1 check (revision > 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, goal_id),
  constraint goal_snapshot_shape check (
    coalesce(jsonb_typeof(snapshot) = 'object', false)
    and coalesce(snapshot->>'id' = goal_id, false)
    and coalesce(jsonb_typeof(snapshot->'completions') = 'object', false)
    and coalesce(jsonb_typeof(snapshot->'restDays') = 'array', false)
    and coalesce(jsonb_typeof(snapshot->'milestones') = 'array', false)
    and octet_length(snapshot::text) <= 262144
  )
);

alter table public.user_goal_snapshots enable row level security;
revoke all on public.user_goal_snapshots from anon, authenticated;
grant select on public.user_goal_snapshots to authenticated;

create policy "read own goal snapshots"
  on public.user_goal_snapshots for select to authenticated
  using ((select auth.uid()) = user_id);

create function public.put_goal_snapshot(
  p_goal_id text,
  p_snapshot jsonb,
  p_expected_revision bigint
) returns bigint
language plpgsql security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_revision bigint;
begin
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  if p_goal_id is null or length(p_goal_id) not between 1 and 80
     or p_snapshot is null or jsonb_typeof(p_snapshot) <> 'object'
     or p_snapshot->>'id' is distinct from p_goal_id
     or jsonb_typeof(p_snapshot->'completions') is distinct from 'object'
     or jsonb_typeof(p_snapshot->'restDays') is distinct from 'array'
     or jsonb_typeof(p_snapshot->'milestones') is distinct from 'array'
     or octet_length(p_snapshot::text) > 262144
     or p_expected_revision is null or p_expected_revision < 0 then
    raise exception 'invalid goal snapshot' using errcode = '22023';
  end if;

  if p_expected_revision = 0 then
    insert into public.user_goal_snapshots (user_id, goal_id, snapshot)
      values (v_user_id, p_goal_id, p_snapshot)
      on conflict (user_id, goal_id) do nothing
      returning revision into v_revision;
  else
    update public.user_goal_snapshots set
      snapshot = p_snapshot,
      revision = revision + 1,
      updated_at = now()
      where user_id = v_user_id and goal_id = p_goal_id
        and revision = p_expected_revision
      returning revision into v_revision;
  end if;
  return v_revision;
end;
$$;

revoke all on function public.put_goal_snapshot(text, jsonb, bigint)
  from public, anon, authenticated;
grant execute on function public.put_goal_snapshot(text, jsonb, bigint)
  to authenticated;
