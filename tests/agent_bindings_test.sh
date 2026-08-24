#!/bin/zsh -f
set -euo pipefail
unsetopt BG_NICE

# A nested pm-flow run exports selectors for its own project. They do not apply
# to this fixture's disposable repository and would make the public command
# resolve the wrong project key there.
for name in ${(k)parameters[(I)PM_FLOW_*]}; do
  unset "$name"
done

REPO_ROOT="$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pm-flow-agent-bindings.XXXXXX")"
case "$TEST_ROOT" in
  */pm-flow-agent-bindings.*) ;;
  *) printf 'unsafe test temp directory: %s\n' "$TEST_ROOT" >&2; exit 1 ;;
esac
LOCK_HOLDER_PID=""
cleanup() {
  if [[ -n "$LOCK_HOLDER_PID" ]]; then
    kill "$LOCK_HOLDER_PID" 2>/dev/null || true
    wait "$LOCK_HOLDER_PID" 2>/dev/null || true
  fi
  rm -rf -- "$TEST_ROOT"
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

expect_failure() {
  local label="$1"
  shift
  if "$@" > "$TEST_ROOT/expected-failure.log" 2>&1; then
    fail "$label: command unexpectedly succeeded"
  fi
}

cat > "$TEST_ROOT/acp_agent.py" <<'PY'
#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path

mode = sys.argv[1]
marker = Path(sys.argv[2])

def read_frame():
    line = sys.stdin.readline()
    if not line:
        raise SystemExit(0)
    frame = json.loads(line)
    assert frame.get("jsonrpc") == "2.0"
    return frame

def reply(request, result):
    print(json.dumps({"jsonrpc": "2.0", "id": request["id"], "result": result}), flush=True)

request = read_frame()
assert request["method"] == "initialize"
assert request["params"]["protocolVersion"] == 1
if mode == "log_fault":
    count = int(marker.read_text()) if marker.exists() else 0
    marker.write_text(str(count + 1))
if mode == "rpc_error":
    count = int(marker.read_text()) if marker.exists() else 0
    marker.write_text(str(count + 1))
    print(json.dumps({
        "jsonrpc": "2.0", "id": request["id"],
        "error": {"code": -32000, "message": "agent RPC failed"}}), flush=True)
    raise SystemExit(0)
if mode == "invalid_json":
    print("not-json", flush=True)
    raise SystemExit(0)
if mode == "invalid_envelope":
    print(json.dumps({"result": {}}), flush=True)
    raise SystemExit(0)
capabilities = {} if mode in {"no_sandbox", "cycle_prompt_level"} else {"_meta": {"sandbox": True}}
reply(request, {"protocolVersion": 1, "agentCapabilities": capabilities})

request = read_frame()
assert request["method"] == "session/new"
assert os.path.isabs(request["params"]["cwd"])
assert request["params"]["mcpServers"] == []
reply(request, {"sessionId": "test-session"})

request = read_frame()
assert request["method"] == "session/prompt"
if mode == "log_fault":
    marker.with_suffix(".prompt").write_text("prompted\n")
assert request["params"]["sessionId"] == "test-session"
prompt = request["params"]["prompt"]
assert isinstance(prompt, list) and len(prompt) == 1
assert prompt[0].get("type") == "text"
if mode.startswith("cycle_"):
    assert "Task: implement this assignment" in prompt[0].get("text", "")
    access_log = Path(os.environ["PM_FLOW_ACCESS_LOG"])
    marker.write_text(access_log.read_text())
else:
    assert prompt == [{"type": "text", "text": "hello ACP"}]
if mode == "early_exit":
    raise SystemExit(17)
if mode == "cancel":
    marker.write_text(str(os.getpid()))
    request = read_frame()
    assert request["method"] == "session/cancel"
    assert "id" not in request
    assert request["params"] == {"sessionId": "test-session"}
    marker.with_suffix(".cancelled").write_text("cancelled\n")
    raise SystemExit(0)

if mode in {"permission_allow", "permission_cancel", "cycle_enforced", "cycle_prompt_level"}:
    print(json.dumps({
        "jsonrpc": "2.0", "id": 91, "method": "session/request_permission",
        "params": {"sessionId": "test-session", "options": [
            {"optionId": "deny-first", "name": "Deny", "kind": "reject_once"},
            {"optionId": "permit-second", "name": "Permit", "kind": "allow_once"},
        ]}}), flush=True)
    permission = read_frame()
    assert permission["id"] == 91
    outcome = permission["result"]["outcome"]
    if mode == "permission_cancel":
        assert outcome == {"outcome": "cancelled"}
    else:
        assert outcome == {"outcome": "selected", "optionId": "permit-second"}

reply_text = "agent reply"
if mode.startswith("cycle_"):
    reply_text = """## What I changed
Built through ACP.

## What I reused or restructured
The section harness.

## Validation
ACP exchange passed.

## What I could not do
Nothing.

## Status
DELIVERED"""

print(json.dumps({
    "jsonrpc": "2.0", "method": "session/update",
    "params": {"sessionId": "test-session", "update": {
        "sessionUpdate": "agent_message_chunk",
        "content": {"type": "text", "text": reply_text}}}}), flush=True)
usage_update = {"sessionUpdate": "usage_update", "used": 7, "size": 100}
if mode in {"token_usage_update", "cycle_enforced"}:
    usage_update = {
        "sessionUpdate": "usage_update", "inputTokens": 17, "outputTokens": 5
    }
print(json.dumps({
    "jsonrpc": "2.0", "method": "session/update",
    "params": {"sessionId": "test-session", "update": usage_update}}), flush=True)
prompt_result = {"stopReason": "end_turn"}
if mode == "token_usage_result":
    prompt_result["usage"] = {"input_tokens": 23, "output_tokens": 9}
reply(request, prompt_result)
PY
chmod +x "$TEST_ROOT/acp_agent.py"

params() {
  python3 - "$TEST_ROOT/acp_agent.py" "$1" "$TEST_ROOT/agent.marker" <<'PY'
import json
import sys
print(json.dumps({
    "command": [sys.executable, sys.argv[1], sys.argv[2], sys.argv[3]],
    "max_attempt_seconds": 5,
    "silent_stall_seconds": 2,
}))
PY
}

run_client() {
  local mode="$1"
  local tier="${2:-write}"
  python3 "$REPO_ROOT/src/pm_flow/acp.py" \
    --prompt "hello ACP" --params-json "$(params "$mode")" --access-tier "$tier"
}

field() {
  python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"
}

healthy="$(run_client healthy write)"
[[ "$(printf '%s' "$healthy" | field text)" == "agent reply" ]] || fail "healthy exchange text"
[[ "$(printf '%s' "$healthy" | field enforceable)" == "True" ]] || fail "sandbox write enforceability"
[[ "$(printf '%s' "$healthy" | field failure_reason)" == "none" ]] || fail "healthy failure reason"
[[ "$(printf '%s' "$healthy" | field usage)" == "{}" ]] || fail "context occupancy was treated as token usage"
printf 'PASS: sandbox capability yields enforceable=true for write\n'

token_update="$(run_client token_usage_update write)"
[[ "$(printf '%s' "$token_update" | field usage)" == \
  "{'input_tokens': 17, 'output_tokens': 5}" ]] || fail "usage-update token normalisation"
token_result="$(run_client token_usage_result write)"
[[ "$(printf '%s' "$token_result" | field usage)" == \
  "{'input_tokens': 23, 'output_tokens': 9}" ]] || fail "prompt-result token normalisation"
printf 'PASS: ACP token usage is normalised and context occupancy is ignored\n'

scoped="$(run_client healthy scoped)"
[[ "$(printf '%s' "$scoped" | field enforceable)" == "True" ]] || fail "sandbox scoped enforceability"
printf 'PASS: sandbox capability yields enforceable=true for scoped\n'

read_result="$(run_client healthy read)"
[[ "$(printf '%s' "$read_result" | field enforceable)" == "True" ]] || fail "sandbox read enforceability"
printf 'PASS: sandbox capability yields enforceable=true for read\n'

no_sandbox="$(run_client no_sandbox write)"
[[ "$(printf '%s' "$no_sandbox" | field enforceable)" == "False" ]] || fail "missing sandbox enforceability"
[[ "$(printf '%s' "$no_sandbox" | field failure_reason)" == "acp_capability_missing" ]] || fail "missing capability reason"
printf 'PASS: no sandbox capability yields enforceable=false for write\n'

no_sandbox_scoped="$(run_client no_sandbox scoped)"
[[ "$(printf '%s' "$no_sandbox_scoped" | field enforceable)" == "False" ]] || fail "missing scoped sandbox enforceability"
printf 'PASS: no sandbox capability yields enforceable=false for scoped\n'

no_sandbox_read="$(run_client no_sandbox read)"
[[ "$(printf '%s' "$no_sandbox_read" | field enforceable)" == "False" ]] || fail "missing read sandbox enforceability"
printf 'PASS: no sandbox capability yields enforceable=false for read\n'

permission_write="$(run_client permission_allow write)"
[[ "$(printf '%s' "$permission_write" | field text)" == "agent reply" ]] || fail "write permission selection"
permission_scoped="$(run_client permission_allow scoped)"
[[ "$(printf '%s' "$permission_scoped" | field text)" == "agent reply" ]] || fail "scoped permission selection"
permission_read="$(run_client permission_cancel read)"
[[ "$(printf '%s' "$permission_read" | field text)" == "agent reply" ]] || fail "read permission cancellation"
printf 'PASS: permission requests follow the access tier and option kind\n'

for mode in invalid_json invalid_envelope; do
  expect_failure "$mode" run_client "$mode"
  result="$(<"$TEST_ROOT/expected-failure.log")"
  [[ "$(printf '%s' "$result" | field failure_reason)" == "acp_malformed_frame" ]] || fail "$mode reason"
done
printf 'PASS: malformed protocol frames have an explicit reason\n'

expect_failure "early exit" run_client early_exit
early="$(<"$TEST_ROOT/expected-failure.log")"
[[ "$(printf '%s' "$early" | field failure_reason)" == "acp_child_exited" ]] || fail "early exit reason"
printf 'PASS: child exit has an explicit recoverable reason\n'

mkdir "$TEST_ROOT/access-log-directory"
rm -f "$TEST_ROOT/agent.marker" "$TEST_ROOT/agent.prompt"
expect_failure "access log directory" python3 "$REPO_ROOT/src/pm_flow/acp.py" \
  --prompt "hello ACP" --params-json "$(params log_fault)" --access-tier write \
  --access-log "$TEST_ROOT/access-log-directory"
log_fault="$(<"$TEST_ROOT/expected-failure.log")"
[[ "$(printf '%s' "$log_fault" | field failure_reason)" == \
  "acp_access_log_unwritable" ]] || fail "access log failure reason"
[[ "$(<"$TEST_ROOT/agent.marker")" == "1" ]] || fail "access log probe did not initialize once"
[[ ! -e "$TEST_ROOT/agent.prompt" ]] || fail "access log fault reached session/prompt"
printf 'PASS: an unwritable ACP access log fails closed with an explicit reason\n'

rm -f "$TEST_ROOT/agent.marker" "$TEST_ROOT/agent.cancelled"
cancel_params="$(params cancel)"
python3 "$REPO_ROOT/src/pm_flow/acp.py" \
  --prompt "hello ACP" --params-json "$cancel_params" --access-tier write \
  > "$TEST_ROOT/cancel-output.json" &
client_pid=$!
for _ in {1..100}; do
  [[ -f "$TEST_ROOT/agent.marker" ]] && break
  sleep 0.01
done
[[ -f "$TEST_ROOT/agent.marker" ]] || fail "cancel agent never reached prompt"
kill -TERM "$client_pid"
if wait "$client_pid"; then
  fail "cancelled client unexpectedly succeeded"
fi
[[ -f "$TEST_ROOT/agent.cancelled" ]] || fail "agent did not receive session/cancel"
agent_pid="$(<"$TEST_ROOT/agent.marker")"
if kill -0 "$agent_pid" 2>/dev/null; then
  fail "cancelled agent was not reaped"
fi
[[ "$(field failure_reason < "$TEST_ROOT/cancel-output.json")" == "acp_cancelled" ]] || fail "cancel reason"
printf 'PASS: cancellation notifies and reaps the child\n'

module_result="$(PYTHONPATH="$REPO_ROOT/src" python3 -m pm_flow.acp \
  --prompt "hello ACP" --params-json "$(params healthy)" --access-tier write)"
[[ "$(printf '%s' "$module_result" | field text)" == "agent reply" ]] || fail "module execution"
printf 'PASS: ACP client runs as module and bare file\n'

# Build the same offline wheel as packaged_layout_test.sh, then install it into
# a separate runtime venv. From this point on the public scenarios use only the
# installed console script and modules; no checkout path is put on PYTHONPATH or
# exported as an engine/repository override.
WHEELHOUSE="$REPO_ROOT/tests/packaging-build-wheelhouse"
BUILD_REQUIREMENTS="$WHEELHOUSE/build-requirements.txt"
BUILD_VENV="$TEST_ROOT/build-venv"
VENV="$TEST_ROOT/venv"
DIST="$TEST_ROOT/dist"
BUILD_LOG="$TEST_ROOT/build.log"
mkdir -p "$DIST"
[[ -f "$BUILD_REQUIREMENTS" ]] || fail "missing locked packaging requirements"

unset VIRTUAL_ENV PYTHONPATH PYTHONHOME PYTHONSTARTUP
for name in ${(k)parameters[(I)PIP_*]} ${(k)parameters[(I)UV_*]}; do
  unset "$name"
done
export PIP_CACHE_DIR="$TEST_ROOT/pip-cache"
export XDG_CACHE_HOME="$TEST_ROOT/xdg-cache"
export PIP_CONFIG_FILE="$TEST_ROOT/pip.conf"
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PIP_NO_INPUT=1
: > "$PIP_CONFIG_FILE"
export ZDOTDIR="$TEST_ROOT/zdotdir"
mkdir -p "$ZDOTDIR"

pip_offline() {
  local venv="$1"
  shift
  "$venv/bin/python" -m pip install \
    --no-index --find-links "$WHEELHOUSE" \
    --disable-pip-version-check --no-input "$@"
}

python3 -m venv "$BUILD_VENV" > "$BUILD_LOG" 2>&1 || {
  /bin/cat "$BUILD_LOG" >&2
  fail "build venv creation failed"
}
pip_offline "$BUILD_VENV" --quiet --require-hashes \
  -r "$BUILD_REQUIREMENTS" >> "$BUILD_LOG" 2>&1 || {
  /bin/cat "$BUILD_LOG" >&2
  fail "locked build requirements did not install offline"
}
"$BUILD_VENV/bin/python" -c 'import hatchling.build' >> "$BUILD_LOG" 2>&1 || {
  /bin/cat "$BUILD_LOG" >&2
  fail "build venv cannot import the pinned backend"
}
"$BUILD_VENV/bin/python" -m pip wheel \
  --no-index --no-build-isolation --no-deps \
  --disable-pip-version-check --no-input \
  --wheel-dir "$DIST" "$REPO_ROOT" >> "$BUILD_LOG" 2>&1 || {
  /bin/cat "$BUILD_LOG" >&2
  fail "offline wheel build failed"
}
built_wheels=("$DIST"/pm_flow-*.whl(N))
(( ${#built_wheels} == 1 )) || fail "expected exactly one pm-flow wheel"
WHEEL="$built_wheels[1]"
python3 -m venv "$VENV" >> "$BUILD_LOG" 2>&1 || {
  /bin/cat "$BUILD_LOG" >&2
  fail "runtime venv creation failed"
}
"$VENV/bin/python" -m pip install \
  --quiet --no-index --no-deps \
  --disable-pip-version-check --no-input \
  "$WHEEL" >> "$BUILD_LOG" 2>&1 || {
  /bin/cat "$BUILD_LOG" >&2
  fail "wheel installation failed"
}
PM_FLOW="$VENV/bin/pm-flow"
[[ -x "$PM_FLOW" ]] || fail "wheel install produced no pm-flow console script"
! "$VENV/bin/python" -c 'import hatchling' >/dev/null 2>&1 || \
  fail "runtime venv contains the build backend"
INSTALLED_ENGINE="$("$VENV/bin/python" -c \
  'from pathlib import Path; import pm_flow; print(Path(pm_flow.__file__).parent / "engine")')"
[[ -f "$INSTALLED_ENGINE/agent_exec.sh" && -f "$INSTALLED_ENGINE/../acp.py" ]] || \
  fail "wheel omitted the installed engine or adjacent ACP client"
printf 'PASS: agent binding scenarios use an isolated wheel install\n'

# The installed public driver keeps its managing roles on the existing claude
# fixture and binds only the developer to ACP. Separate sections prove the ACP
# cycle, collect nested claude usage, and leave a never-dispatched control for
# the MCP section-selection assertion below.
CYCLE_REPO="$TEST_ROOT/cycle repo"
mkdir "$CYCLE_REPO"
git -C "$CYCLE_REPO" init --quiet
( cd "$CYCLE_REPO" && "$REPO_ROOT/install.sh" "$CYCLE_REPO" \
  --name "ACP Binding Project" ) > "$TEST_ROOT/cycle-install.out"
CYCLE_FLOW="$CYCLE_REPO/.agentic/pm_flow"
CYCLE_SECTION="$CYCLE_FLOW/cycle-repo/sections/widget"
ENFORCED_MARKER="$TEST_ROOT/enforced-access.marker"

cycle_pm() {
  ( cd "$CYCLE_REPO" && "$PM_FLOW" "$@" )
}

"$VENV/bin/python" - "$CYCLE_FLOW/config.json" "$TEST_ROOT/acp_agent.py" "$ENFORCED_MARKER" <<'PYCFG'
import json
import sys
from pathlib import Path

path, agent, marker = map(Path, sys.argv[1:])
config = json.loads(path.read_text())
for role in ("cpo", "pm", "10x_developer", "maintenance_engineer"):
    config["roles"][role] = {"cli": "claude", "model": "", "difficulty": "low"}
config["roles"]["consultant"] = [
    {"cli": "claude", "model": "", "difficulty": "low"},
    {"cli": "claude", "model": "", "difficulty": "low"},
]
config["roles"]["developer"] = {
    "cli": "acp",
    "model": "",
    "difficulty": "low",
    "cli_params": {
        "command": [sys.executable, str(agent), "cycle_enforced", str(marker)]
    },
}
config["supervision"] = {
    "heartbeat_stall_seconds": 30,
    "silent_stall_seconds": 5,
    "max_attempt_seconds": 20,
    "max_attempts": 1,
    "retry_backoff_seconds": 1,
    "usage_limit_pause_seconds": 1,
}
config["isolation"] = {"worktrees": 0}
path.write_text(json.dumps(config, indent=2) + "\n")
PYCFG

cycle_pm init-section widget <<'SECTIONBRIEF' > "$TEST_ROOT/cycle-section.out"
## Objective

- Build the ACP widget.

## Scope

- The widget only.

## Priority

- must-have: the section proves the binding

## Owned paths

- `src/widget/**`

## Dependencies

- None.

## Acceptance

- The ACP cycle reaches GO.

## Rejection conditions

- A non-ACP developer satisfies the assignment.
SECTIONBRIEF

cycle_pm init-section selected-widget <<'SECTIONBRIEF' > "$TEST_ROOT/selected-section.out"
## Objective

- Build the selected widget.

## Scope

- The selected widget only.

## Priority

- must-have: the section argument selects this section

## Owned paths

- `src/selected-widget/**`

## Dependencies

- None.

## Acceptance

- An MCP tick advances only this section.

## Rejection conditions

- Another section advances instead.
SECTIONBRIEF

cycle_pm init-section usage-widget <<'SECTIONBRIEF' > "$TEST_ROOT/usage-section.out"
## Objective

- Record nested claude usage from a failing attempt.

## Scope

- The usage fixture only.

## Priority

- must-have: preserve claude token accounting

## Owned paths

- `src/usage-widget/**`

## Dependencies

- None.

## Acceptance

- Cost retains the failing claude attempt's token counts.

## Rejection conditions

- The fixture repairs engine state by hand.
SECTIONBRIEF

FLOW_BIN="$TEST_ROOT/flow-bin"
mkdir "$FLOW_BIN"
/bin/cp "$REPO_ROOT/tests/fixtures/stub_success.zsh" "$FLOW_BIN/claude"
chmod +x "$FLOW_BIN/claude"

drain_project_work() {
  local guard=0
  while [[ "$(cycle_pm status)" == *"portfolio review due"* ]]; do
    (( guard += 1 ))
    (( guard <= 8 )) || fail "the portfolio review queue would not drain"
    PM_DONE_FLAG="$TEST_ROOT/project-complete.flag" \
      PATH="$VENV/bin:$FLOW_BIN:/usr/bin:/bin" cycle_pm tick > /dev/null 2>&1
  done
}

run_driver() {
  PM_DONE_FLAG="$TEST_ROOT/widget-complete.flag" \
    PATH="$VENV/bin:$FLOW_BIN:/usr/bin:/bin" \
    cycle_pm --section widget run --max-ticks "${1:-12}" 2>&1
}

drain_project_work

# A failed claude response carries its real usage inside the JSON string that
# write_response wraps. Record one such attempt so cost proves that adding ACP
# usage did not shadow the nested claude counts with an empty top-level block.
cat > "$FLOW_BIN/claude" <<'ZSH'
#!/bin/zsh -f
python3 -c 'import json; print(json.dumps({"is_error": True, "result": "synthetic failure", "usage": {"input_tokens": 11, "output_tokens": 3}}))'
exit 1
ZSH
chmod +x "$FLOW_BIN/claude"
if PM_DONE_FLAG="$TEST_ROOT/selected-complete.flag" \
    PATH="$VENV/bin:$FLOW_BIN:/usr/bin:/bin" \
    cycle_pm --section usage-widget tick > "$TEST_ROOT/claude-failure.out" 2>&1; then
  fail "synthetic claude failure unexpectedly succeeded"
fi
/bin/cp "$REPO_ROOT/tests/fixtures/stub_success.zsh" "$FLOW_BIN/claude"
chmod +x "$FLOW_BIN/claude"

cycle_run=""
if ! cycle_run="$(run_driver 12)"; then
  printf '%s\n' "$cycle_run" >&2
  fail "ACP public driver cycle failed"
fi
assert_contains "$cycle_run" "develop 001 -> result" "driver dispatches the ACP developer"
assert_contains "$cycle_run" "review 001 -> GO" "ACP result reaches a GO verdict"
assert_contains "$cycle_run" "complete -> section done" "ACP section completes"
assert_contains "$(/bin/cat "$CYCLE_SECTION/cycles/001/result.md")" "Built through ACP." \
  "accepted result contains the ACP agent's text"
[[ "$(/bin/cat "$CYCLE_SECTION/cycles/001/result.md")" != *'"failure_reason"'* ]] || \
  fail "accepted result contains the ACP outcome JSON"
assert_contains "$(/bin/cat "$ENFORCED_MARKER")" '"access":"enforced"' \
  "enforced record exists before session/prompt"
assert_contains "$(/bin/cat "$ENFORCED_MARKER")" '"source":"acp-capabilities"' \
  "ACP access record identifies its source"
printf 'PASS: ACP developer completes a public driver cycle to GO\n'
printf 'PASS: enforced ACP access is recorded before work\n'

cost_output="$(cycle_pm cost)"
printf '%s\n' "$cost_output" | awk -F'\t' \
  '$1 == "ATTEMPT" && $4 == "developer" && $6 == "acp" && $8 == 17 && $9 == 5 {found=1} END {exit !found}' || \
  fail "cost has no token-priced ACP developer attempt"
printf '%s\n' "$cost_output" | awk -F'\t' \
  '$1 == "ATTEMPT" && $6 == "claude" && $8 == 11 && $9 == 3 {found=1} END {exit !found}' || \
  fail "cost lost nested claude token counts"
printf 'PASS: cost distinguishes ACP and claude transports\n'
printf 'PASS: cost preserves ACP and nested claude token counts\n'

# Rebind the same seat to an agent declaring no boundary. Its successful
# capability-missing outcome must still dispatch, and the marker is the proof
# that prompt-level access was recorded before the prompt arrived.
PROMPT_LEVEL_MARKER="$TEST_ROOT/prompt-level-access.marker"
"$VENV/bin/python" - "$CYCLE_FLOW/config.json" "$TEST_ROOT/acp_agent.py" "$PROMPT_LEVEL_MARKER" <<'PYCFG'
import json
import sys
from pathlib import Path

path, agent, marker = map(Path, sys.argv[1:])
config = json.loads(path.read_text())
config["roles"]["developer"]["cli_params"]["command"] = [
    sys.executable, str(agent), "cycle_prompt_level", str(marker)
]
path.write_text(json.dumps(config, indent=2) + "\n")
PYCFG
printf 'Task: implement this assignment\n' > "$TEST_ROOT/prompt-level-prompt.md"
PM_FLOW_FLOW_DIR="$CYCLE_FLOW" PM_FLOW_REPO_ROOT="$CYCLE_REPO" \
  PATH="$VENV/bin:$FLOW_BIN:/usr/bin:/bin" \
  zsh "$INSTALLED_ENGINE/agent_exec.sh" developer \
    --prompt-file "$TEST_ROOT/prompt-level-prompt.md" \
    --output "$TEST_ROOT/prompt-level-response.json"
[[ "$(field is_error < "$TEST_ROOT/prompt-level-response.json")" == "False" ]] || \
  fail "prompt-level ACP dispatch was treated as a failure"
assert_contains "$(field result < "$TEST_ROOT/prompt-level-response.json")" "Built through ACP." \
  "prompt-level response contains agent text"
"$VENV/bin/python" - "$TEST_ROOT/prompt-level-response.json" <<'PY'
import json
import sys
from pathlib import Path

assert "usage" not in json.loads(Path(sys.argv[1]).read_text())
PY
assert_contains "$(/bin/cat "$PROMPT_LEVEL_MARKER")" '"access":"prompt-level"' \
  "prompt-level record exists before session/prompt"
printf 'PASS: prompt-level ACP access is recorded before work and still dispatches\n'
printf 'PASS: an empty ACP usage block is omitted from the response envelope\n'

configure_failure_mode() {
  "$VENV/bin/python" - "$CYCLE_FLOW/config.json" "$TEST_ROOT/acp_agent.py" "$1" "$2" "$3" <<'PYCFG'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
agent = Path(sys.argv[2])
mode, marker, max_attempts = sys.argv[3:]
config = json.loads(path.read_text())
config["roles"]["developer"]["cli_params"]["command"] = [
    sys.executable, str(agent), mode, marker
]
config["supervision"]["max_attempts"] = int(max_attempts)
path.write_text(json.dumps(config, indent=2) + "\n")
PYCFG
}

run_failed_dispatch() {
  local output="$1"
  local access_log="${2:-${output%.json}.access.jsonl}"
  if PM_FLOW_FLOW_DIR="$CYCLE_FLOW" PM_FLOW_REPO_ROOT="$CYCLE_REPO" \
      PM_FLOW_ACCESS_LOG="$access_log" PATH="$VENV/bin:$FLOW_BIN:/usr/bin:/bin" \
      zsh "$INSTALLED_ENGINE/agent_exec.sh" developer \
        --prompt-file "$TEST_ROOT/failure-prompt.md" --output "$output" \
        > "$TEST_ROOT/failure-dispatch.log" 2>&1; then
    fail "ACP failure dispatch unexpectedly succeeded"
  fi
}

printf 'hello ACP\n' > "$TEST_ROOT/failure-prompt.md"
configure_failure_mode invalid_json "$TEST_ROOT/invalid.marker" 1
run_failed_dispatch "$TEST_ROOT/malformed-response.json"
[[ "$(field failure_reason < "$TEST_ROOT/malformed-response.json")" == "permanent" ]] || \
  fail "malformed ACP frame did not map to permanent"

configure_failure_mode early_exit "$TEST_ROOT/early.marker" 1
run_failed_dispatch "$TEST_ROOT/child-exit-response.json"
[[ "$(field failure_reason < "$TEST_ROOT/child-exit-response.json")" == "network" ]] || \
  fail "ACP child exit did not map to network"

rm -f "$TEST_ROOT/rpc-attempts.marker"
configure_failure_mode rpc_error "$TEST_ROOT/rpc-attempts.marker" 3
run_failed_dispatch "$TEST_ROOT/rpc-response.json"
[[ "$(field failure_reason < "$TEST_ROOT/rpc-response.json")" == "unknown" ]] || \
  fail "ACP RPC error did not map to unknown"
[[ "$(field attempts < "$TEST_ROOT/rpc-response.json")" == "2" ]] || \
  fail "unknown ACP failure did not receive exactly one extra attempt"
[[ "$(/bin/cat "$TEST_ROOT/rpc-attempts.marker")" == "2" ]] || \
  fail "RPC test agent did not observe exactly two exchanges"
printf 'PASS: ACP failures use the dedicated retry mapping\n'

mkdir "$TEST_ROOT/arm-access-log-directory"
rm -f "$TEST_ROOT/arm-log-fault.marker" "$TEST_ROOT/arm-log-fault.prompt"
configure_failure_mode log_fault "$TEST_ROOT/arm-log-fault.marker" 3
run_failed_dispatch "$TEST_ROOT/log-fault-response.json" \
  "$TEST_ROOT/arm-access-log-directory"
[[ "$(field failure_reason < "$TEST_ROOT/log-fault-response.json")" == "permanent" ]] || \
  fail "access-log failure did not map to permanent"
[[ "$(field attempts < "$TEST_ROOT/log-fault-response.json")" == "1" ]] || \
  fail "access-log failure was retried"
[[ "$(<"$TEST_ROOT/arm-log-fault.marker")" == "1" ]] || \
  fail "access-log fault agent ran more than once"
[[ ! -e "$TEST_ROOT/arm-log-fault.prompt" ]] || \
  fail "arm access-log fault reached session/prompt"
printf 'PASS: an ACP access-log fault is permanent and is not retried\n'

printf 'PASS: agent bindings ACP suite\n'

# Restore the successful ACP developer before the same installed project is
# handed to the MCP client. The client must prove that an explicit tick advances
# selected-widget while the never-dispatched, actionable control remains
# unchanged.
configure_failure_mode cycle_enforced "$TEST_ROOT/selected-access.marker" 1
MCP_REPO="$CYCLE_REPO"
MCP_FLOW="$CYCLE_FLOW"
MCP_PROJECT_DIR="$CYCLE_FLOW/cycle-repo"
MCP_DRIVER_BIN="$FLOW_BIN"
MCP_DONE_FLAG="$TEST_ROOT/selected-complete.flag"
drain_project_work

# Give the target a real dispatch timestamp, then create a lexically later
# control with no timestamp. The scheduler must therefore put the control first
# because it has never been dispatched, not because of its name.
PM_DONE_FLAG="$MCP_DONE_FLAG" PATH="$VENV/bin:$MCP_DRIVER_BIN:/usr/bin:/bin" \
  cycle_pm --section selected-widget tick > "$TEST_ROOT/selected-seed.out" 2>&1
cycle_pm init-section undispatched-widget <<'SECTIONBRIEF' > "$TEST_ROOT/control-section.out"
## Objective

- Remain available as the untargeted control.

## Scope

- The control widget only.

## Priority

- must-have: an untargeted tick selects this never-dispatched section first

## Owned paths

- `src/undispatched-widget/**`

## Dependencies

- None.

## Acceptance

- A targeted MCP drive leaves this section unchanged.

## Rejection conditions

- The control is made unactionable before the MCP drive.
SECTIONBRIEF

cat > "$TEST_ROOT/mcp_client.py" <<'PY'
#!/usr/bin/env python3
import json
import subprocess
import sys


repo_root, project_key, section_key, unchanged_key, mode = sys.argv[1:]
server = subprocess.Popen(
    [sys.executable, "-m", "pm_flow.mcp_server"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    cwd=repo_root,
)
request_id = 0


def send(frame):
    server.stdin.write(json.dumps(frame, separators=(",", ":")) + "\n")
    server.stdin.flush()


def request(method, params=None):
    global request_id
    request_id += 1
    frame = {"jsonrpc": "2.0", "id": request_id, "method": method}
    if params is not None:
        frame["params"] = params
    send(frame)
    line = server.stdout.readline()
    assert line, f"MCP server exited while answering {method}"
    response = json.loads(line)
    assert response.get("jsonrpc") == "2.0", response
    assert response.get("id") == request_id, response
    return response


def call(name, arguments=None):
    response = request(
        "tools/call", {"name": name, "arguments": arguments or {}}
    )
    assert "error" not in response, response
    return response["result"]


def text(result):
    return "\n".join(item["text"] for item in result["content"] if item["type"] == "text")


def section_row(index, key):
    for line in index.splitlines():
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) >= 3 and cells[0] == key:
            return line
    raise AssertionError(f"section {key!r} missing from list_sections:\n{index}")


def section_is_done(index):
    cells = [cell.strip() for cell in section_row(index, section_key).strip().strip("|").split("|")]
    return cells[2] == "done"


def queued_section_keys(queue):
    keys = []
    for line in queue.splitlines():
        cells = line.split(maxsplit=2)
        if len(cells) == 3 and cells[0].isdigit() and cells[1] != "(project)":
            keys.append(cells[1])
    return keys


try:
    initialized = request(
        "initialize",
        {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "pm-flow-test", "version": "1"},
        },
    )
    assert initialized["result"]["capabilities"] == {"tools": {}}
    send({"jsonrpc": "2.0", "method": "notifications/initialized"})

    listed = request("tools/list", {})["result"]["tools"]
    names = {tool["name"] for tool in listed}
    expected = {"status", "next", "tick", "list_sections", "cost"}
    assert names == expected, names
    for tool in listed:
        schema = tool["inputSchema"]
        assert schema["additionalProperties"] is False
        expected_properties = {"project", "section"} if tool["name"] == "tick" else {"project"}
        assert set(schema["properties"]) == expected_properties

    bad_arguments = request(
        "tools/call",
        {"name": "status", "arguments": {"section": section_key}},
    )
    assert bad_arguments["error"]["code"] == -32602
    bad_tool = request("tools/call", {"name": "run", "arguments": {}})
    assert bad_tool["error"]["code"] == -32602

    project = {"project": project_key}
    targeted = {"project": project_key, "section": section_key}
    if mode == "lock":
        before = text(call("list_sections", project))
        refused = call("tick", project)
        after = text(call("list_sections", project))
        refused_text = text(refused)
        assert refused["isError"] is True
        assert "another pm_flow driver is already running" in refused_text, refused_text
        assert before == after
        report = {"tools": sorted(names), "lock": refused_text.strip()}
    elif mode == "budget":
        before = text(call("cost", project))
        refused = call("tick", targeted)
        after = text(call("cost", project))
        refused_text = text(refused)
        assert refused["isError"] is True
        assert "project budget exhausted" in refused_text
        assert before == after, "a dispatch was recorded behind the budget guard"
        report = {"tools": sorted(names), "budget": refused_text.strip()}
    else:
        assert call("status", project)["isError"] is False
        final_index = text(call("list_sections", project))
        for ticks in range(1, 33):
            queue = text(call("next", project))
            section_queue = queued_section_keys(queue)
            assert section_queue and section_queue[0] == unchanged_key, (
                f"control {unchanged_key!r} was not first in the section queue: "
                f"keys={section_queue!r}; next={queue!r}"
            )
            selected_before = section_row(final_index, section_key)
            unchanged_before = section_row(final_index, unchanged_key)
            tick_result = call("tick", targeted)
            assert tick_result["isError"] is False, text(tick_result)
            final_index = text(call("list_sections", project))
            selected_after = section_row(final_index, section_key)
            unchanged_after = section_row(final_index, unchanged_key)
            assert selected_after != selected_before, (
                "target row did not change after targeted tick: "
                f"before={selected_before!r}; after={selected_after!r}; "
                f"control_before={unchanged_before!r}; "
                f"control_after={unchanged_after!r}"
            )
            assert unchanged_after == unchanged_before, (
                "control row changed after targeted tick: "
                f"target_before={selected_before!r}; "
                f"target_after={selected_after!r}; "
                f"before={unchanged_before!r}; after={unchanged_after!r}"
            )
            if section_is_done(final_index):
                break
        else:
            raise AssertionError("MCP targeted tick loop did not converge in 32 ticks")
        assert call("cost", project)["isError"] is False
        report = {
            "tools": sorted(names),
            "ticks": ticks,
            "selection": True,
            "terminal": final_index,
        }
    print(json.dumps(report, separators=(",", ":")))
finally:
    server.stdin.close()
    returncode = server.wait(timeout=5)
    diagnostics = server.stderr.read()
    assert returncode == 0, diagnostics
PY
chmod +x "$TEST_ROOT/mcp_client.py"

# Prove mechanically that the client has exactly one process-spawning call and
# no alternate shell/process API. That one Popen is the MCP server above.
python3 - "$TEST_ROOT/mcp_client.py" <<'PY'
import ast
import sys
from pathlib import Path

tree = ast.parse(Path(sys.argv[1]).read_text())
process_calls = []
for node in ast.walk(tree):
    if not isinstance(node, ast.Call):
        continue
    function = node.func
    if isinstance(function, ast.Attribute) and isinstance(function.value, ast.Name):
        if function.value.id in {"subprocess", "os"}:
            process_calls.append((function.value.id, function.attr))
assert process_calls == [("subprocess", "Popen")], process_calls
PY
printf 'PASS: MCP client has no shell or state-reading escape hatch\n'

cat > "$TEST_ROOT/lock_holder.py" <<'PY'
import fcntl
import signal
import sys

lock_path, ready_path = sys.argv[1:]
with open(lock_path, "a+") as lock:
    fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
    with open(ready_path, "w") as ready:
        ready.write("ready\n")
    while True:
        signal.pause()
PY

MCP_LOCK_READY="$TEST_ROOT/mcp-lock.ready"
/usr/bin/python3 "$TEST_ROOT/lock_holder.py" \
  "$MCP_PROJECT_DIR/.driver.lock" "$MCP_LOCK_READY" &
LOCK_HOLDER_PID=$!
for _ in {1..100}; do
  [[ -f "$MCP_LOCK_READY" ]] && break
  sleep 0.01
done
[[ -f "$MCP_LOCK_READY" ]] || fail "MCP driver lock holder did not become ready"
lock_result="$(PM_DONE_FLAG="$MCP_DONE_FLAG" \
  PATH="$VENV/bin:$MCP_DRIVER_BIN:/usr/bin:/bin" \
  "$VENV/bin/python" "$TEST_ROOT/mcp_client.py" \
  "$MCP_REPO" cycle-repo selected-widget undispatched-widget lock)"
kill "$LOCK_HOLDER_PID" 2>/dev/null || true
wait "$LOCK_HOLDER_PID" 2>/dev/null || true
LOCK_HOLDER_PID=""
assert_contains "$lock_result" "another pm_flow driver is already running" \
  "MCP lock tool error"
printf 'PASS: MCP tick reports the driver lock as a tool error without advancing\n'

# While selected-widget is still actionable, seed prior spend and put the
# ceiling below it. The budget-mode client compares cost output across the
# refused tick, proving no attempt was recorded, then the ceiling is removed so
# the same two-section project can proceed through the named drive.
budget_run="$("$VENV/bin/python" "$INSTALLED_ENGINE/telemetry.py" \
  --db "$MCP_PROJECT_DIR/runs/pm_flow.db" \
  run-start --project cycle-repo --run-key mcp-budget-seed)"
budget_run_id="$(printf '%s\n' "$budget_run" | sed -n 's/^run_id=//p')"
budget_attempt="$("$VENV/bin/python" "$INSTALLED_ENGINE/telemetry.py" \
  --db "$MCP_PROJECT_DIR/runs/pm_flow.db" \
  attempt-start --run "$budget_run_id" --role developer --task selected-widget --label seed)"
budget_attempt_id="$(printf '%s\n' "$budget_attempt" | sed -n 's/^attempt_id=//p')"
"$VENV/bin/python" "$INSTALLED_ENGINE/telemetry.py" \
  --db "$MCP_PROJECT_DIR/runs/pm_flow.db" \
  attempt-end --attempt "$budget_attempt_id" --cost-usd 1 >/dev/null
"$VENV/bin/python" - "$MCP_FLOW/config.json" <<'PYCFG'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
config = json.loads(path.read_text())
config.setdefault("budget", {})["max_usd"] = 0.01
path.write_text(json.dumps(config, indent=2) + "\n")
PYCFG

budget_result="$(PM_DONE_FLAG="$MCP_DONE_FLAG" \
  PATH="$VENV/bin:$MCP_DRIVER_BIN:/usr/bin:/bin" \
  "$VENV/bin/python" "$TEST_ROOT/mcp_client.py" \
  "$MCP_REPO" cycle-repo selected-widget undispatched-widget budget)"
assert_contains "$budget_result" "project budget exhausted" "MCP budget tool error"
printf 'PASS: MCP tick reports budget exhaustion as a tool error without dispatching\n'
"$VENV/bin/python" - "$MCP_FLOW/config.json" <<'PYCFG'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
config = json.loads(path.read_text())
config.get("budget", {}).pop("max_usd", None)
path.write_text(json.dumps(config, indent=2) + "\n")
PYCFG

drive_result="$(PM_DONE_FLAG="$MCP_DONE_FLAG" \
  PATH="$VENV/bin:$MCP_DRIVER_BIN:/usr/bin:/bin" \
  "$VENV/bin/python" "$TEST_ROOT/mcp_client.py" \
  "$MCP_REPO" cycle-repo selected-widget undispatched-widget drive)"
[[ "$(printf '%s' "$drive_result" | field tools)" == \
  "['cost', 'list_sections', 'next', 'status', 'tick']" ]] || fail "MCP tool set"
[[ "$(printf '%s' "$drive_result" | field selection)" == "True" ]] || \
  fail "MCP named-section discrimination"
assert_contains "$(printf '%s' "$drive_result" | field terminal)" \
  "| selected-widget | must-have | done |" "MCP terminal section reading"
printf 'PASS: MCP lists exactly five tools and drives a section to done\n'
printf 'PASS: MCP targets one named section and leaves the other unchanged\n'

printf 'PASS: agent bindings MCP suite\n'
