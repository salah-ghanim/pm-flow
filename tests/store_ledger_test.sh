#!/bin/zsh -f
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1

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

before="12.1250"
legacy_alpha="3.7500"
legacy_beta="8.3750"
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
legacy_total_status=0
python3 "$COST" total "$PROJECT_DIR" "$LEDGER" >/dev/null 2>&1 || \
  legacy_total_status=$?
assert_eq "$legacy_total_status" "2" "legacy total arity exit status"

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

set_config() {
  python3 -c '
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
raw = p.read_text().replace(chr(34) + "{{DOMAIN}}" + chr(34), chr(34) + "generic" + chr(34))
c = json.loads(raw)
section, key = sys.argv[2].split(".")
value = sys.argv[3]
c.setdefault(section, {})[key] = float(value) if "." in value else int(value)
p.write_text(json.dumps(c, indent=2))
' "$FLOW/config.json" "$1" "$2"
}

cat > "$FLOW/agent_exec.sh" <<'STUB'
#!/bin/zsh -f
set -euo pipefail
OUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) OUT="$2"; shift 2 ;;
    --heartbeat|--label|--prompt-file|--seat) shift 2 ;;
    *) shift ;;
  esac
done
python3 -c '
import json, sys
from pathlib import Path
Path(sys.argv[1]).parent.mkdir(parents=True, exist_ok=True)
Path(sys.argv[1]).write_text(json.dumps({"is_error": False, "result": sys.argv[2],
    "failure_reason": "none", "total_cost_usd": 0.5}))
' "$OUT" "${PM_FLOW_STUB:-}"
STUB
chmod +x "$FLOW/agent_exec.sh" "$FLOW/pm_flow.sh"

brief() {
  printf '## Objective\n\n- %s\n\n## Scope\n\n- one thing\n\n## Priority\n\n- must-have: without it there is no product\n\n## Owned paths\n\n- `%s`\n\n## Dependencies\n\n- None.\n\n## Acceptance\n\n- `.venv/bin/python -m pytest -q` exits 0\n\n## Rejection conditions\n\n- nothing runs\n' \
    "$1" "$2"
}

brief dispatch-check "src/" > "$TEST_ROOT/dispatch-brief.md"
(cd "$COMMAND_WORK" && "$FLOW/pm_flow.sh" init-section dispatch-check \
  --file "$TEST_ROOT/dispatch-brief.md" >/dev/null)
git -C "$COMMAND_WORK" add -A >/dev/null
git -C "$COMMAND_WORK" commit -qm fixture

ANALYSIS='## Where the section stands

- The store-backed dispatch is under test.

## What is blocking it

- Nothing.

## What I would do next and why

- Verify the cost and budget behavior.

## What I cannot settle myself

- Nothing.'

attempts_before="$(cd "$COMMAND_WORK" && "$FLOW/pm_flow.sh" cost | \
  grep -c '^ATTEMPT' || true)"
total_before="$(python3 "$COST" total "$PROJECT_DIR")"
assert_eq "$attempts_before" "7" "pre-dispatch attempt count"
assert_eq "$total_before" "12.1650" "pre-dispatch store total"

(cd "$COMMAND_WORK" && PM_FLOW_STUB="$ANALYSIS" \
  "$FLOW/pm_flow.sh" section-analysis dispatch-check >/dev/null)

runs_listing="$(ls "$PROJECT_DIR/runs")"
[[ "$runs_listing" == *pm_flow.db* ]] || fail "dispatch did not retain pm_flow.db"
[[ "$runs_listing" != *cost_ledger.tsv* ]] || fail "dispatch wrote cost_ledger.tsv"
git -C "$COMMAND_WORK" status --porcelain | grep 'runs/' >/dev/null && \
  fail "dispatch dirtied a path under runs/"

after_report="$(cd "$COMMAND_WORK" && "$FLOW/pm_flow.sh" cost)"
attempts_after="$(printf '%s\n' "$after_report" | grep -c '^ATTEMPT' || true)"
assert_eq "$attempts_after" "$(( attempts_before + 1 ))" \
  "dispatch adds exactly one attempt"
printf '%s\n' "$after_report" | awk -F'\t' \
  '$1 == "ATTEMPT" && $5 == "analysis dispatch-check" && $7 == "0.5000" {found=1} END {exit !found}' || \
  fail "dispatch attempt does not carry its 0.5000 cost"
assert_eq "$(python3 "$COST" total "$PROJECT_DIR")" "12.6650" \
  "dispatch raises the store total"

set_config budget.max_usd 12.66
budget_output="$(cd "$COMMAND_WORK" && PM_FLOW_STUB="$ANALYSIS" \
  "$FLOW/pm_flow.sh" section-analysis dispatch-check 2>&1 || true)"
[[ "$budget_output" == *"project budget exhausted"* ]] || \
  fail "store-backed budget did not refuse the next dispatch"
assert_eq "$(cd "$COMMAND_WORK" && "$FLOW/pm_flow.sh" cost | \
  grep -c '^ATTEMPT' || true)" "$attempts_after" \
  "budget refusal does not add an attempt"
