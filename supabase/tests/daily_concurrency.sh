#!/usr/bin/env bash
set -euo pipefail

test_db=${1:?Pass the disposable local database name}
user_id=00000000-0000-0000-0000-000000000071
first_result=$(mktemp)
second_result=$(mktemp)
trap 'rm -f "$first_result" "$second_result"' EXIT

psql -X -v ON_ERROR_STOP=1 -q -d "$test_db" \
  -c "insert into auth.users (id) values ('$user_id')" >/dev/null

run_put() {
  local note=$1
  local expected=$2
  psql -X -v ON_ERROR_STOP=1 -qAt -d "$test_db" \
    -c "set role authenticated; select set_config('request.jwt.claim.sub', '$user_id', false); select coalesce(public.put_daily_snapshot('{\"version\":1,\"tasks\":[],\"notes\":[{\"id\":\"note-1\",\"day\":\"2026-11-01\",\"text\":\"$note\"}]}', $expected)::text, 'NULL');" \
    | tail -n 1
}

if [[ $(run_put initial 0) != 1 ]]; then
  echo 'Could not create the daily snapshot.' >&2
  exit 1
fi

run_put first 1 >"$first_result" &
first_pid=$!
run_put second 1 >"$second_result" &
second_pid=$!
wait "$first_pid"
wait "$second_pid"

results=$(cat "$first_result" "$second_result" | sort)
if [[ $results != $'2\nNULL' ]]; then
  echo "Expected one winning daily update and one stale rejection: $results" >&2
  exit 1
fi

revision=$(psql -X -v ON_ERROR_STOP=1 -qAt -d "$test_db" \
  -c "select revision from public.user_daily_snapshots where user_id = '$user_id'")
if [[ $revision != 2 ]]; then
  echo "Concurrent daily updates advanced to revision $revision." >&2
  exit 1
fi

echo 'SQL concurrency passed: daily snapshot revision'
