begin;

insert into auth.users (id) values
  ('00000000-0000-0000-0000-000000000041'),
  ('00000000-0000-0000-0000-000000000042');

do $$
begin
  if has_function_privilege('anon',
       'public.award_verified_game_stage_first_clear(uuid,text,uuid,smallint)',
       'EXECUTE')
     or has_function_privilege('authenticated',
       'public.award_verified_game_stage_first_clear(uuid,text,uuid,smallint)',
       'EXECUTE')
     or not has_function_privilege('service_role',
       'public.award_verified_game_stage_first_clear(uuid,text,uuid,smallint)',
       'EXECUTE')
     or has_function_privilege('anon',
       'public.get_game_stage_reward_status()', 'EXECUTE')
     or has_table_privilege('authenticated',
       'public.game_stage_first_clears', 'INSERT')
     or has_table_privilege('service_role',
       'public.game_stage_first_clears', 'INSERT')
     or has_table_privilege('service_role',
       'public.game_stage_first_clears', 'UPDATE')
     or has_table_privilege('service_role',
       'public.game_stage_first_clears', 'DELETE')
     or has_table_privilege('authenticated',
       'public.game_verified_battles', 'INSERT')
     or has_table_privilege('authenticated',
       'public.game_verified_battles', 'UPDATE')
     or has_table_privilege('authenticated',
       'public.game_verified_battles', 'DELETE')
     or has_table_privilege('anon',
       'public.game_verified_battles', 'SELECT')
     or not has_table_privilege('service_role',
       'public.game_verified_battles', 'INSERT')
     or has_table_privilege('service_role',
       'public.game_verified_battles', 'UPDATE')
     or has_table_privilege('service_role',
       'public.game_verified_battles', 'DELETE') then
    raise exception 'first-clear reward can be forged by a client';
  end if;
end;
$$;

set role authenticated;
select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000041', false);
select public.claim_game_starter('pine_fox');
select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000042', false);
select public.claim_game_starter('wave_otter');
reset role;

-- Keep the expected failure outside the handler so a successful payout fails
-- this test instead of catching its own assertion.
create function public.test_expect_stage_rejection(
  p_user uuid, p_stage text, p_battle uuid, p_stars smallint, p_label text)
returns void language plpgsql as $$
begin
  begin
    perform public.award_verified_game_stage_first_clear(
      p_user, p_stage, p_battle, p_stars);
  exception when sqlstate '22023' then
    return;
  end;
  raise exception '%', p_label;
end;
$$;

set role service_role;
insert into public.game_verified_battles
  (battle_ref, user_id, stage_id, won, stars) values
  ('40000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000041', 'forest_moss_gate', true, 3),
  ('40000000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-000000000041', 'forest_firefly_path', true, 2),
  ('40000000-0000-0000-0000-000000000003',
   '00000000-0000-0000-0000-000000000041', 'forest_dawn_lookout', true, 1),
  ('40000000-0000-0000-0000-000000000005',
   '00000000-0000-0000-0000-000000000042', 'forest_moss_gate', true, 2),
  ('40000000-0000-0000-0000-000000000006',
   '00000000-0000-0000-0000-000000000041', 'forest_moss_gate', false, 0);
do $$
declare
  v_user uuid := '00000000-0000-0000-0000-000000000041';
  v_first jsonb;
  v_repeat jsonb;
  v_second jsonb;
  v_third jsonb;