[[ ! -e "$LEDGER" ]] || fail "budget refusal depended on a legacy TSV"

installed() {
  ( cd "$COMMAND_WORK" && PYTHONPATH="$REPO_ROOT/src" PM_FLOW_ENGINE_ROOT="$FLOW" \
    python3 -c 'import sys; from pm_flow.cli import main; sys.exit(main())' "$@" )
}

# Exercise a fresh legacy project through the console-script entry point. The
# expected total is independent arithmetic over the TSV and envelope-only file.
PROJECT2="$FLOW/legacy-two"
PROJECT2_LEDGER="$PROJECT2/runs/cost_ledger.tsv"
PROJECT2_DB="$PROJECT2/runs/pm_flow.db"
PROJECT2_ALPHA_ONE="$PROJECT2/sections/alpha/cycles/001/first.response.json"
PROJECT2_ALPHA_BLANK="$PROJECT2/sections/alpha/cycles/001/blank.response.json"
PROJECT2_BETA_ONE="$PROJECT2/sections/beta/cycles/001/first.response.json"
PROJECT2_EXTRA="$PROJECT2/sections/beta/cycles/002/extra.response.json"
mkdir -p "$PROJECT2/runs" \
  "$PROJECT2/project_state" \
  "$PROJECT2/sections/alpha/cycles/001" \
  "$PROJECT2/sections/beta/cycles/001" \
  "$PROJECT2/sections/beta/cycles/002"
printf '%s\n' '{"domain":"generic"}' > "$PROJECT2/project.json"
printf '# Legacy Two Task Contract\n\nrules\n' > "$PROJECT2/task_contract.md"
printf '# Plan\n\nexercise installed legacy import\n' > \
  "$PROJECT2/project_state/plan.md"
printf '%s\n' '{"total_cost_usd": 7.777}' > "$PROJECT2_ALPHA_BLANK"
printf '%s\n' '{"total_cost_usd": 0.625}' > "$PROJECT2_EXTRA"
{
  printf '2026-02-02T03:04:05Z\talpha\tdeveloper\tfirst\t1.250000\t%s\n' \
    "$PROJECT2_ALPHA_ONE"
  printf '2026-02-02T03:05:05Z\talpha\treviewer\tblank\t\t%s\n' \
    "$PROJECT2_ALPHA_BLANK"
  printf '2026-02-02T03:06:05Z\tbeta\tdeveloper\tfirst\t2.500000\t%s\n' \
    "$PROJECT2_BETA_ONE"
} > "$PROJECT2_LEDGER"
[[ ! -e "$PROJECT2_DB" ]] || fail "legacy-two unexpectedly starts with a store"

project2_tsv_total="$(awk -F'\t' '{s+=$5} END {printf "%.4f", s}' \
  "$PROJECT2_LEDGER")"
project2_extra_total="$(python3 -c \
  'import json,sys; print(json.load(open(sys.argv[1]))["total_cost_usd"])' \
  "$PROJECT2_EXTRA")"
project2_expected="$(awk -v tsv="$project2_tsv_total" \
  -v extra="$project2_extra_total" 'BEGIN {printf "%.4f", tsv + extra}')"
project2_first="$TEST_ROOT/legacy-two-first.txt"
project2_second="$TEST_ROOT/legacy-two-second.txt"
installed --project legacy-two cost > "$project2_first"
installed --project legacy-two cost > "$project2_second"
grep -Fx $'TOTAL\t'"$project2_expected" "$project2_first" >/dev/null || \
  fail "installed legacy-two cost differs from independent legacy arithmetic"
cmp -s "$project2_first" "$project2_second" || \
  fail "repeated installed legacy-two cost output is not byte-identical"
assert_eq "$(python3 "$COST" import "$PROJECT2")" "imported=0" \
  "installed legacy-two cost import is idempotent"

# Live telemetry may use a different projects.key from the importer's basename.
# A per-project store reader must still include the row and resolve its task.
mixed_run_output="$(python3 "$TELEMETRY" --db "$PROJECT2_DB" run-start \
  --project other-key --run-key mixed-project-key)"
mixed_run_id="$(printf '%s\n' "$mixed_run_output" | sed -n 's/^run_id=//p')"
mixed_attempt_output="$(python3 "$TELEMETRY" --db "$PROJECT2_DB" attempt-start \
  --run "$mixed_run_id" --role developer --task alpha --label mixed-key --cli claude)"
mixed_attempt_id="$(printf '%s\n' "$mixed_attempt_output" | \
  sed -n 's/^attempt_id=//p')"
python3 "$TELEMETRY" --db "$PROJECT2_DB" attempt-end \
  --attempt "$mixed_attempt_id" --cost-usd 0.25 \
  --response "$PROJECT2/runs/mixed-key-does-not-exist.response.json"
project2_mixed_report="$(installed --project legacy-two cost)"
project2_mixed_expected="$(awk -v total="$project2_expected" \
  'BEGIN {printf "%.4f", total + 0.25}')"
grep -Fx $'TOTAL\t'"$project2_mixed_expected" <<< "$project2_mixed_report" \
  >/dev/null || fail "mixed projects.key row does not raise the total by 0.2500"
