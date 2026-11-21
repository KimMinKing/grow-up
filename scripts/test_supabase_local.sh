#!/usr/bin/env bash
set -euo pipefail

if [[ $(id -un) != postgres ]]; then
  echo 'Run this script as the local PostgreSQL postgres user.' >&2
  exit 1
fi
if ! pg_isready -q; then
  echo 'Start the local PostgreSQL server first.' >&2
  exit 1
fi

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_db="growup_sql_test_$$"
createdb "$test_db"
trap 'dropdb --if-exists "$test_db"' EXIT

psql -X -v ON_ERROR_STOP=1 -d "$test_db" \
  -f "$project_root/supabase/tests/local_supabase_bootstrap.sql" >/dev/null

for name in \
  20261031000000_ai_roadmap_usage \
  20261031010000_goal_sync \
  20261101000000_game_expeditions \
  20261101010000_game_draws \
  20261101020000_daily_sync \
  20261104000000_game_stage_first_clears \
  20261104010000_game_verified_battles \
  20261107000000_game_battle_attempts \
  20261107010000_game_task_battle_passes \
  20261117000000_game_river_battles \
  20261118000000_game_battle_retry_companion; do
  psql -X -v ON_ERROR_STOP=1 -d "$test_db" \
    -f "$project_root/supabase/migrations/$name.sql" >/dev/null
  echo "Migration passed: $name"
done

for name in ai_roadmap_usage goal_sync game_expeditions game_draws game_reward_flow daily_sync game_stage_first_clears game_battle_attempts game_task_battle_passes game_river_battles account_deletion; do
  psql -X -v ON_ERROR_STOP=1 -d "$test_db" \
    -f "$project_root/supabase/tests/$name.sql" >/dev/null
  echo "SQL test passed: $name"
done

bash "$project_root/supabase/tests/game_concurrency.sh" "$test_db"
bash "$project_root/supabase/tests/daily_concurrency.sh" "$test_db"
