#!/bin/zsh -f
set -euo pipefail

for name in ${(k)parameters[(I)PM_FLOW_*]}; do
  unset "$name"
done
# `fail` is defined further down, once TEST_ROOT exists; this check runs first.
[[ -z "${PM_FLOW_PROJECT:-}${PM_FLOW_ROOT:-}${PM_FLOW_ENGINE_ROOT:-}${PM_FLOW_REPO_ROOT:-}${PM_FLOW_FLOW_DIR:-}" ]] || {
  printf 'FAIL: a PM_FLOW_* override survived into the test environment\n' >&2
  exit 1
}

REPO_ROOT="$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)"
COST="$REPO_ROOT/template/.agentic/pm_flow/cost.py"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/store-ledger-test.XXXXXX")"
TEST_ROOT="$(cd -P "$TEST_ROOT" && pwd -P)"
case "$TEST_ROOT" in
  */store-ledger-test.*) ;;
  *) printf 'unsafe test temp directory: %s\n' "$TEST_ROOT" >&2; exit 1 ;;
esac

cleanup() {
  if [[ -n "${TEST_ROOT:-}" && -d "$TEST_ROOT" && \
        "$(basename "$TEST_ROOT")" == store-ledger-test.* ]]; then
    rm -rf -- "$TEST_ROOT"
  fi
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  [[ "$actual" == "$expected" ]] || \
    fail "$label: expected '$expected', got '$actual'"
}

PROJECT_DIR="$TEST_ROOT/legacy-project"
LEDGER="$PROJECT_DIR/runs/cost_ledger.tsv"
DB="$PROJECT_DIR/runs/pm_flow.db"
ALPHA_ONE="$PROJECT_DIR/sections/alpha/cycles/001/first.response.json"
ALPHA_BLANK="$PROJECT_DIR/sections/alpha/cycles/001/blank.response.json"
ALPHA_THREE="$PROJECT_DIR/sections/alpha/cycles/001/third.response.json"
BETA_ONE="$PROJECT_DIR/sections/beta/cycles/001/first.response.json"
BETA_TWO="$PROJECT_DIR/sections/beta/cycles/001/second.response.json"
BETA_EXTRA="$PROJECT_DIR/sections/beta/cycles/002/result.response.json"

mkdir -p "$PROJECT_DIR/runs" \
  "$PROJECT_DIR/sections/alpha/cycles/001" \
  "$PROJECT_DIR/sections/beta/cycles/001" \
  "$PROJECT_DIR/sections/beta/cycles/002"

printf '%s\n' '{"total_cost_usd": 7.777}' > "$ALPHA_BLANK"
printf '%s\n' '{"total_cost_usd": 99.0}' > "$BETA_ONE"
printf '%s\n' '{"total_cost_usd": 0.625}' > "$BETA_EXTRA"

{
  printf '2026-01-02T03:04:05Z\talpha\tdeveloper\tfirst\t1.250000\t%s\n' "$ALPHA_ONE"
  printf '2026-01-02T03:05:05Z\talpha\treviewer\tblank\t\t%s\n' "$ALPHA_BLANK"
  printf '2026-01-02T03:06:05Z\talpha\tdeveloper\tthird\t2.500000\t%s\n' "$ALPHA_THREE"
  printf '2026-01-02T03:07:05Z\tbeta\tdeveloper\tfirst\t3.750000\t%s\n' "$BETA_ONE"
  printf '2026-01-02T03:08:05Z\tbeta\treviewer\tsecond\t4.000000\t%s\n' "$BETA_TWO"
} > "$LEDGER"

before="$(python3 "$COST" total "$PROJECT_DIR" "$LEDGER")"
first_import="$(python3 "$COST" import "$PROJECT_DIR")"
assert_eq "$first_import" "imported=6" "first import count"

store_total="$(python3 -c \
  'import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); value=c.execute("SELECT SUM(cost_usd) FROM attempts").fetchone()[0]; print(f"{(value or 0):.4f}")' \
  "$DB")"
assert_eq "$store_total" "$before" "store total matches legacy total"

blank_is_null="$(python3 -c \
  'import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); print(c.execute("SELECT cost_usd IS NULL FROM attempts WHERE response_path = ?", (sys.argv[2],)).fetchone()[0])' \
  "$DB" "$ALPHA_BLANK")"
assert_eq "$blank_is_null" "1" "blank TSV cost remains NULL"

alpha_count="$(python3 -c \
  'import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); print(c.execute("SELECT COUNT(*) FROM attempts a JOIN tasks t ON t.id = a.task_id WHERE t.key = ?", ("alpha",)).fetchone()[0])' \
  "$DB")"
assert_eq "$alpha_count" "3" "alpha task resolution"

count_before="$(python3 -c \
  'import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); print(c.execute("SELECT COUNT(*) FROM attempts").fetchone()[0])' \
  "$DB")"
second_import="$(python3 "$COST" import "$PROJECT_DIR")"
count_after="$(python3 -c \
  'import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); print(c.execute("SELECT COUNT(*) FROM attempts").fetchone()[0])' \
  "$DB")"
assert_eq "$second_import" "imported=0" "second import count"
assert_eq "$count_after" "$count_before" "second import row count"

dispatch_counts="$(python3 -c \
  'import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); print(",".join(str(row[0]) for row in c.execute("SELECT COUNT(*) FROM attempts GROUP BY response_path ORDER BY response_path")))' \
  "$DB")"
assert_eq "$dispatch_counts" "1,1,1,1,1,1" "one attempt per response path"

printf 'store ledger tests passed\n'
