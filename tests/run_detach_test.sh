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
