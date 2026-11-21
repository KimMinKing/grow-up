begin;
insert into auth.users (id) values
  ('00000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-000000000002');

do $$
declare
  first_call uuid;
  second_user uuid;
  retry_call uuid;
begin
  if has_function_privilege('authenticated',
      'public.reserve_ai_roadmap_call(uuid,date,bigint,bigint)', 'EXECUTE') then
    raise exception 'client can reserve AI usage';
  end if;

  first_call := public.reserve_ai_roadmap_call(
    '00000000-0000-0000-0000-000000000001', '2026-10-01', 100, 150);
  if first_call is null then raise exception 'first call was rejected'; end if;
  if public.reserve_ai_roadmap_call(
      '00000000-0000-0000-0000-000000000001', '2026-10-01', 100, 150) is not null then
    raise exception 'duplicate call was accepted';
  end if;
  if public.reserve_ai_roadmap_call(
      '00000000-0000-0000-0000-000000000002', '2026-10-01', 100, 150) is not null then
    raise exception 'global budget was exceeded';
  end if;

  perform public.finish_ai_roadmap_call(first_call,
    '00000000-0000-0000-0000-000000000001', false, 10, 5, 10);
  second_user := public.reserve_ai_roadmap_call(
    '00000000-0000-0000-0000-000000000002', '2026-10-01', 100, 150);
  if second_user is null then raise exception 'released budget was not reusable'; end if;
  perform public.finish_ai_roadmap_call(second_user,
    '00000000-0000-0000-0000-000000000002', true, 20, 10, 80);
  if public.reserve_ai_roadmap_call(
      '00000000-0000-0000-0000-000000000002', '2026-10-01', 100, 200) is not null then
    raise exception 'successful user got a second monthly call';
  end if;

  retry_call := public.reserve_ai_roadmap_call(
    '00000000-0000-0000-0000-000000000001', '2026-10-01', 100, 200);
  if retry_call is null then raise exception 'retry after failure was rejected'; end if;
  perform public.finish_ai_roadmap_call(retry_call,
    '00000000-0000-0000-0000-000000000001', false, 0, 0, 0);
  retry_call := public.reserve_ai_roadmap_call(
    '00000000-0000-0000-0000-000000000001', '2026-10-01', 100, 200);
  if retry_call is null then raise exception 'last retry was rejected'; end if;
  perform public.finish_ai_roadmap_call(retry_call,
    '00000000-0000-0000-0000-000000000001', false, 0, 0, 0);
  if public.reserve_ai_roadmap_call(
      '00000000-0000-0000-0000-000000000001', '2026-10-01', 100, 200) is not null then
    raise exception 'failure retry cap was exceeded';
  end if;
end;
$$;
rollback;
