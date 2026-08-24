#!/bin/zsh -f
set -euo pipefail
unsetopt BG_NICE

# --- no inherited selector may reach the fixture -----------------------------
#
# PM_FLOW_PROJECT and PM_FLOW_ROOT are legitimate overrides, and a pm-flow run
# that dispatches this suite exports both. Inherited, they point the fixture's
# commands at the *caller's* project workspace, which does not exist inside the
# temporary repository, so the suite dies before its first PASS group. The
# fixture is written here in full; nothing it needs may come from outside it.
for name in ${(k)parameters[(I)PM_FLOW_*]}; do
  unset "$name"
done
# `fail` is defined further down, once TEST_ROOT exists; this check runs first.
[[ -z "${PM_FLOW_PROJECT:-}${PM_FLOW_ROOT:-}${PM_FLOW_ENGINE_ROOT:-}${PM_FLOW_REPO_ROOT:-}${PM_FLOW_FLOW_DIR:-}" ]] || {
  printf 'FAIL: a PM_FLOW_* override survived into the test environment\n' >&2
  exit 1
}

REPO_ROOT="$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pm-flow-test.XXXXXX")"
TEST_ROOT="$(cd -P "$TEST_ROOT" && pwd -P)"
case "$TEST_ROOT" in
  */pm-flow-test.*) ;;
  *) printf 'unsafe test temp directory: %s\n' "$TEST_ROOT" >&2; exit 1 ;;
esac