printf '%s\n' "$project2_mixed_report" | awk -F'\t' \
  '$1 == "ATTEMPT" && $3 == "alpha" && $5 == "mixed-key" && $7 == "0.2500" {found=1} END {exit !found}' || \
  fail "mixed projects.key row is not reported under alpha"

# Reopen spending and dispatch through pm_flow.cli.main, keeping the copied
# engine's stub in force for the whole invocation.
set_config budget.max_usd 100
installed_before_report="$(installed cost)"
installed_attempts_before="$(printf '%s\n' "$installed_before_report" | \
  grep -c '^ATTEMPT' || true)"
installed_priced_before="$(printf '%s\n' "$installed_before_report" | \
  awk -F'\t' '$1 == "ATTEMPT" && $7 == "0.5000" {n++} END {print n+0}')"
PM_FLOW_STUB="$ANALYSIS" installed section-analysis dispatch-check >/dev/null
installed_after_report="$(installed cost)"
installed_attempts_after="$(printf '%s\n' "$installed_after_report" | \
  grep -c '^ATTEMPT' || true)"
installed_priced_after="$(printf '%s\n' "$installed_after_report" | \
  awk -F'\t' '$1 == "ATTEMPT" && $7 == "0.5000" {n++} END {print n+0}')"
assert_eq "$installed_attempts_after" "$(( installed_attempts_before + 1 ))" \
  "installed dispatch adds exactly one attempt"
assert_eq "$installed_priced_after" "$(( installed_priced_before + 1 ))" \
  "installed dispatch adds exactly one 0.5000 attempt"
printf '%s\n' "$installed_after_report" | grep -F $'ATTEMPT\t' | grep -F \
  $'\talpha\tdeveloper\tcodex-one\tcodex\t0.0400\t13937\t5' >/dev/null || \
  fail "installed cost omits live Codex attempt fields"

runs_listing="$(ls "$PROJECT_DIR/runs")"
[[ "$runs_listing" == *pm_flow.db* ]] || \
  fail "installed dispatch did not retain pm_flow.db"
[[ "$runs_listing" != *cost_ledger.tsv* ]] || \
  fail "installed dispatch wrote cost_ledger.tsv"
git -C "$COMMAND_WORK" status --porcelain | grep 'runs/' >/dev/null && \
  fail "installed dispatch dirtied a path under runs/"

assert_eq "$(python3 "$COST" import "$PROJECT_DIR")" "imported=0" \
  "installed dispatch envelope is not re-imported"
duplicate_response_paths="$(python3 -c '
import sqlite3, sys
connection = sqlite3.connect(sys.argv[1])
rows = connection.execute(
    "SELECT response_path, COUNT(*) FROM attempts "
    "WHERE response_path IS NOT NULL GROUP BY response_path"
)
print("\\n".join(path for path, count in rows if count > 1))
' "$DB")"
assert_eq "$duplicate_response_paths" "" \
  "no response_path is represented more than once"
python3 -c '
import sqlite3, sys
sys.path.insert(0, sys.argv[3])
import cost
connection = sqlite3.connect(sys.argv[1])
recorded = {
    row[0] for row in connection.execute(
        "SELECT response_path FROM attempts "
        "WHERE status != ? AND response_path IS NOT NULL", ("imported",)
    )
}
discovered = {str(path) for path in cost.response_files(sys.argv[2])}
missing = sorted(recorded - discovered)
if missing:
    print("\\n".join(missing))
    raise SystemExit(1)
' "$DB" "$PROJECT_DIR" "$FLOW" || \
  fail "live response_path values differ from cost.response_files strings"

set_config budget.max_usd 12.66
installed_budget_stdout="$TEST_ROOT/installed-budget.stdout"
installed_budget_stderr="$TEST_ROOT/installed-budget.stderr"
installed_budget_status=0
PM_FLOW_STUB="$ANALYSIS" installed section-analysis dispatch-check \
  > "$installed_budget_stdout" 2> "$installed_budget_stderr" || \
  installed_budget_status=$?
[[ "$installed_budget_status" -ne 0 ]] || \
  fail "installed budget refusal returned success"
grep -F "project budget exhausted" "$installed_budget_stderr" >/dev/null || \
  fail "installed command did not report project budget exhaustion"
assert_eq "$(installed cost | grep -c '^ATTEMPT' || true)" \
  "$installed_attempts_after" \
  "installed budget refusal does not add an attempt"
[[ ! -e "$LEDGER" ]] || \
  fail "installed budget refusal depended on a legacy TSV"
grep -F "cost.py total reported nothing" "$installed_budget_stderr" >/dev/null && \
  fail "healthy store reader entered spent_usd fallback"

assert_eq "$(grep -c cost_ledger_file \
  "$REPO_ROOT/template/.agentic/pm_flow/driver.zsh" || true)" "0" \
  "driver has no cost_ledger_file reference"
legacy_refs="$(grep -rl cost_ledger "$REPO_ROOT/template" || true)"
assert_eq "$legacy_refs" "$REPO_ROOT/template/.agentic/pm_flow/cost.py" \
  "only the importer references cost_ledger"

printf 'store ledger tests passed\n'
