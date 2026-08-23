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
ENGINE="$REPO_ROOT/template/.agentic/pm_flow"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-usage-test.XXXXXX")"
TEST_ROOT="$(cd -P "$TEST_ROOT" && pwd -P)"
case "$TEST_ROOT" in
  */codex-usage-test.*) ;;
  *) printf 'unsafe test temp directory: %s\n' "$TEST_ROOT" >&2; exit 1 ;;
esac

cleanup() {
  if [[ -n "${TEST_ROOT:-}" && -d "$TEST_ROOT" && \
        "$(basename "$TEST_ROOT")" == codex-usage-test.* ]]; then
    rm -rf -- "$TEST_ROOT"
  fi
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local value="$1"
  local expected="$2"
  local label="$3"
  [[ "$value" == *"$expected"* ]] || fail "$label: expected to find '$expected'"
}

assert_not_contains() {
  local value="$1"
  local unexpected="$2"
  local label="$3"
  [[ "$value" != *"$unexpected"* ]] || fail "$label: did not expect '$unexpected'"
}

assert_file_contains() {
  local path="$1"
  local expected="$2"
  local label="$3"
  [[ -f "$path" ]] || fail "$label: missing file $path"
  assert_contains "$(/bin/cat "$path")" "$expected" "$label"
}

response_field() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' \
    "$1" "$2"
}

