#!/bin/zsh -f
# rejections: stale versions, a second production timeline, references into
# another project or an unknown timeline, keys outside scope, dependency cycles,
# unknown operation versions and malformed envelopes are each refused with their
# exact error code, and none of them commits anything.
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

# request <name> <project> <timeline> <scope> <idempotency key> <operations> [expected version]
request() {
  local expected=""
  if [[ -n "${7:-}" ]]; then
    expected=", \"expected_version\": $7"
  fi
  printf '{"request_version": 1, "project": "%s", "actor": {"key": "scenario", "kind": "system"}, "timeline": "%s", "scope": %s, "idempotency_key": "%s"%s, "operations": [%s]}\n' \
    "$2" "$3" "$4" "$5" "$expected" "$6" > "$REQUESTS/$1.json"
}

accept() {
  local output
  output="$(python3 "$CLI" apply --db "$DB" --request "$REQUESTS/$1.json")" || \
    fail "request $1 was refused: $output"
}

# Everything a rejected request could have touched: the log, every timeline's
# head and version, principals, and the task and dependency rows.
snapshot() {
  sqlite3 -readonly "$DB" "
    SELECT 'transactions ' || (SELECT COUNT(*) FROM state_transactions)
      || ' changes ' || (SELECT COUNT(*) FROM state_changes)
      || ' principals ' || (SELECT COUNT(*) FROM principals);
    SELECT p.key || '/' || t.key || ' head_seq ' || t.head_seq || ' version ' || t.version
      FROM timelines t JOIN projects p ON p.id = t.project_id ORDER BY t.id;
    SELECT 'task ' || key || ' ' || COALESCE(status, '-') || ' v' || version
      FROM tasks ORDER BY id;
    SELECT 'dependency ' || task_id || '->' || depends_on_id
      FROM task_dependencies ORDER BY task_id, depends_on_id;"
}

# expect_rejection <label> <code> <request name>: exit 1, the exact
# "error": "<code>" string, and nothing committed.
expect_rejection() {
  local label="$1" code="$2" before output rc=0
  before="$(snapshot)"
  output="$(python3 "$CLI" apply --db "$DB" --request "$REQUESTS/$3.json")" || rc=$?
  assert_eq "$rc" "1" "$label: exit status"
  [[ "$output" == *"\"error\": \"$code\""* ]] || \
    fail "$label: expected \"error\": \"$code\", got $output"
  assert_eq "$(json_get "$output" error)" "$code" "$label: error field"
  assert_eq "$(snapshot)" "$before" "$label: state after rejection"
  printf '  %s: matched "error": "%s"\n' "$label" "$code"
}

# ------------------------------------------------------------------ fixture
#
# Two projects, each with a production timeline. alpha has tasks a and b, beta
# has task x.
: > "$DB"
python3 "$CLI" migrate --db "$DB" --apply >/dev/null
sqlite3 "$DB" "INSERT INTO projects (key, created_at) VALUES ('alpha', 0), ('beta', 0)"

for project in alpha beta; do
  request "$project-timeline" "$project" main '"*"' create-timeline \
    '{"op": "timeline.create", "op_version": 1, "purpose": "production"}'
  accept "$project-timeline"
done
request alpha-tasks alpha main '"*"' create-tasks \
  '{"op": "task.create", "op_version": 1, "key": "a"}, {"op": "task.create", "op_version": 1, "key": "b"}'
accept alpha-tasks
request beta-task beta main '"*"' create-x '{"op": "task.create", "op_version": 1, "key": "x"}'
accept beta-task

# ------------------------------------------------------------------ conflict
request current-version alpha main '"*"' a-ready \
  '{"op": "task.set_status", "op_version": 1, "task": "a", "status": "ready"}' 2
accept current-version
request stale-version alpha main '"*"' a-blocked \
  '{"op": "task.set_status", "op_version": 1, "task": "a", "status": "blocked"}' 2
expect_rejection "stale expected_version" conflict stale-version

request second-production alpha shadow '"*"' shadow-timeline \
  '{"op": "timeline.create", "op_version": 1, "purpose": "production"}'
expect_rejection "second production timeline" conflict second-production

# --------------------------------------------------------- invalid_reference
request other-project alpha main '"*"' touch-x \
  '{"op": "task.set_status", "op_version": 1, "task": "x", "status": "done"}'
expect_rejection "task key from the other project" invalid_reference other-project

request unknown-timeline alpha nowhere '"*"' create-c \
  '{"op": "task.create", "op_version": 1, "key": "c"}'
expect_rejection "unknown timeline" invalid_reference unknown-timeline

# -------------------------------------------------------------- denied_scope
#
# The first operation is in scope and would succeed alone; the second is not,
# so the whole request, including the first, must roll back.
request outside-scope alpha main '{"tasks": ["a"]}' touch-b \
  '{"op": "task.set_status", "op_version": 1, "task": "a", "status": "started"},
   {"op": "task.set_status", "op_version": 1, "task": "b", "status": "started"}'
expect_rejection "task key outside scope" denied_scope outside-scope

# --------------------------------------------------------- cyclic_dependency
request a-after-b alpha main '"*"' a-after-b \
  '{"op": "dependency.add", "op_version": 1, "task": "a", "depends_on": "b"}'
accept a-after-b
request b-after-a alpha main '"*"' b-after-a \
  '{"op": "dependency.add", "op_version": 1, "task": "b", "depends_on": "a"}'
expect_rejection "b depends on a after a depends on b" cyclic_dependency b-after-a
request a-after-a alpha main '"*"' a-after-a \
  '{"op": "dependency.add", "op_version": 1, "task": "a", "depends_on": "a"}'
expect_rejection "a depends on a" cyclic_dependency a-after-a

# ------------------------------------------------ unknown_operation_version
request future-op alpha main '"*"' future-op \
  '{"op": "task.set_status", "op_version": 99, "task": "a", "status": "done"}'
expect_rejection "op_version 99" unknown_operation_version future-op

# ---------------------------------------------------------- invalid_contract
printf '%s\n' '{"request_version": 1, "project": "alpha", "actor": {"key": "scenario", "kind": "system"}, "timeline": "main", "scope": "*", "operations": [{"op": "task.set_status", "op_version": 1, "task": "a", "status": "done"}]}' \
  > "$REQUESTS/no-idempotency-key.json"
expect_rejection "missing idempotency_key" invalid_contract no-idempotency-key

# ------------------------------------- the accepted history is still whole
for project in alpha beta; do
  verified="$(python3 "$CLI" timeline verify --db "$DB" --project "$project" --timeline main)" || \
    fail "$project verify after rejections: $verified"
done
assert_eq "$(json_get "$(python3 "$CLI" timeline log --db "$DB" --project alpha --timeline main)" head_seq)" \
  "4" "alpha head_seq after rejections"
