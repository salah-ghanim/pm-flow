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
TELEMETRY="$REPO_ROOT/template/.agentic/pm_flow/telemetry.py"
WATCH="$REPO_ROOT/template/.agentic/pm_flow/watch.py"
CODEX_EVENTS="$REPO_ROOT/tests/fixtures/codex_events_real.jsonl"
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

COMMAND_WORK="$TEST_ROOT/command-work"
mkdir -p "$COMMAND_WORK/src" "$COMMAND_WORK/.agentic"
git init -q "$COMMAND_WORK"
git -C "$COMMAND_WORK" config user.email t@t
git -C "$COMMAND_WORK" config user.name t
cp -R "$REPO_ROOT/template/.agentic/pm_flow" "$COMMAND_WORK/.agentic/pm_flow"
FLOW="$COMMAND_WORK/.agentic/pm_flow"
rm -rf -- "$FLOW/project"

PROJECT_DIR="$FLOW/legacy-project"
LEDGER="$PROJECT_DIR/runs/cost_ledger.tsv"
DB="$PROJECT_DIR/runs/pm_flow.db"
ALPHA_ONE="$PROJECT_DIR/sections/alpha/cycles/001/first.response.json"
ALPHA_BLANK="$PROJECT_DIR/sections/alpha/cycles/001/blank.response.json"
ALPHA_THREE="$PROJECT_DIR/sections/alpha/cycles/001/third.response.json"
BETA_ONE="$PROJECT_DIR/sections/beta/cycles/001/first.response.json"
BETA_TWO="$PROJECT_DIR/sections/beta/cycles/001/second.response.json"
BETA_EXTRA="$PROJECT_DIR/sections/beta/cycles/002/result.response.json"

mkdir -p "$PROJECT_DIR/runs" \
  "$PROJECT_DIR/project_state" \
  "$PROJECT_DIR/sections/alpha/cycles/001" \
  "$PROJECT_DIR/sections/beta/cycles/001" \
  "$PROJECT_DIR/sections/beta/cycles/002"

printf 'legacy-project\n' > "$FLOW/.project-key"
printf '%s\n' '{"domain":"generic"}' > "$PROJECT_DIR/project.json"
printf '# Legacy Project Task Contract\n\nrules\n' > "$PROJECT_DIR/task_contract.md"
printf '# Plan\n\nexercise the store ledger\n' > \
  "$PROJECT_DIR/project_state/plan.md"
printf 'print("hi")\n' > "$COMMAND_WORK/src/main.py"

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
legacy_alpha="$(python3 "$COST" total "$PROJECT_DIR" "$LEDGER" alpha)"
legacy_beta="$(python3 "$COST" total "$PROJECT_DIR" "$LEDGER" beta)"
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

# Exercise the new arity from a store-free legacy project: it must silently
# import, print only the number, and agree with the legacy arity on this fixture.
rm -f -- "$DB" "$DB-shm" "$DB-wal"
new_total="$(python3 "$COST" total "$PROJECT_DIR")"
new_alpha="$(python3 "$COST" total "$PROJECT_DIR" alpha)"
new_beta="$(python3 "$COST" total "$PROJECT_DIR" beta)"
assert_eq "$new_total" "$before" "new total matches legacy total"
assert_eq "$new_total" "12.1250" "fixture total"
assert_eq "$new_alpha" "$legacy_alpha" "new alpha matches legacy alpha"
assert_eq "$new_alpha" "3.7500" "fixture alpha total"
assert_eq "$new_beta" "$legacy_beta" "new beta matches legacy beta"
assert_eq "$new_beta" "8.3750" "fixture beta total"

rm -- "$LEDGER"
assert_eq "$(python3 "$COST" total "$PROJECT_DIR")" "$new_total" \
  "deleting imported TSV does not change total"
printf '2026-01-02T03:04:05Z\talpha\tdeveloper\tfirst\t999.000000\t%s\n' \
  "$ALPHA_ONE" > "$LEDGER"
assert_eq "$(python3 "$COST" total "$PROJECT_DIR")" "$new_total" \
  "inflating imported TSV does not change total"

# Add a live attempt through the real telemetry commands and real Codex event
# fixture. Its response path is already in attempts, so import must not absorb
# the same envelope a second time.
CODEX_RESPONSE="$PROJECT_DIR/sections/alpha/cycles/002/codex.response.json"
mkdir -p "${CODEX_RESPONSE:h}"
printf '%s\n' '{"pm_backend":"codex","total_cost_usd":0.04}' > "$CODEX_RESPONSE"
run_output="$(python3 "$TELEMETRY" --db "$DB" run-start \
  --project legacy-project --run-key store-ledger-test)"