begin
  perform public.test_expect_stage_rejection(v_user, 'forest_moss_gate',
    '40000000-0000-0000-0000-000000000007', 3::smallint,
    'unverified battle was paid');
  perform public.test_expect_stage_rejection(v_user, 'forest_moss_gate',
    '40000000-0000-0000-0000-000000000001', 2::smallint,
    'mismatched stars were paid');
  perform public.test_expect_stage_rejection(v_user, 'forest_moss_gate',
    '40000000-0000-0000-0000-000000000002', 2::smallint,
    'another stage battle was paid');
  perform public.test_expect_stage_rejection(v_user, 'forest_moss_gate',
    '40000000-0000-0000-0000-000000000005', 2::smallint,
    'another account battle was paid');
  perform public.test_expect_stage_rejection(v_user, 'forest_moss_gate',
    '40000000-0000-0000-0000-000000000006', 1::smallint,
    'lost battle was paid');
  perform public.test_expect_stage_rejection(v_user, 'forest_firefly_path',
    '40000000-0000-0000-0000-000000000002', 2::smallint,
    'second stage bypassed prerequisite');
  perform public.test_expect_stage_rejection(v_user, 'unknown',
    '40000000-0000-0000-0000-000000000009', 2::smallint,
    'unknown stage was accepted');
  perform public.test_expect_stage_rejection(v_user, 'forest_moss_gate',
    '40000000-0000-0000-0000-000000000009', 0::smallint,
    'zero-star result was accepted');
  if (select draw_shards from public.game_wallets where user_id = v_user) <> 0 or
     (select count(*) from public.game_stage_first_clears
      where user_id = v_user) <> 0 then
    raise exception 'rejected battles changed the reward ledger';
  end if;

  v_first := public.award_verified_game_stage_first_clear(
    v_user, 'forest_moss_gate',
    '40000000-0000-0000-0000-000000000001', 3::smallint);
  v_repeat := public.award_verified_game_stage_first_clear(
    v_user, 'forest_moss_gate',
    '40000000-0000-0000-0000-000000000001', 3::smallint);
  if (v_first->>'awardedShards')::integer <> 1 or
     (v_first->>'alreadyGranted')::boolean or
     (v_repeat->>'awardedShards')::integer <> 0 or
     not (v_repeat->>'alreadyGranted')::boolean or
     (select draw_shards from public.game_wallets where user_id = v_user) <> 1 then
    raise exception 'first clear was not paid exactly once';
  end if;

  perform public.test_expect_stage_rejection(v_user, 'forest_firefly_path',
    '40000000-0000-0000-0000-000000000001', 2::smallint,
    'battle reference was reused for another stage');
  v_second := public.award_verified_game_stage_first_clear(
    v_user, 'forest_firefly_path',
    '40000000-0000-0000-0000-000000000002', 2::smallint);
  v_third := public.award_verified_game_stage_first_clear(
    v_user, 'forest_dawn_lookout',
    '40000000-0000-0000-0000-000000000003', 1::smallint);
  if (v_second->>'awardedShards')::integer <> 1 or
     (v_third->>'awardedShards')::integer <> 2 or
     (select draw_shards from public.game_wallets where user_id = v_user) <> 4 or
     (select count(*) from public.game_stage_first_clears
       where user_id = v_user) <> 3 then
    raise exception 'ordered first clear rewards were wrong';
  end if;
  v_repeat := public.award_verified_game_stage_first_clear(
    v_user, 'forest_dawn_lookout',
    '40000000-0000-0000-0000-000000000004', 3::smallint);
  if (v_repeat->>'awardedShards')::integer <> 0 or
     (select draw_shards from public.game_wallets where user_id = v_user) <> 4 then
    raise exception 'boss retry minted shards';
  end if;
end;
$$;
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000041', false);
do $$
declare
  v_first jsonb;
  v_retry jsonb;
begin
  if (select count(*) from public.game_verified_battles) <> 4 then
    raise exception 'verified battle evidence leaked or was hidden from owner';
  end if;
  v_first := public.draw_game_creature(
    '40000000-0000-0000-0000-000000000010');
  v_retry := public.draw_game_creature(
    '40000000-0000-0000-0000-000000000010');
  if (v_first->>'remainingShards')::integer <> 1 or
     (v_first->>'alreadyDrawn')::boolean or
     (v_retry->>'remainingShards')::integer <> 1 or
     not (v_retry->>'alreadyDrawn')::boolean or
     (select count(*) from public.game_creature_instances) <> 2 then
    raise exception 'first-clear shards did not fund exactly one draw';
  end if;
  if (public.get_game_stage_reward_status()->>'draw_shards')::integer <> 1 or
     pg_catalog.jsonb_array_length(
       public.get_game_stage_reward_status()->'first_clears') <> 3 then
    raise exception 'server reward status did not match the wallet';
  end if;
end;
$$;

select set_config('request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000042', false);
do $$
begin
  if (select count(*) from public.game_verified_battles) <> 1 then
    raise exception 'verified battle evidence leaked across accounts';
  end if;
  if (select count(*) from public.game_stage_first_clears) <> 0 then
    raise exception 'another user can read first clears';
  end if;
  if (public.get_game_stage_reward_status()->>'draw_shards')::integer <> 0 or
     pg_catalog.jsonb_array_length(
       public.get_game_stage_reward_status()->'first_clears') <> 0 then
    raise exception 'server reward status leaked another account';
  end if;
end;
$$;
reset role;

rollback;