mkdir "$TEST_ROOT/bin"
{
  printf '#!/bin/zsh -f\n'
  printf 'set -euo pipefail\n'
  printf 'REPO_ROOT=%q\n' "$REPO_ROOT"
  printf 'TEST_ROOT=%q\n' "$TEST_ROOT"
  /bin/cat <<'STUB'

prompt="${@[-1]}"
out=""
while [[ $# -gt 0 ]]; do
  [[ "$1" == "-o" ]] && { out="$2"; shift 2; continue; }
  shift
done

retire_workplan_scaffold() {
  local wp
  wp="$(printf '%s\n' "$prompt" | sed -n 's/^- *`\{0,1\}\([^`]*workplan\.md\)`\{0,1\} *$/\1/p' | head -n 1)"
  [[ -n "$wp" ]] || return 0
  [[ "$wp" == /* ]] || wp="${PROJECT_ROOT:-$PWD}/$wp"
  [[ -f "$wp" ]] || return 0
  grep -v 'pm-flow-workplan-template' "$wp" > "$wp.tmp" && mv "$wp.tmp" "$wp"
}

emit_portfolio_review() {
  local verdicts="" section_dir key lifecycle
  local project_key
  project_key="$(head -n 1 "$PROJECT_ROOT/.agentic/pm_flow/.project-key" 2>/dev/null)"
  for section_dir in "$PROJECT_ROOT"/.agentic/pm_flow/${project_key:-*}/sections/*(/N); do
    key="${section_dir:t}"
    [[ "$key" != .* ]] || continue
    lifecycle="$(head -n 1 "$section_dir/status.txt" 2>/dev/null)"
    case "$lifecycle" in done|cancelled) continue ;; esac
    verdicts+="- $key: CONTINUE still on the shortest path"$'\n'
  done
  print -r -- "## Standing
Every live section is doing the work its brief asked for.

## Verdicts
${verdicts}
## Plan structure
- unstarted dependency: CLEAR
- unreachable section: CLEAR
- must-have inflation: CLEAR
- linear-chain risk: CLEAR

## Shortest path
Finish the sections already in flight; nothing else is on the critical path.

## Decision
ON_TRACK - the plan and the work still agree"
}

role_answer() {
  case "$prompt" in
    *"Task: review the portfolio"*)
      emit_portfolio_review ;;
    *"Task: scope the next assignment"*)
      retire_workplan_scaffold
      if [[ -f "$PM_DONE_FLAG" ]]; then
        print -r -- "## Where the section stands
Done.

## Assignment
Not applicable.

## Acceptance
Not applicable.

## Rejection conditions
Not applicable.

## Decision
COMPLETE - acceptance met"
      else
        touch "$PM_DONE_FLAG"
        print -r -- "## Where the section stands
Starting.

## Workplan task
T1

## Assignment
Build it.

## Acceptance
Tests pass.

## Rejection conditions
Drift.

## Decision
ASSIGN - first piece"
      fi ;;
    *"Task: implement this assignment"*)
      print -r -- "## What I changed
Built it.

## What I reused or restructured
Harness.

## Validation
Tests passed.

## What I could not do
Nothing.

## Status
DELIVERED" ;;
    *"Task: review a developer result"*)
      print -r -- "## Assessment
Good.

## Obstruction
NONE - the work was judged on its merits.

## Drift review
None.

## Evidence check
Output present.

## Risks
Low.

## Decision
GO - accepted" ;;
    *"Task: write the section handoff"*)
      print -r -- "## Outcome
Widget works.

## Decisions
Reused harness.

## Interfaces
Widget API.

## Risks
None.

## What is unproven
None; every claim above was demonstrated.

## Next action
Integrate." ;;
    *)
      print -r -- "## Decision
ASSIGN - fallback" ;;
  esac
}

mode="$(head -n 1 "$TEST_ROOT/codex-mode" 2>/dev/null || print replay)"
case "$mode" in
  replay)
    /bin/cat "$REPO_ROOT/tests/fixtures/codex_events_real.jsonl"
    role_answer > "$out"
    ;;
  slow-events)
    while IFS= read -r line; do
      print -r -- "$line"
      sleep 1
    done < "$REPO_ROOT/tests/fixtures/codex_events_real.jsonl"
    sleep 1
    role_answer > "$out"
    ;;
  silent)
    sleep 8
    ;;
  fail-events|fail-stderr)
    print -r -- '{"type":"item.completed","item":{"id":"item_failure","type":"agent_message","text":"provider returned 429 too many requests; rate limit hit; request refused"}}'
    /usr/bin/tail -n 1 "$REPO_ROOT/tests/fixtures/codex_events_real.jsonl"
    [[ "$mode" != "fail-stderr" ]] || print -u2 "Error: rate limit exceeded"
    exit 1
    ;;
  *)
    print -u2 "unknown codex test mode: $mode"
    exit 2
    ;;
esac
STUB
} > "$TEST_ROOT/bin/codex"
chmod +x "$TEST_ROOT/bin/codex"

typeset -ga PM
PROJ=""
FLOW=""
PROJECT=""
SECTION=""
DB=""
DRIVER_DONE_FLAG=""

configure_project() {
  local config="$1"
  python3 - "$config" <<'PYCFG'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
config = json.loads(path.read_text())
binding = {"cli": "codex", "model": "gpt-stub", "difficulty": "low"}
for role in ("cpo", "pm", "developer", "10x_developer"):
    config["roles"][role] = dict(binding)
config["roles"]["consultant"] = [dict(binding), dict(binding)]
config["supervision"] = {
    "heartbeat_stall_seconds": 3,
    "silent_stall_seconds": 3,
    "max_attempts": 1,
    "max_step_claims": 6,
    "retry_backoff_seconds": 1,
    "usage_limit_pause_seconds": 1,
}
config["escalation"] = {
    "failures_before_consultant": 9,
    "max_rescue_attempts": 1,
}
path.write_text(json.dumps(config, indent=2) + "\n")
PYCFG
}

install_project() {
  local project_root="$1"
  local selected_engine="$2"
  local project_key
  mkdir "$project_root"
  "$REPO_ROOT/install.sh" "$project_root" --name "Codex Usage" > /dev/null
  configure_project "$project_root/.agentic/pm_flow/config.json"
  project_key="$(head -n 1 "$project_root/.agentic/pm_flow/.project-key")"

  PROJ="$project_root"
  FLOW="$PROJ/.agentic/pm_flow"
  PROJECT="$FLOW/$project_key"
  SECTION="$PROJECT/sections/widget"
  DB="$PROJECT/runs/pm_flow.db"
  DRIVER_DONE_FLAG="$project_root/driver-complete.flag"
  PM=(env PM_FLOW_ENGINE_ROOT="$selected_engine" PM_FLOW_FLOW_DIR="$FLOW" \
      PM_FLOW_REPO_ROOT="$PROJ" PATH="$TEST_ROOT/bin:$PATH" \
      zsh -f "$selected_engine/pm_flow.sh")

  "${PM[@]}" init-section widget <<'SECTIONBRIEF' > /dev/null
## Objective

- Build the widget.

## Scope

- The widget only.

## Priority

- must-have: the product cannot ship without it

## Owned paths

- `src/widget/**`

## Dependencies

- None.

## Acceptance

- Widget tests pass.

## Rejection conditions

- Scope drift.
SECTIONBRIEF
}

drain_project_work() {
  local guard=0
  while [[ "$("${PM[@]}" status)" == *"portfolio review due"* ]]; do
    (( guard += 1 ))
    (( guard <= 8 )) || fail "the portfolio review queue would not drain"
    PM_DONE_FLAG="$DRIVER_DONE_FLAG" "${PM[@]}" tick > /dev/null 2>&1
  done
}

driver_tick() {
  drain_project_work
  PM_DONE_FLAG="$DRIVER_DONE_FLAG" "${PM[@]}" tick
}

read_attempts() {
  local selected_engine="$1"
  local db="$2"
  python3 - "$selected_engine" "$db" <<'PY'
import sys

sys.path.insert(0, sys.argv[1])
import store

columns = (
    "id", "role_key", "cli", "status", "failure_reason", "input_tokens",
    "output_tokens", "cache_read_tokens", "reasoning_tokens", "total_tokens",
)
connection = store.connect(sys.argv[2])
for row in connection.execute(
    "SELECT " + ",".join(columns) + " FROM attempts ORDER BY id"
):
    print("|".join(str(row[column]) for column in columns))
connection.close()
PY
}

install_project "$TEST_ROOT/cu repo" "$ENGINE"
printf 'store=%s\n' "$DB"
CYCLE="$SECTION/cycles/001"
HEARTBEAT="$CYCLE/heartbeat.txt"

printf 'replay\n' > "$TEST_ROOT/codex-mode"
scope_out="$(driver_tick)"
assert_contains "$scope_out" "scope 001 -> ASSIGN" "the first dispatch scopes the section"
assert_not_contains "$scope_out" "UNPARSED" "the first scope assignment parses"
printf '%s\n' "$scope_out"

printf 'silent\n' > "$TEST_ROOT/codex-mode"
silent_rc=0
silent_out="$(driver_tick 2>&1)" || silent_rc=$?
(( silent_rc != 0 )) || fail "the silent control was not terminated"
assert_file_contains "$HEARTBEAT" "stalled with no progress for 3s" \
  "the silent control records the active stall budget"
stall_count_before="$(/usr/bin/grep -c 'stalled with no progress' "$HEARTBEAT")"
rm -f "$SECTION/quarantine.txt"
printf 'PASS: silent Codex dispatch was classified as a 3s stall\n'

printf 'slow-events\n' > "$TEST_ROOT/codex-mode"
slow_started="$(date +%s)"
slow_out="$(driver_tick)"
slow_elapsed=$(( $(date +%s) - slow_started ))
(( slow_elapsed >= 5 )) || fail "event-only dispatch finished too quickly to prove liveness (${slow_elapsed}s)"
assert_contains "$slow_out" "action=develop" "the event-only dispatch develops the section"
stall_count_after="$(/usr/bin/grep -c 'stalled with no progress' "$HEARTBEAT")"
[[ "$stall_count_after" == "$stall_count_before" ]] || \
  fail "event-stream activity added a stalled heartbeat line"
RESULT_EVENTS="$CYCLE/result.response.events.jsonl"
cmp -s "$RESULT_EVENTS" "$REPO_ROOT/tests/fixtures/codex_events_real.jsonl" || \
  fail "the slow dispatch did not preserve the tracked fixture byte-for-byte"
printf 'PASS: event-only dispatch ran %ss past the 3s budget; result.response.events.jsonl is byte-identical to the fixture\n' \
  "$slow_elapsed"

printf 'fail-events\n' > "$TEST_ROOT/codex-mode"
fail_events_rc=0
fail_events_out="$(driver_tick 2>&1)" || fail_events_rc=$?
(( fail_events_rc != 0 )) || fail "the event-only failure unexpectedly succeeded"
REVIEW_RESPONSE="$CYCLE/review.response.json"
REVIEW_EVENTS="$CYCLE/review.response.events.jsonl"
[[ "$(response_field "$REVIEW_RESPONSE" failure_reason)" == "unknown" ]] || \
  fail "failure-looking event text changed the response classification"
/bin/cp "$REVIEW_EVENTS" "$TEST_ROOT/fail-events.jsonl"
rm -f "$SECTION/quarantine.txt"

printf 'fail-stderr\n' > "$TEST_ROOT/codex-mode"
fail_stderr_rc=0
fail_stderr_out="$(driver_tick 2>&1)" || fail_stderr_rc=$?
(( fail_stderr_rc != 0 )) || fail "the stderr failure unexpectedly succeeded"
[[ "$(response_field "$REVIEW_RESPONSE" failure_reason)" == "usage_limit" ]] || \
  fail "stderr did not classify the failure as a usage limit"
cmp -s "$TEST_ROOT/fail-events.jsonl" "$REVIEW_EVENTS" || \
  fail "the event-only and stderr failures emitted different event streams"
rm -f "$SECTION/quarantine.txt"
printf 'PASS: identical failure event streams stored unknown from events and usage_limit from stderr\n'

printf 'replay\n' > "$TEST_ROOT/codex-mode"
review_out="$(driver_tick)"
assert_contains "$review_out" "review 001 -> GO" "the final review succeeds"

attempt_rows="$(read_attempts "$ENGINE" "$DB")"
printf '%s\n' "$attempt_rows"
assert_contains "$attempt_rows" "1|pm|codex|ok|None|13937|5|12032|0|13942" \
  "the replay scope row stores the fixture usage"
assert_contains "$attempt_rows" "2|developer|codex|error|stall|" \
  "the silent control row stores a stall"
assert_contains "$attempt_rows" "3|developer|codex|ok|None|13937|5|12032|0|13942" \
  "the event-only developer row stores the fixture usage"
assert_contains "$attempt_rows" "4|pm|codex|error|unknown|" \
  "event text is not used for failure classification"
assert_contains "$attempt_rows" "5|pm|codex|error|usage_limit|" \
  "stderr is used for failure classification"
assert_contains "$attempt_rows" "6|pm|codex|ok|None|13937|5|12032|0|13942" \
  "the successful review row stores the fixture usage"
printf 'PASS: replay stored Codex rows with fixture tokens 13937|5|12032|0|13942\n'

NO_END_ENGINE="$TEST_ROOT/engine-no-end"
/bin/cp -R "$ENGINE" "$NO_END_ENGINE"
chmod +x "$NO_END_ENGINE/agent_exec.sh"
sed -i.bak '/^  telemetry_end_attempt "\$response_json" "\$output_md" ok/d' \
  "$NO_END_ENGINE/driver.zsh"
if cmp -s "$ENGINE/driver.zsh" "$NO_END_ENGINE/driver.zsh"; then
  fail "the telemetry_end_attempt mutation did not change driver.zsh"
fi
install_project "$TEST_ROOT/no-end repo" "$NO_END_ENGINE"
printf 'replay\n' > "$TEST_ROOT/codex-mode"
no_end_out="$(driver_tick)"
assert_contains "$no_end_out" "action=scope" "the no-end mutation runs the scope step"
no_end_rows="$(read_attempts "$NO_END_ENGINE" "$DB")"
printf '%s\n' "$no_end_rows"
assert_contains "$no_end_rows" "|pm|None|running|None|None|None|None|None|None" \
  "removing telemetry_end_attempt leaves tokens absent"
assert_not_contains "$no_end_rows" "|pm|codex|ok|" \
  "removing telemetry_end_attempt must not leave an ok row"
printf 'PASS: mutation without telemetry_end_attempt left Codex tokens absent and status not ok\n'

WRONG_KEY_ENGINE="$TEST_ROOT/engine-wrong-key"
/bin/cp -R "$ENGINE" "$WRONG_KEY_ENGINE"
chmod +x "$WRONG_KEY_ENGINE/agent_exec.sh"
sed -i.bak 's/for key in ("total_token_usage", "usage"):/for key in ("total_token_usage",):/' \
  "$WRONG_KEY_ENGINE/telemetry.py"
if cmp -s "$ENGINE/telemetry.py" "$WRONG_KEY_ENGINE/telemetry.py"; then
  fail "the usage-key mutation did not change telemetry.py"
fi
install_project "$TEST_ROOT/wrong-key repo" "$WRONG_KEY_ENGINE"
printf 'replay\n' > "$TEST_ROOT/codex-mode"
wrong_key_out="$(driver_tick)"
assert_contains "$wrong_key_out" "action=scope" "the wrong-key mutation runs the scope step"
wrong_key_rows="$(read_attempts "$WRONG_KEY_ENGINE" "$DB")"
printf '%s\n' "$wrong_key_rows"
assert_contains "$wrong_key_rows" "|pm|codex|ok|None|None|None|None|None|None" \
  "reading only total_token_usage leaves real Codex tokens absent"
printf 'PASS: mutation reading only total_token_usage left Codex tokens absent\n'
