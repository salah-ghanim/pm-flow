#!/bin/zsh -f
# transactions: five requests through cli.py apply commit seq 1..5 with no gap,
# a repeated idempotency key commits nothing, and timeline verify replays the log
# to the head hash until a raw SQL edit makes it name the table it corrupted.
# Run by tests/knowledge_state_test.sh, which exports REPO_ROOT, FLOW, TEST_ROOT.
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
: "${REPO_ROOT:?}" "${FLOW:?}" "${TEST_ROOT:?}"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local actual="$1" expected="$2" label="$3"
  [[ "$actual" == "$expected" ]] || \
    fail "$label: expected '$expected', got '$actual'"
}

# json_get <document> <key>...: the value at that path, a string bare and
# anything else as JSON.
json_get() {
  python3 - "$@" <<'PY'
import json, sys
value = json.loads(sys.argv[1])
for key in sys.argv[2:]:
    value = value[int(key)] if isinstance(value, list) else value[key]
print(value if isinstance(value, str) else json.dumps(value))
PY
}

command -v sqlite3 >/dev/null || fail "sqlite3 is not on PATH"
CLI="$FLOW/state_service/cli.py"
DB="$TEST_ROOT/project/runs/pm_flow.db"
REQUESTS="$TEST_ROOT/requests"
mkdir -p "${DB:h}" "$REQUESTS"

count_transactions() {
  sqlite3 -readonly "$DB" 'SELECT COUNT(*) FROM state_transactions'
}

timeline_cli() {
  python3 "$CLI" timeline "$1" --db "$DB" --project ledger --timeline main
}

# request <n> <idempotency key> <operations>: a version-1 envelope on the ledger
# project's production timeline.
request() {
  printf '{"request_version": 1, "project": "ledger", "actor": {"key": "scenario", "kind": "system"}, "timeline": "main", "scope": "*", "idempotency_key": "%s", "operations": [%s]}\n' \
    "$2" "$3" > "$REQUESTS/$1.json"
}

# ------------------------------------------------------------------ fixture
#
# An empty file is a new store to `migrate --apply`. Projects are registered by
# the catalogue, not the state service, so the fixture inserts one directly.
: > "$DB"
python3 "$CLI" migrate --db "$DB" --apply >/dev/null
sqlite3 "$DB" "INSERT INTO projects (key, created_at) VALUES ('ledger', 0)"

request 1 create-timeline '{"op": "timeline.create", "op_version": 1, "purpose": "production"}'
request 2 create-alpha '{"op": "task.create", "op_version": 1, "key": "alpha", "title": "Alpha"}'
request 3 create-beta '{"op": "task.create", "op_version": 1, "key": "beta", "title": "Beta", "contract": {"done_when": "alpha ships"}}'
request 4 beta-after-alpha '{"op": "dependency.add", "op_version": 1, "task": "beta", "depends_on": "alpha"}'
request 5 alpha-started '{"op": "task.set_status", "op_version": 1, "task": "alpha", "status": "in_progress"}'

# ------------------------------------------------ five contiguous transactions
typeset -A results
for n in 1 2 3 4 5; do
  results[$n]="$(python3 "$CLI" apply --db "$DB" --request "$REQUESTS/$n.json")" || \
    fail "request $n was refused: ${results[$n]}"
  assert_eq "$(json_get "${results[$n]}" seq) $(json_get "${results[$n]}" timeline_version) $(json_get "${results[$n]}" changes)" \
    "$n $n 1" "request $n seq, timeline_version, changes"
done

log="$(timeline_cli log)"
assert_eq "$(python3 -c '
import json, sys
print(" ".join(str(entry["seq"]) for entry in json.loads(sys.argv[1])["transactions"]))
' "$log")" "1 2 3 4 5" "timeline log seq"
assert_eq "$(json_get "$log" head_seq) $(json_get "$log" version)" "5 5" "timeline head_seq and version"
for n in 1 2 3 4 5; do
  assert_eq "$(json_get "$log" transactions $((n - 1)) projection_hash)" \
    "$(json_get "${results[$n]}" projection_hash)" "logged projection hash of seq $n"
done
assert_eq "$(count_transactions)" "5" "state_transactions rows"
printf '  timeline log: seq 1 2 3 4 5\n'

# ---------------------------------------------------- idempotent replay
replayed="$(python3 "$CLI" apply --db "$DB" --request "$REQUESTS/3.json")" || \
  fail "replaying request 3 exited non-zero: $replayed"
assert_eq "$(json_get "$replayed" idempotent_replay)" "true" "replay is marked"
assert_eq "$(json_get "$replayed" transaction_id)" "$(json_get "${results[3]}" transaction_id)" \
  "replay returns the original transaction_id"
assert_eq "$(python3 -c '
import json, sys
replay, original = json.loads(sys.argv[1]), json.loads(sys.argv[2])
replay.pop("idempotent_replay")
print(replay == original)
' "$replayed" "${results[3]}")" "True" "replay returns the original result"
assert_eq "$(count_transactions)" "5" "replay added no state_transactions row"
printf '  idempotent replay of seq 3: transaction %s, 5 rows\n' "$(json_get "$replayed" transaction_id)"

# ------------------------------------------------------- verify by replay
head_hash="$(json_get "${results[5]}" projection_hash)"
assert_eq "$(json_get "$(timeline_cli projection)" projection_hash)" "$head_hash" \
  "timeline projection hash at head"

verified="$(timeline_cli verify)" || fail "verify exited non-zero before any outside edit: $verified"
assert_eq "$(json_get "$verified" match) $(json_get "$verified" head_seq)" "true 5" "verify before the edit"
assert_eq "$(json_get "$verified" stored)" "$head_hash" "verify stored hash"
assert_eq "$(json_get "$verified" replayed)" "$head_hash" "verify replayed hash"
printf '  verify before the edit: match true\n'

# A legacy task (NULL timeline_id) in the same project is outside the hash.
sqlite3 "$DB" "INSERT INTO tasks (project_id, key, status, created_at)
  SELECT id, 'legacy', 'open', 0 FROM projects WHERE key = 'ledger'"
verified="$(timeline_cli verify)" || fail "a legacy row changed the projection: $verified"

# ------------------------------------------------- mutation outside the service
sqlite3 "$DB" "UPDATE tasks SET status='done' WHERE timeline_id IS NOT NULL"
verify_status=0
verified="$(timeline_cli verify)" || verify_status=$?
[[ "$verify_status" -ne 0 ]] || fail "verify exited 0 after a raw UPDATE: $verified"
assert_eq "$(json_get "$verified" match)" "false" "verify after the edit"
assert_eq "$(json_get "$verified" mismatched_tables)" '["tasks"]' "mismatched tables"
assert_eq "$(json_get "$verified" replayed)" "$head_hash" "the log still replays to the stored hash"
[[ "$(json_get "$verified" current)" != "$head_hash" ]] || fail "live hash did not change"
printf '  verify after raw UPDATE: exit %s, mismatched_tables %s\n' \
  "$verify_status" "$(json_get "$verified" mismatched_tables)"
