-- One revisioned snapshot keeps deletions visible as absence in the whole list.
create table public.user_daily_snapshots (
  user_id uuid primary key references auth.users(id) on delete cascade,
  snapshot jsonb not null,
  revision bigint not null default 1 check (revision > 0),
  updated_at timestamptz not null default now(),
  constraint daily_snapshot_shape check (
    coalesce(snapshot->'version' = '1'::jsonb, false)
    and case when jsonb_typeof(snapshot->'tasks') = 'array'
      then jsonb_array_length(snapshot->'tasks') <= 1000 else false end
    and case when jsonb_typeof(snapshot->'notes') = 'array'
      then jsonb_array_length(snapshot->'notes') <= 1000 else false end
    and octet_length(snapshot::text) <= 2097152
  )
);

alter table public.user_daily_snapshots enable row level security;
revoke all on public.user_daily_snapshots from anon, authenticated;
grant select on public.user_daily_snapshots to authenticated;

create policy "read own daily snapshot"
  on public.user_daily_snapshots for select to authenticated
  using ((select auth.uid()) = user_id);

create function public.put_daily_snapshot(
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
  if p_snapshot is null or jsonb_typeof(p_snapshot) is distinct from 'object'
     or p_snapshot->'version' is distinct from '1'::jsonb
     or jsonb_typeof(p_snapshot->'tasks') is distinct from 'array'
     or jsonb_typeof(p_snapshot->'notes') is distinct from 'array'
     or (case when jsonb_typeof(p_snapshot->'tasks') = 'array'
       then jsonb_array_length(p_snapshot->'tasks') > 1000 else true end)
     or (case when jsonb_typeof(p_snapshot->'notes') = 'array'
       then jsonb_array_length(p_snapshot->'notes') > 1000 else true end)
     or octet_length(p_snapshot::text) > 2097152
     or p_expected_revision is null or p_expected_revision < 0 then
    raise exception 'invalid daily snapshot' using errcode = '22023';
  end if;

  if p_expected_revision = 0 then
    insert into public.user_daily_snapshots (user_id, snapshot)
      values (v_user_id, p_snapshot)
      on conflict (user_id) do nothing
      returning revision into v_revision;
  else
    update public.user_daily_snapshots set
      snapshot = p_snapshot,
      revision = revision + 1,
      updated_at = now()
      where user_id = v_user_id and revision = p_expected_revision
      returning revision into v_revision;
  end if;
  return v_revision;
end;
$$;

revoke all on function public.put_daily_snapshot(jsonb, bigint)
  from public, anon, authenticated;
grant execute on function public.put_daily_snapshot(jsonb, bigint)
  to authenticated;