cleanup() {
  if [[ -n "${TEST_ROOT:-}" && -d "$TEST_ROOT" && "$(basename "$TEST_ROOT")" == pm-flow-test.* ]]; then
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

output_value() {
  local output="$1"
  local key="$2"
  printf '%s\n' "$output" | awk -F= -v key="$key" \
    '$1 == key {sub(/^[^=]*=/, ""); print; exit}'
}

state_value() {
  local file_path="$1"
  local key="$2"
  sed -n "s/^${key}=//p" "$file_path" | /usr/bin/head -n 1
}

wait_for_file() {
  local file_path="$1"
  local label="$2"
  local attempt=0
  while (( attempt < 300 )); do
    [[ -f "$file_path" ]] && return 0
    (( attempt += 1 ))
    /bin/sleep 0.1
  done
  fail "$label: timed out waiting for $file_path"
}

wait_for_output() {
  local file_path="$1"
  local expected="$2"
  local label="$3"
  local attempt=0
  while (( attempt < 100 )); do
    if [[ -f "$file_path" && "$(/bin/cat "$file_path")" == *"$expected"* ]]; then
      return 0
    fi
    (( attempt += 1 ))
    /bin/sleep 0.1
  done
  fail "$label: timed out waiting for '$expected' in $file_path"
}

wait_for_exit() {
  local pid="$1"
  local label="$2"
  local attempt=0
  while (( attempt < 300 )); do
    kill -0 "$pid" 2>/dev/null || return 0
    (( attempt += 1 ))
    /bin/sleep 0.1
  done
  fail "$label: process $pid was still live"
}

ENGINE="$REPO_ROOT/template/.agentic/pm_flow"
DETACH_SCRIPT="$ENGINE/run_detach.zsh"
FIXTURE_REPO="$TEST_ROOT/detach repo"
FLOW_DIR="$FIXTURE_REPO/.agentic/pm_flow"
PROJECT_KEY="detach-repo"
PROJECT_DIR="$FLOW_DIR/$PROJECT_KEY"
RUNS_DIR="$PROJECT_DIR/runs"
SECTION_KEY="hangup-work"
SECTION_DIR="$PROJECT_DIR/sections/$SECTION_KEY"
MARKER="$TEST_ROOT/dispatch-started.marker"
WOKE_MARKER="$MARKER.woke"
DONE_FLAG="$TEST_ROOT/scope-done.flag"
STUB_BIN="$TEST_ROOT/stub-bin"

mkdir -p "$FIXTURE_REPO" "$STUB_BIN"
git -C "$FIXTURE_REPO" init -q
"$REPO_ROOT/install.sh" "$FIXTURE_REPO" --name "Detach Project" \
  > "$TEST_ROOT/install.out"

python3 - "$FLOW_DIR/config.json" <<'PYCFG'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
config = json.loads(path.read_text())
for role in ("cpo", "pm", "developer", "10x_developer"):
    config["roles"][role] = {"cli": "claude", "model": "", "difficulty": "low"}
path.write_text(json.dumps(config, indent=2) + "\n")
PYCFG

/bin/cp "$REPO_ROOT/tests/fixtures/stub_detach.zsh" "$STUB_BIN/claude"
chmod +x "$STUB_BIN/claude"

engine_command() {
  env PM_FLOW_ENGINE_ROOT="$ENGINE" PM_FLOW_FLOW_DIR="$FLOW_DIR" \
    PM_FLOW_REPO_ROOT="$FIXTURE_REPO" PM_FLOW_PROJECT="$PROJECT_KEY" \
    PM_DONE_FLAG="$DONE_FLAG" PM_DETACH_MARKER="$MARKER" \
    PATH="$STUB_BIN:$PATH" zsh -f "$ENGINE/pm_flow.sh" --project "$PROJECT_KEY" "$@"
}

detach_command() {
  env PM_FLOW_ENGINE_ROOT="$ENGINE" PM_FLOW_FLOW_DIR="$FLOW_DIR" \
    PM_FLOW_REPO_ROOT="$FIXTURE_REPO" PM_FLOW_PROJECT="$PROJECT_KEY" \
    PM_DONE_FLAG="$DONE_FLAG" PM_DETACH_MARKER="$MARKER" \
    PATH="$STUB_BIN:$PATH" zsh -f "$DETACH_SCRIPT" --project "$PROJECT_KEY" "$@"
}

engine_command init-section "$SECTION_KEY" <<'SECTIONBRIEF' > "$TEST_ROOT/init-section.out"
## Objective

- Prove a dispatched child survives its launcher's hangup.

## Scope

- The detached fixture only.

## Priority

- must-have: launcher independence is the command's contract.

## Owned paths

- `src/detached/**`

## Dependencies

- None.

## Acceptance

- The developer result is recorded after the launcher exits.

## Rejection conditions

- The launcher signal reaches the dispatch.
SECTIONBRIEF

scope_output="$(engine_command --section "$SECTION_KEY" run --max-ticks 1 2>&1)"
assert_contains "$scope_output" "scope 001 -> ASSIGN" "fixture preparation scopes one cycle"

git -C "$FIXTURE_REPO" add -A
git -C "$FIXTURE_REPO" -c user.name=pm-flow-test -c user.email=pm-flow@example.invalid \
  commit -qm "test fixture baseline"
[[ -z "$(git -C "$FIXTURE_REPO" status --porcelain)" ]] || \
  fail "fixture repository was dirty before start"

START_OUTPUT="$TEST_ROOT/start.out"
LAUNCHER_ERROR="$TEST_ROOT/launcher.err"
launcher_body='set -e
zsh -f "$1" --project "$2" start --max-ticks 1 --section "$3" > "$4" 2> "$5"
while :; do sleep 1; done'

PM_FLOW_ENGINE_ROOT="$ENGINE" PM_FLOW_FLOW_DIR="$FLOW_DIR" \
  PM_FLOW_REPO_ROOT="$FIXTURE_REPO" PM_FLOW_PROJECT="$PROJECT_KEY" \
  PM_DONE_FLAG="$DONE_FLAG" PM_DETACH_MARKER="$MARKER" PATH="$STUB_BIN:$PATH" \
  python3 -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' \
    zsh -f -c "$launcher_body" launcher "$DETACH_SCRIPT" "$PROJECT_KEY" \
    "$SECTION_KEY" "$START_OUTPUT" "$LAUNCHER_ERROR" &
launcher_pid=$!

wait_for_output "$START_OUTPUT" "log=" "detached start output"
start_output="$(/bin/cat "$START_OUTPUT")"
[[ "$(printf '%s\n' "$start_output" | awk 'END {print NR}')" == 2 ]] || \
  fail "start did not print exactly two lines"
supervisor_pid="$(output_value "$start_output" pid)"
log_path="$(output_value "$start_output" log)"
[[ "$supervisor_pid" == <-> ]] || fail "start did not print a numeric supervisor pid"
[[ "$log_path" == "$RUNS_DIR"/* ]] || fail "start log was outside the project runs directory"

fixture_status="$(git -C "$FIXTURE_REPO" status --porcelain)"
[[ -z "$fixture_status" ]] || \
  fail "fixture repository became dirty after start:\n$fixture_status"
bad_runtime="$(find "$FLOW_DIR" -name 'run-detach*' ! -path "$RUNS_DIR/*" -print)"
[[ -z "$bad_runtime" ]] || fail "run-detach wrote runtime files outside project runs: $bad_runtime"

wait_for_file "$MARKER" "first dispatch marker"
[[ ! -f "$WOKE_MARKER" ]] || fail "the dispatch woke before the launcher was signalled"

STATE_FILE="$RUNS_DIR/run-detach.state"
PID_FILE="$RUNS_DIR/run-detach.pid"
ticks_before="$(state_value "$STATE_FILE" ticks)"
second_code=0
second_output="$(detach_command start --max-ticks 1 --section "$SECTION_KEY" 2>&1)" || \
  second_code=$?
(( second_code != 0 )) || fail "a second start succeeded while the supervisor was live"
assert_contains "$second_output" "pid=$supervisor_pid" "second start reports the live pid"
assert_contains "$second_output" "log=$log_path" "second start reports the live log"
ticks_after="$(state_value "$STATE_FILE" ticks)"
[[ "$ticks_before" == "$ticks_after" ]] || fail "a refused second start changed the tick count"

live_status="$(detach_command status)"
assert_contains "$live_status" "running" "status while the dispatch is live"
assert_contains "$live_status" "pid=$supervisor_pid" "live status pid"
assert_contains "$live_status" "started_at=" "live status start time"
assert_contains "$live_status" "ticks=" "live status tick count"
assert_contains "$live_status" "log=$log_path" "live status log"

/bin/kill -HUP "-$launcher_pid"
launcher_wait=0
wait "$launcher_pid" || launcher_wait=$?
(( launcher_wait != 0 )) || fail "the launcher exited normally instead of from SIGHUP"
kill -0 "$launcher_pid" 2>/dev/null && fail "the launcher pid survived SIGHUP"
kill -0 "$supervisor_pid" 2>/dev/null || fail "the supervisor died with its launcher"

wait_for_file "$WOKE_MARKER" "post-SIGHUP woke marker"
CYCLE_RESULT="$SECTION_DIR/cycles/001/result.md"
wait_for_file "$CYCLE_RESULT" "developer cycle result"
result_output="$(/bin/cat "$CYCLE_RESULT")"
assert_contains "$result_output" "## Status" "developer result status heading"
assert_contains "$result_output" "DELIVERED" "developer result normal status"
assert_not_contains "$(/bin/cat "$log_path")" "failed (unknown)" \
  "detached dispatch log"

wait_for_exit "$supervisor_pid" "supervisor completion"
idle_status="$(detach_command status)"
assert_contains "$idle_status" "idle" "status after the run ends"

printf '%s\n' "$supervisor_pid" > "$PID_FILE"
stale_code=0
stale_status="$(detach_command status)" || stale_code=$?
(( stale_code == 0 )) || fail "status with a stale pid file exited $stale_code"
assert_contains "$stale_status" "idle" "status with a stale pid file"

printf 'PASS: launcher process-group SIGHUP leaves supervisor and dispatch alive\n'
printf 'PASS: live, idle, and stale-pid status reporting\n'
printf 'PASS: duplicate start refusal preserves tick state\n'
printf 'PASS: detached runtime stays under the project runs directory\n'

# --- graceful stop finishes one dispatch, then resumes at the next action ---

git -C "$FIXTURE_REPO" add -A
git -C "$FIXTURE_REPO" -c user.name=pm-flow-test -c user.email=pm-flow@example.invalid \
  commit -qm "record hangup fixture result"

STOP_SECTION_KEY="stop-work"
STOP_SECTION_DIR="$PROJECT_DIR/sections/$STOP_SECTION_KEY"
MARKER="$TEST_ROOT/stop-dispatch-started.marker"
WOKE_MARKER="$MARKER.woke"
STUB_BIN="$TEST_ROOT/stop-stub-bin"
mkdir -p "$STUB_BIN"
/bin/cp "$REPO_ROOT/tests/fixtures/stub_detach_stop.zsh" "$STUB_BIN/claude"
chmod +x "$STUB_BIN/claude"

engine_command init-section "$STOP_SECTION_KEY" <<'SECTIONBRIEF' > "$TEST_ROOT/init-stop-section.out"
## Objective

- Prove a graceful stop records the dispatch in flight and resumes after it.

## Scope

- The detached stop fixture only.

## Priority

- must-have: stop must never repeat paid work.

## Owned paths

- `src/stopped/**`

## Dependencies

- None.

## Acceptance

- The in-flight result is recorded and the restart performs the following action.

## Rejection conditions

- The stop signal reaches the dispatch or the restart repeats it.
SECTIONBRIEF

stop_scope_output="$(engine_command --section "$STOP_SECTION_KEY" run --max-ticks 1 2>&1)"
assert_contains "$stop_scope_output" "scope 001 -> ASSIGN" \
  "stop fixture preparation scopes one cycle"

git -C "$FIXTURE_REPO" add -A
git -C "$FIXTURE_REPO" -c user.name=pm-flow-test -c user.email=pm-flow@example.invalid \
  commit -qm "test stop fixture baseline"
[[ -z "$(git -C "$FIXTURE_REPO" status --porcelain)" ]] || \
  fail "stop fixture repository was dirty before start"

next_before_stop="$(engine_command --section "$STOP_SECTION_KEY" next)"
action_before_stop="$(printf '%s\n' "$next_before_stop" | \
  awk -v section="$STOP_SECTION_KEY" '$2 == section {print $3; exit}')"
[[ -n "$action_before_stop" ]] || fail "next did not name the stop section action"

stop_start_output="$(detach_command start --max-ticks 4 --section "$STOP_SECTION_KEY" \
  2> "$TEST_ROOT/stop-start.err")"
stop_supervisor_pid="$(output_value "$stop_start_output" pid)"
stop_log_path="$(output_value "$stop_start_output" log)"
[[ "$stop_supervisor_pid" == <-> ]] || fail "stop start did not print a numeric pid"
[[ "$stop_log_path" == "$RUNS_DIR"/* ]] || fail "stop log was outside the project runs directory"

fixture_status="$(git -C "$FIXTURE_REPO" status --porcelain)"
[[ -z "$fixture_status" ]] || \
  fail "fixture repository became dirty after stopped-run start:\n$fixture_status"
bad_runtime="$(find "$FLOW_DIR" -name 'run-detach*' ! -path "$RUNS_DIR/*" -print)"
[[ -z "$bad_runtime" ]] || fail "stop start wrote runtime files outside project runs: $bad_runtime"

wait_for_file "$MARKER" "stop dispatch marker"
STOP_CYCLE_DIR="$STOP_SECTION_DIR/cycles/001"
STOP_CYCLE_RESULT="$STOP_CYCLE_DIR/result.md"
[[ ! -f "$STOP_CYCLE_RESULT" ]] || fail "the stop dispatch finished before stop was requested"

# The driver's in-flight bookkeeping is tracked fixture state. Record it so
# the porcelain check below measures stop itself, not the ordinary dispatch.
git -C "$FIXTURE_REPO" add -A
git -C "$FIXTURE_REPO" -c user.name=pm-flow-test -c user.email=pm-flow@example.invalid \
  commit -qm "record in-flight stop fixture state"

stop_output="$(detach_command stop)"
assert_contains "$stop_output" "stop after the current dispatch" "stop response"
assert_contains "$stop_output" "pid=$stop_supervisor_pid" "stop response pid"
assert_contains "$stop_output" "log=$stop_log_path" "stop response log"

fixture_status="$(git -C "$FIXTURE_REPO" status --porcelain)"
[[ -z "$fixture_status" ]] || fail "fixture repository became dirty after stop:\n$fixture_status"
bad_runtime="$(find "$FLOW_DIR" -name 'run-detach*' ! -path "$RUNS_DIR/*" -print)"
[[ -z "$bad_runtime" ]] || fail "stop wrote runtime files outside project runs: $bad_runtime"

stopping_status="$(detach_command status)"
assert_contains "$stopping_status" "stopping" "status during the stopped dispatch"
[[ ! -f "$WOKE_MARKER" ]] || fail "the stopped dispatch finished before stopping status was observed"

wait_for_file "$WOKE_MARKER" "post-stop woke marker"
wait_for_file "$STOP_CYCLE_RESULT" "stopped developer cycle result"
stop_result_output="$(/bin/cat "$STOP_CYCLE_RESULT")"
assert_contains "$stop_result_output" "## Status" "stopped developer result status heading"
assert_contains "$stop_result_output" "DELIVERED" "stopped developer normal status"
stop_result_mtime="$(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_mtime_ns)' \
  "$STOP_CYCLE_RESULT")"

wait_for_exit "$stop_supervisor_pid" "stopped supervisor completion"
stop_last_line="$(/usr/bin/tail -n 1 "$stop_log_path")"
assert_contains "$stop_last_line" "stopped by request after tick 1" "stopped log final line"
assert_contains "$(/bin/cat "$stop_log_path")" \
  "$STOP_SECTION_KEY: $action_before_stop" "stopped run action from next"
[[ "$(state_value "$STATE_FILE" ticks)" == 1 ]] || \
  fail "stopped state did not record exactly one tick"
[[ ! -f "$RUNS_DIR/run-detach.stop" ]] || fail "the honoured stop request was not removed"

stopped_idle_status="$(detach_command status)"
assert_contains "$stopped_idle_status" "idle" "status after graceful stop"

no_live_stop="$(detach_command stop)"
assert_contains "$no_live_stop" "no run-detach supervisor is live" "stop with no live supervisor"
[[ ! -f "$RUNS_DIR/run-detach.stop" ]] || fail "idle stop created a request file"

next_before_restart="$(engine_command --section "$STOP_SECTION_KEY" next)"
action_before_restart="$(printf '%s\n' "$next_before_restart" | \
  awk -v section="$STOP_SECTION_KEY" '$2 == section {print $3; exit}')"
[[ -n "$action_before_restart" ]] || fail "next did not name the resume action"
[[ "$action_before_restart" != "$action_before_stop" ]] || \
  fail "the stopped dispatch did not advance the section action"

git -C "$FIXTURE_REPO" add -A
git -C "$FIXTURE_REPO" -c user.name=pm-flow-test -c user.email=pm-flow@example.invalid \
  commit -qm "record stopped fixture result"
[[ -z "$(git -C "$FIXTURE_REPO" status --porcelain)" ]] || \
  fail "stop fixture repository was dirty before restart"

restart_output="$(detach_command start --max-ticks 1 --section "$STOP_SECTION_KEY" \
  2> "$TEST_ROOT/restart.err")"
restart_supervisor_pid="$(output_value "$restart_output" pid)"
restart_log_path="$(output_value "$restart_output" log)"
[[ "$restart_supervisor_pid" == <-> ]] || fail "restart did not print a numeric pid"
wait_for_exit "$restart_supervisor_pid" "restarted supervisor completion"

STOP_CYCLE_REVIEW="$STOP_CYCLE_DIR/review.md"
wait_for_file "$STOP_CYCLE_REVIEW" "post-restart cycle review"
assert_contains "$(/bin/cat "$restart_log_path")" \
  "$STOP_SECTION_KEY: $action_before_restart" "restart action from next"
restart_result_mtime="$(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_mtime_ns)' \
  "$STOP_CYCLE_RESULT")"
[[ "$restart_result_mtime" == "$stop_result_mtime" ]] || \
  fail "restart rewrote the pre-stop developer result"

fixture_status="$(git -C "$FIXTURE_REPO" status --porcelain)"
if [[ -n "$fixture_status" ]]; then
  [[ "$fixture_status" == " M .agentic/pm_flow/$PROJECT_KEY/project_state/sections.md" ]] || \
    fail "fixture repository had unexpected changes after restart:\n$fixture_status"
  git -C "$FIXTURE_REPO" add -A
  git -C "$FIXTURE_REPO" -c user.name=pm-flow-test -c user.email=pm-flow@example.invalid \
    commit -qm "record resumed fixture index"
  fixture_status="$(git -C "$FIXTURE_REPO" status --porcelain)"
fi
[[ -z "$fixture_status" ]] || fail "fixture repository remained dirty after restart:\n$fixture_status"
bad_runtime="$(find "$FLOW_DIR" -name 'run-detach*' ! -path "$RUNS_DIR/*" -print)"
[[ -z "$bad_runtime" ]] || fail "restart wrote runtime files outside project runs: $bad_runtime"

printf 'PASS: graceful stop outlasts and records the dispatch in flight\n'
printf 'PASS: stopping becomes idle with one tick and no stop file\n'
printf 'PASS: restart performs the next action without rewriting the stopped result\n'
printf 'PASS: stop and restart keep runtime under runs and fixture porcelain empty\n'

# --- the routed command exposes start, status, stop, and safe restart -------

ROUTED_SECTION_KEY="routed-work"
MARKER="$TEST_ROOT/routed-dispatch-started.marker"
WOKE_MARKER="$MARKER.woke"
STUB_BIN="$TEST_ROOT/routed-stub-bin"
mkdir -p "$STUB_BIN"
/bin/cp "$REPO_ROOT/tests/fixtures/stub_detach.zsh" "$STUB_BIN/claude"
chmod +x "$STUB_BIN/claude"

engine_command init-section "$ROUTED_SECTION_KEY" <<'SECTIONBRIEF' > "$TEST_ROOT/init-routed-section.out"
## Objective

- Prove the operator-facing command routes detached run controls.

## Scope

- The routed detached fixture only.

## Priority

- must-have: operators need a reachable detached command.

## Owned paths

- `src/routed/**`

## Dependencies

- None.

## Acceptance

- Routed start, status, stop, and restart reach the supervisor.

## Rejection conditions

- Runtime state leaves the project runs directory.
SECTIONBRIEF

routed_scope_output="$(engine_command --section "$ROUTED_SECTION_KEY" run --max-ticks 1 2>&1)"
assert_contains "$routed_scope_output" "scope 001 -> ASSIGN" \
  "routed fixture preparation scopes one cycle"

git -C "$FIXTURE_REPO" add -A
git -C "$FIXTURE_REPO" -c user.name=pm-flow-test -c user.email=pm-flow@example.invalid \
  commit -qm "test routed fixture baseline"
[[ -z "$(git -C "$FIXTURE_REPO" status --porcelain)" ]] || \
  fail "routed fixture repository was dirty before start"

help_output="$(engine_command help)"
assert_contains "$help_output" "run-detach" "engine help"

routed_start_output="$(engine_command run-detach start --max-ticks 2 \
  --section "$ROUTED_SECTION_KEY" 2> "$TEST_ROOT/routed-start.err")"
routed_supervisor_pid="$(output_value "$routed_start_output" pid)"
routed_log_path="$(output_value "$routed_start_output" log)"
[[ "$routed_supervisor_pid" == <-> ]] || fail "routed start did not print a numeric pid"
[[ "$routed_log_path" == "$RUNS_DIR"/* ]] || \
  fail "routed start log was outside the project runs directory"

fixture_status="$(git -C "$FIXTURE_REPO" status --porcelain)"
[[ -z "$fixture_status" ]] || \
  fail "fixture repository became dirty after routed start:\n$fixture_status"
bad_runtime="$(find "$FLOW_DIR" -name 'run-detach*' ! -path "$RUNS_DIR/*" -print)"
[[ -z "$bad_runtime" ]] || \
  fail "routed start wrote runtime files outside project runs: $bad_runtime"

wait_for_file "$MARKER" "routed dispatch marker"
routed_status="$(engine_command --section "$ROUTED_SECTION_KEY" run-detach status)"
assert_contains "$routed_status" "running" "routed live status"
assert_contains "$routed_status" "pid=$routed_supervisor_pid" "routed live status pid"
assert_contains "$routed_status" "log=$routed_log_path" "routed live status log"

# The driver's in-flight bookkeeping is tracked fixture state. Record it so
# the duplicate-start and stop porcelain checks measure only those commands.
git -C "$FIXTURE_REPO" add -A
git -C "$FIXTURE_REPO" -c user.name=pm-flow-test -c user.email=pm-flow@example.invalid \
  commit -qm "record in-flight routed fixture state"

routed_second_code=0
routed_second_output="$(engine_command run-detach start --max-ticks 2 \
  --section "$ROUTED_SECTION_KEY" 2>&1)" || routed_second_code=$?
(( routed_second_code != 0 )) || fail "a routed second start succeeded while live"
assert_contains "$routed_second_output" "pid=$routed_supervisor_pid" \
  "routed second start reports the live pid"
assert_contains "$routed_second_output" "log=$routed_log_path" \
  "routed second start reports the live log"

fixture_status="$(git -C "$FIXTURE_REPO" status --porcelain)"
[[ -z "$fixture_status" ]] || \
  fail "fixture repository became dirty after routed second start:\n$fixture_status"
bad_runtime="$(find "$FLOW_DIR" -name 'run-detach*' ! -path "$RUNS_DIR/*" -print)"
[[ -z "$bad_runtime" ]] || \
  fail "routed second start wrote runtime files outside project runs: $bad_runtime"

routed_stop_output="$(engine_command --section "$ROUTED_SECTION_KEY" run-detach stop)"
assert_contains "$routed_stop_output" "stop after the current dispatch" "routed stop response"
assert_contains "$routed_stop_output" "pid=$routed_supervisor_pid" "routed stop pid"
assert_contains "$routed_stop_output" "log=$routed_log_path" "routed stop log"

fixture_status="$(git -C "$FIXTURE_REPO" status --porcelain)"
[[ -z "$fixture_status" ]] || \
  fail "fixture repository became dirty after routed stop:\n$fixture_status"
bad_runtime="$(find "$FLOW_DIR" -name 'run-detach*' ! -path "$RUNS_DIR/*" -print)"
[[ -z "$bad_runtime" ]] || \
  fail "routed stop wrote runtime files outside project runs: $bad_runtime"

routed_stopping_status="$(engine_command --section "$ROUTED_SECTION_KEY" run-detach status)"
assert_contains "$routed_stopping_status" "stopping" "routed stopping status"
wait_for_file "$WOKE_MARKER" "routed post-stop woke marker"
wait_for_exit "$routed_supervisor_pid" "routed stopped supervisor completion"
routed_idle_status="$(engine_command --section "$ROUTED_SECTION_KEY" run-detach status)"
assert_contains "$routed_idle_status" "idle" "routed idle status"
assert_contains "$(/usr/bin/tail -n 1 "$routed_log_path")" \
  "stopped by request after tick 1" "routed stopped log final line"

git -C "$FIXTURE_REPO" add -A
git -C "$FIXTURE_REPO" -c user.name=pm-flow-test -c user.email=pm-flow@example.invalid \
  commit -qm "record routed stop result"
[[ -z "$(git -C "$FIXTURE_REPO" status --porcelain)" ]] || \
  fail "routed fixture repository was dirty before stale-stop start"

printf 'stale stop request\n' > "$RUNS_DIR/run-detach.stop"
stale_stop_start_output="$(engine_command run-detach start --max-ticks 2 \
  --section "$ROUTED_SECTION_KEY" 2> "$TEST_ROOT/stale-stop-start.err")"
stale_stop_supervisor_pid="$(output_value "$stale_stop_start_output" pid)"
[[ "$stale_stop_supervisor_pid" == <-> ]] || \
  fail "stale-stop start did not print a numeric pid"
wait_for_exit "$stale_stop_supervisor_pid" "stale-stop supervisor completion"
[[ "$(state_value "$STATE_FILE" ticks)" == 2 ]] || \
  fail "a stale stop request prevented the routed run from reaching two ticks"
[[ ! -f "$RUNS_DIR/run-detach.stop" ]] || \
  fail "routed start did not clear the stale stop request"

printf 'PASS: routed run-detach covers help, start, status, stop, refusal, and stale-stop restart\n'
