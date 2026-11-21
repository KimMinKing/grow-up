create table public.ai_roadmap_usage (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  month_start date not null,
  status text not null check (status in ('reserved', 'succeeded', 'failed')),
  reserved_micros bigint not null check (reserved_micros > 0),
  actual_micros bigint check (actual_micros >= 0),
  input_tokens integer check (input_tokens >= 0),
  output_tokens integer check (output_tokens >= 0),
  created_at timestamptz not null default now(),
  finished_at timestamptz
);

create unique index ai_roadmap_one_success_per_month
  on public.ai_roadmap_usage (user_id, month_start)
  where status in ('reserved', 'succeeded');

create index ai_roadmap_month_cost
  on public.ai_roadmap_usage (month_start);

alter table public.ai_roadmap_usage enable row level security;
-- Usage and costs are server-only. No client policies are granted.
revoke all on public.ai_roadmap_usage from anon, authenticated;

create function public.reserve_ai_roadmap_call(
  p_user_id uuid,
  p_month_start date,
  p_request_budget_micros bigint,
  p_month_budget_micros bigint
) returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
  v_spent bigint;
begin
  if p_user_id is null or p_month_start is null
     or p_month_start <> date_trunc('month', p_month_start)::date
     or p_request_budget_micros <= 0 or p_month_budget_micros <= 0 then
    raise exception 'invalid quota arguments';
  end if;

  perform pg_advisory_xact_lock(hashtext('ai-roadmap-' || p_month_start::text));
  update public.ai_roadmap_usage set status = 'failed', actual_micros = 0,
    finished_at = now()
    where month_start = p_month_start and status = 'reserved'
      and created_at < now() - interval '2 minutes';
  select coalesce(sum(coalesce(actual_micros, reserved_micros)), 0)
    into v_spent from public.ai_roadmap_usage
    where month_start = p_month_start;
  if v_spent + p_request_budget_micros > p_month_budget_micros
     or exists (
       select 1 from public.ai_roadmap_usage
       where user_id = p_user_id and month_start = p_month_start
         and status in ('reserved', 'succeeded')
     ) or (
       select count(*) from public.ai_roadmap_usage
       where user_id = p_user_id and month_start = p_month_start
     ) >= 3 then
    return null;
  end if;

  insert into public.ai_roadmap_usage
    (user_id, month_start, status, reserved_micros)
    values (p_user_id, p_month_start, 'reserved', p_request_budget_micros)
    returning id into v_id;
  return v_id;
end;
$$;

create function public.finish_ai_roadmap_call(
  p_id uuid,
  p_user_id uuid,
  p_success boolean,
  p_input_tokens integer,
  p_output_tokens integer,
  p_actual_micros bigint
) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  update public.ai_roadmap_usage set
    status = case when p_success then 'succeeded' else 'failed' end,
    input_tokens = p_input_tokens,
    output_tokens = p_output_tokens,
    actual_micros = p_actual_micros,
    finished_at = now()
  where id = p_id and user_id = p_user_id and status = 'reserved';
  if not found then
    raise exception 'roadmap reservation missing';
  end if;
end;
$$;

revoke all on function public.reserve_ai_roadmap_call(uuid, date, bigint, bigint) from public, anon, authenticated;
revoke all on function public.finish_ai_roadmap_call(uuid, uuid, boolean, integer, integer, bigint) from public, anon, authenticated;
grant execute on function public.reserve_ai_roadmap_call(uuid, date, bigint, bigint) to service_role;
grant execute on function public.finish_ai_roadmap_call(uuid, uuid, boolean, integer, integer, bigint) to service_role;
