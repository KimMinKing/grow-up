#!/usr/bin/env bash
set -euo pipefail

test_db=${1:?Pass the disposable local database name}
user_id=00000000-0000-0000-0000-000000000061
request_id=60000000-0000-0000-0000-000000000001

psql -X -v ON_ERROR_STOP=1 -q -d "$test_db" <<SQL
insert into auth.users (id) values ('$user_id');
SQL

run_as_user() {
  psql -X -v ON_ERROR_STOP=1 -qAt -d "$test_db" \
    -c "set role authenticated; select set_config('request.jwt.claim.sub', '$user_id', false); $1" \
    >/dev/null
}

run_as_server() {
  psql -X -v ON_ERROR_STOP=1 -qAt -d "$test_db" \
    -c "set role service_role; $1" >/dev/null
}

run_with_lock() {
  psql -X -v ON_ERROR_STOP=1 -qAt -d "$test_db" \
    -c "begin; set role authenticated; select set_config('request.jwt.claim.sub', '$user_id', false); select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('game:$user_id')); select pg_catalog.pg_sleep(1); $1 commit;" \
    >/dev/null
}

run_server_with_lock() {
  psql -X -v ON_ERROR_STOP=1 -qAt -d "$test_db" \
    -c "begin; set role service_role; select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('game:$user_id')); select pg_catalog.pg_sleep(1); $1 commit;" \
    >/dev/null
}

wait_for_game_lock() {
  for ((attempt = 0; attempt < 30; attempt++)); do
    lock_count=$(psql -X -v ON_ERROR_STOP=1 -qAt -d "$test_db" \
      -c "select count(*) from pg_locks where locktype = 'advisory' and granted and database = (select oid from pg_database where datname = current_database())")
    if ((lock_count > 0)); then
      return
    fi
    sleep 0.05
  done
  echo 'The first game request did not acquire its lock in time.' >&2
  exit 1
}

run_as_user "select public.claim_game_starter('pine_fox');"

run_with_lock "select public.start_game_expedition('pine_forest');" &
first_pid=$!
wait_for_game_lock
run_as_user "select public.start_game_expedition('pine_forest');" &
second_pid=$!
wait "$first_pid"
wait "$second_pid"

expedition_id=$(psql -X -v ON_ERROR_STOP=1 -qAt -d "$test_db" \
  -c "select id from public.game_expeditions where user_id = '$user_id'")
if [[ -z $expedition_id ]]; then
  echo 'Concurrent expedition start did not create a row.' >&2
  exit 1
fi
psql -X -v ON_ERROR_STOP=1 -q -d "$test_db" \
  -c "update public.game_expeditions set started_at = now() - interval '11 minutes', ready_at = now() - interval '1 minute' where id = '$expedition_id'" \
  >/dev/null

run_with_lock "select public.claim_game_expedition('$expedition_id');" &
first_pid=$!
wait_for_game_lock
run_as_user "select public.claim_game_expedition('$expedition_id');" &
second_pid=$!
wait "$first_pid"
wait "$second_pid"

psql -X -v ON_ERROR_STOP=1 -q -d "$test_db" \
  -c "update public.game_wallets set draw_shards = 3 where user_id = '$user_id'" \
  >/dev/null
run_with_lock "select public.draw_game_creature('$request_id');" &
first_pid=$!
wait_for_game_lock
run_as_user "select public.draw_game_creature('$request_id');" &
second_pid=$!
wait "$first_pid"
wait "$second_pid"

psql -X -v ON_ERROR_STOP=1 -q -d "$test_db" <<'SQL'
do $$
begin
  if (select count(*) from public.game_expeditions) <> 1
     or (select count(*) from public.game_draw_requests) <> 1
     or (select count(*) from public.game_creature_instances) <> 2
     or (select draw_shards from public.game_wallets) <> 0 then
    raise exception 'parallel game requests changed state more than once';
  end if;
end;
$$;
SQL

run_as_server "insert into public.game_verified_battles (battle_ref, user_id, stage_id, won, stars) values ('60000000-0000-0000-0000-000000000002', '$user_id', 'forest_moss_gate', true, 3), ('60000000-0000-0000-0000-000000000003', '$user_id', 'forest_moss_gate', true, 2);"
run_server_with_lock "select public.award_verified_game_stage_first_clear('$user_id', 'forest_moss_gate', '60000000-0000-0000-0000-000000000002', 3::smallint);" &
first_pid=$!
wait_for_game_lock
run_as_server "select public.award_verified_game_stage_first_clear('$user_id', 'forest_moss_gate', '60000000-0000-0000-0000-000000000003', 2::smallint);" &
second_pid=$!
wait "$first_pid"
wait "$second_pid"

psql -X -v ON_ERROR_STOP=1 -q -d "$test_db" <<'SQL'
do $$
begin
  if (select count(*) from public.game_stage_first_clears) <> 1
     or (select draw_shards from public.game_wallets) <> 1 then
    raise exception 'parallel first-clear requests paid more than once';
  end if;
end;
$$;
SQL

run_as_user "select public.begin_game_forest_battle('60000000-0000-0000-0000-000000000004', 'forest_moss_gate');"
run_server_with_lock "select public.finish_game_forest_battle('60000000-0000-0000-0000-000000000004', true, 3::smallint, 5::smallint);" &
first_pid=$!
wait_for_game_lock
run_as_server "select public.finish_game_forest_battle('60000000-0000-0000-0000-000000000004', true, 3::smallint, 5::smallint);" &
second_pid=$!
wait "$first_pid"
wait "$second_pid"

psql -X -v ON_ERROR_STOP=1 -q -d "$test_db" <<'SQL'
do $$
begin
  if (select count(*) from public.game_verified_battles
      where battle_ref = '60000000-0000-0000-0000-000000000004') <> 1
     or (select count(*) from public.game_battle_attempts
      where status = 'resolved' and experience_awarded = 1) <> 1
     or (select battle_experience from public.game_creature_instances
      where source = 'starter') <> 1
     or (select draw_shards from public.game_wallets) <> 1 then
    raise exception 'parallel battle result granted rewards twice';
  end if;
end;
$$;
SQL

run_as_user "select public.put_daily_snapshot(jsonb_build_object('version', 1, 'notes', jsonb_build_array(), 'tasks', jsonb_build_array(jsonb_build_object('id', 'concurrent-task', 'completedDay', (now() at time zone 'Asia/Seoul')::date::text, 'roadmapLinked', false))), 0);"
run_with_lock "select public.claim_game_task_battle_passes();" &
first_pid=$!
wait_for_game_lock
run_as_user "select public.claim_game_task_battle_passes();" &
second_pid=$!
wait "$first_pid"
wait "$second_pid"

psql -X -v ON_ERROR_STOP=1 -q -d "$test_db" <<'SQL'
do $$
begin
  if (select count(*) from public.game_task_battle_grants) <> 1
     or (select battle_passes from public.game_wallets) <> 3 then
    raise exception 'parallel task claims granted battle passes twice';
  end if;
end;
$$;
SQL

echo 'SQL concurrency passed: start, reward, draw, first clear, battle, task passes'