run_id="$(printf '%s\n' "$run_output" | sed -n 's/^run_id=//p')"
attempt_output="$(python3 "$TELEMETRY" --db "$DB" attempt-start \
  --run "$run_id" --role developer --task alpha --label codex-one --cli codex)"
attempt_id="$(printf '%s\n' "$attempt_output" | sed -n 's/^attempt_id=//p')"
python3 "$TELEMETRY" --db "$DB" attempt-end --attempt "$attempt_id" \
  --response "$CODEX_RESPONSE" --events "$CODEX_EVENTS" --cost-usd 0.04

report="$(python3 "$COST" report "$PROJECT_DIR")"
report_total="$(python3 "$COST" total "$PROJECT_DIR")"
report_alpha="$(python3 "$COST" total "$PROJECT_DIR" alpha)"
report_beta="$(python3 "$COST" total "$PROJECT_DIR" beta)"
[[ "$report" == *$'alpha\t'"$report_alpha"* ]] || \
  fail "report alpha total differs from total command"
[[ "$report" == *$'beta\t'"$report_beta"* ]] || \
  fail "report beta total differs from total command"
[[ "$report" == *$'TOTAL\t'"$report_total"* ]] || \
  fail "report project total differs from total command"
printf '%s\n' "$report" | grep -F \
  $'ATTEMPT\t' | grep -F \
  $'\talpha\tdeveloper\tcodex-one\tcodex\t0.0400\t13937\t5' >/dev/null || \
  fail "report omits live Codex attempt fields"
assert_eq "$(python3 "$COST" import "$PROJECT_DIR")" "imported=0" \
  "live attempt envelope is not re-imported"

flow_report="$(cd "$COMMAND_WORK" && zsh -f "$FLOW/pm_flow.sh" cost)"
assert_eq "$flow_report" "$report" \
  "pm_flow cost matches cost.py report"
printf '%s\n' "$flow_report" | grep -Fx $'TOTAL\t12.1650' >/dev/null || \
  fail "pm_flow cost has the wrong total"
printf '%s\n' "$flow_report" | grep -F $'ATTEMPT\t' | grep -F \
  $'\talpha\tdeveloper\tcodex-one\tcodex\t0.0400\t13937\t5' >/dev/null || \
  fail "pm_flow cost omits live Codex attempt fields"

legacy_report_status=0
python3 "$COST" report "$PROJECT_DIR" "$LEDGER" >/dev/null 2>&1 || \
  legacy_report_status=$?
assert_eq "$legacy_report_status" "2" "legacy report arity exit status"

cmd_cost_body="$(sed -n '/^cmd_cost()/,/^}/p' \
  "$REPO_ROOT/template/.agentic/pm_flow/driver.zsh")"
[[ "$cmd_cost_body" == *'report "$PROJECT_DIR"'* ]] || \
  fail "cmd_cost does not report from PROJECT_DIR"
[[ "$cmd_cost_body" != *cost_ledger_file* ]] || \
  fail "cmd_cost still reads the legacy ledger"

rm -- "$LEDGER"
flow_report_without_ledger="$(cd "$COMMAND_WORK" && \
  zsh -f "$FLOW/pm_flow.sh" cost)"
assert_eq "$flow_report_without_ledger" "$flow_report" \
  "pm_flow cost changes after deleting imported TSV"

WATCH_FLOW="$TEST_ROOT/watch-flow"
mkdir -p "$WATCH_FLOW"
cp "$WATCH" "$WATCH_FLOW/watch.py"
ln -s "$PROJECT_DIR" "$WATCH_FLOW/legacy-project"
watch_output="$(PM_FLOW_PROJECT=legacy-project python3 "$WATCH_FLOW/watch.py")"
watch_total="$(python3 "$COST" total "$PROJECT_DIR")"
watch_spend="$(python3 -c 'import sys; print(f"${float(sys.argv[1]):.2f}")' \
  "$watch_total")"
[[ "$watch_output" == *"$watch_spend"* ]] || fail "watch omits store spend"
[[ "$watch_output" == *"13937"* ]] || fail "watch omits Codex input tokens"

mkdir -p "$WATCH_FLOW/empty-project"
PM_FLOW_PROJECT=empty-project python3 "$WATCH_FLOW/watch.py" >/dev/null
[[ ! -e "$WATCH_FLOW/empty-project/runs/pm_flow.db" ]] || \
  fail "watch created a store for an empty project"
assert_eq "$(grep -c cost_ledger "$WATCH" || true)" "0" \
  "watch has no legacy ledger references"

printf 'store ledger tests passed\n'
