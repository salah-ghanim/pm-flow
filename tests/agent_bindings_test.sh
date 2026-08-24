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
print(json.dumps({
    "jsonrpc": "2.0", "method": "session/update",
    "params": {"sessionId": "test-session", "update": {
        "sessionUpdate": "usage_update", "used": 7, "size": 100}}}), flush=True)
reply(request, {"stopReason": "end_turn"})
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
assert_contains "$healthy" '"used":7' "healthy usage"
printf 'PASS: sandbox capability yields enforceable=true for write\n'

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

# The public driver keeps its managing roles on the existing claude fixture and
# binds only the developer to ACP. This proves the adapter inside a real cycle,
# including telemetry and the accepted result body.
CYCLE_REPO="$TEST_ROOT/cycle repo"
mkdir "$CYCLE_REPO"
"$REPO_ROOT/install.sh" "$CYCLE_REPO" --name "ACP Binding Project" > "$TEST_ROOT/cycle-install.out"
CYCLE_PM=(env PM_FLOW_REPO_ROOT="$CYCLE_REPO" PYTHONPATH="$REPO_ROOT/src" python3 -m pm_flow.cli)
CYCLE_FLOW="$CYCLE_REPO/.agentic/pm_flow"
CYCLE_SECTION="$CYCLE_FLOW/cycle-repo/sections/widget"
ENFORCED_MARKER="$TEST_ROOT/enforced-access.marker"

python3 - "$CYCLE_FLOW/config.json" "$TEST_ROOT/acp_agent.py" "$ENFORCED_MARKER" <<'PYCFG'
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
path.write_text(json.dumps(config, indent=2) + "\n")
PYCFG

"${CYCLE_PM[@]}" init-section widget <<'SECTIONBRIEF' > "$TEST_ROOT/cycle-section.out"
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

mkdir "$TEST_ROOT/driver-bin"
/bin/cp "$REPO_ROOT/tests/fixtures/stub_success.zsh" "$TEST_ROOT/driver-bin/claude"
chmod +x "$TEST_ROOT/driver-bin/claude"

drain_project_work() {
  local guard=0
  while [[ "$("${CYCLE_PM[@]}" status)" == *"portfolio review due"* ]]; do
    (( guard += 1 ))
    (( guard <= 8 )) || fail "the portfolio review queue would not drain"
    PM_DONE_FLAG="$TEST_ROOT/cycle-complete.flag" \
      PATH="$TEST_ROOT/driver-bin:$PATH" "${CYCLE_PM[@]}" tick > /dev/null 2>&1
  done
}

run_driver() {
  PM_DONE_FLAG="$TEST_ROOT/cycle-complete.flag" \
    PATH="$TEST_ROOT/driver-bin:$PATH" "${CYCLE_PM[@]}" run --max-ticks "${1:-12}" 2>&1
}

drain_project_work
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

cost_output="$("${CYCLE_PM[@]}" cost)"
printf '%s\n' "$cost_output" | awk -F'\t' \
  '$1 == "ATTEMPT" && $4 == "developer" && $6 == "acp" {found=1} END {exit !found}' || \
  fail "cost has no ACP developer attempt"
printf '%s\n' "$cost_output" | awk -F'\t' \
  '$1 == "ATTEMPT" && $6 == "claude" {found=1} END {exit !found}' || \
  fail "cost has no claude attempt"
printf 'PASS: cost distinguishes ACP and claude transports\n'

# Rebind the same seat to an agent declaring no boundary. Its successful
# capability-missing outcome must still dispatch, and the marker is the proof
# that prompt-level access was recorded before the prompt arrived.
PROMPT_LEVEL_MARKER="$TEST_ROOT/prompt-level-access.marker"
python3 - "$CYCLE_FLOW/config.json" "$TEST_ROOT/acp_agent.py" "$PROMPT_LEVEL_MARKER" <<'PYCFG'
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
PM_FLOW_ENGINE_ROOT="$REPO_ROOT/template/.agentic/pm_flow" \
PM_FLOW_FLOW_DIR="$CYCLE_FLOW" PM_FLOW_REPO_ROOT="$CYCLE_REPO" \
  zsh "$REPO_ROOT/template/.agentic/pm_flow/agent_exec.sh" developer \
    --prompt-file "$TEST_ROOT/prompt-level-prompt.md" \
    --output "$TEST_ROOT/prompt-level-response.json"
[[ "$(field is_error < "$TEST_ROOT/prompt-level-response.json")" == "False" ]] || \
  fail "prompt-level ACP dispatch was treated as a failure"
assert_contains "$(field result < "$TEST_ROOT/prompt-level-response.json")" "Built through ACP." \
  "prompt-level response contains agent text"
assert_contains "$(/bin/cat "$PROMPT_LEVEL_MARKER")" '"access":"prompt-level"' \
  "prompt-level record exists before session/prompt"
printf 'PASS: prompt-level ACP access is recorded before work and still dispatches\n'

configure_failure_mode() {
  python3 - "$CYCLE_FLOW/config.json" "$TEST_ROOT/acp_agent.py" "$1" "$2" "$3" <<'PYCFG'
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
  if PM_FLOW_ENGINE_ROOT="$REPO_ROOT/template/.agentic/pm_flow" \
      PM_FLOW_FLOW_DIR="$CYCLE_FLOW" PM_FLOW_REPO_ROOT="$CYCLE_REPO" \
      zsh "$REPO_ROOT/template/.agentic/pm_flow/agent_exec.sh" developer \
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

printf 'PASS: agent bindings ACP suite\n'

# A second installed project is driven only through the MCP server after the
# client starts. Setup remains outside the client, and every role uses the same
# existing successful agent fixture.
MCP_REPO="$TEST_ROOT/mcp repo"
mkdir "$MCP_REPO"
"$REPO_ROOT/install.sh" "$MCP_REPO" --name "MCP Binding Project" > "$TEST_ROOT/mcp-install.out"
MCP_PM=(env PM_FLOW_REPO_ROOT="$MCP_REPO" PYTHONPATH="$REPO_ROOT/src" python3 -m pm_flow.cli)
MCP_FLOW="$MCP_REPO/.agentic/pm_flow"
MCP_PROJECT_DIR="$MCP_FLOW/mcp-repo"
MCP_DRIVER_BIN="$TEST_ROOT/mcp-driver-bin"
MCP_DONE_FLAG="$TEST_ROOT/mcp-complete.flag"
mkdir "$MCP_DRIVER_BIN"
/bin/cp "$REPO_ROOT/tests/fixtures/stub_success.zsh" "$MCP_DRIVER_BIN/claude"
chmod +x "$MCP_DRIVER_BIN/claude"

python3 - "$MCP_FLOW/config.json" <<'PYCFG'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
config = json.loads(path.read_text())
for role in config["roles"]:
    config["roles"][role] = {"cli": "claude", "model": "", "difficulty": "low"}
# Force project work to recur during the drive so the client cannot assume
# that every tick advances its section.
config.setdefault("governance", {})["portfolio_review_dispatches"] = 1
path.write_text(json.dumps(config, indent=2) + "\n")
PYCFG

"${MCP_PM[@]}" init-section mcp-widget <<'SECTIONBRIEF' > "$TEST_ROOT/mcp-section.out"
## Objective

- Build the MCP widget.

## Scope

- The MCP widget only.

## Priority

- must-have: prove the MCP client can drive a section

## Owned paths

- `src/mcp-widget/**`

## Dependencies

- None.

## Acceptance

- The MCP-driven section reaches done.

## Rejection conditions

- The client reads project state outside an MCP tool result.
SECTIONBRIEF

cat > "$TEST_ROOT/mcp_client.py" <<'PY'
#!/usr/bin/env python3
import json
import os
import subprocess
import sys


repo_root, project_key, section_key, mode = sys.argv[1:]
environment = dict(os.environ)
environment["PM_FLOW_REPO_ROOT"] = repo_root
server = subprocess.Popen(
    [sys.executable, "-m", "pm_flow.mcp_server"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    env=environment,
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


def section_is_done(index):
    for line in index.splitlines():
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) >= 3 and cells[0] == section_key and cells[2] == "done":
            return True
    return False


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
        assert call("next", project)["isError"] is False
        final_index = ""
        ticks = 0
        for ticks in range(1, 33):
            tick_result = call("tick", project)
            assert tick_result["isError"] is False, text(tick_result)
            final_index = text(call("list_sections", project))
            if section_is_done(final_index):
                break
        else:
            raise AssertionError("MCP tick loop did not converge in 32 ticks")
        assert call("cost", project)["isError"] is False
        report = {"tools": sorted(names), "ticks": ticks, "terminal": final_index}
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
lock_result="$(PM_DONE_FLAG="$MCP_DONE_FLAG" PATH="$MCP_DRIVER_BIN:/usr/bin:/bin" \
  PYTHONPATH="$REPO_ROOT/src" /usr/bin/python3 "$TEST_ROOT/mcp_client.py" \
  "$MCP_REPO" mcp-repo mcp-widget lock)"
kill "$LOCK_HOLDER_PID" 2>/dev/null || true
wait "$LOCK_HOLDER_PID" 2>/dev/null || true
LOCK_HOLDER_PID=""
assert_contains "$lock_result" "another pm_flow driver is already running" \
  "MCP lock tool error"
printf 'PASS: MCP tick reports the driver lock as a tool error without advancing\n'

drive_result="$(PM_DONE_FLAG="$MCP_DONE_FLAG" PATH="$MCP_DRIVER_BIN:/usr/bin:/bin" \
  PYTHONPATH="$REPO_ROOT/src" /usr/bin/python3 "$TEST_ROOT/mcp_client.py" \
  "$MCP_REPO" mcp-repo mcp-widget drive)"
[[ "$(printf '%s' "$drive_result" | field tools)" == \
  "['cost', 'list_sections', 'next', 'status', 'tick']" ]] || fail "MCP tool set"
assert_contains "$(printf '%s' "$drive_result" | field terminal)" \
  "| mcp-widget | must-have | done |" "MCP terminal section reading"
printf 'PASS: MCP lists exactly five tools and drives a section to done\n'

# Leave a second section actionable, record prior spend, and put the ceiling
# below it. The budget-mode client compares cost tool output across the refused
# tick, proving that no attempt was recorded.
"${MCP_PM[@]}" init-section budget-widget <<'SECTIONBRIEF' > "$TEST_ROOT/mcp-budget-section.out"
## Objective

- Exercise the project budget guard.

## Scope

- The budget guard only.

## Priority

- must-have: exhausted projects do not dispatch

## Owned paths

- `src/budget-widget/**`

## Dependencies

- None.

## Acceptance

- Tick refuses before dispatch.

## Rejection conditions

- Any dispatch is recorded.
SECTIONBRIEF

budget_run="$(python3 "$REPO_ROOT/template/.agentic/pm_flow/telemetry.py" \
  --db "$MCP_PROJECT_DIR/runs/pm_flow.db" \
  run-start --project mcp-repo --run-key mcp-budget-seed)"
budget_run_id="$(printf '%s\n' "$budget_run" | sed -n 's/^run_id=//p')"
budget_attempt="$(python3 "$REPO_ROOT/template/.agentic/pm_flow/telemetry.py" \
  --db "$MCP_PROJECT_DIR/runs/pm_flow.db" \
  attempt-start --run "$budget_run_id" --role developer --task budget-widget --label seed)"
budget_attempt_id="$(printf '%s\n' "$budget_attempt" | sed -n 's/^attempt_id=//p')"
python3 "$REPO_ROOT/template/.agentic/pm_flow/telemetry.py" \
  --db "$MCP_PROJECT_DIR/runs/pm_flow.db" \
  attempt-end --attempt "$budget_attempt_id" --cost-usd 1 >/dev/null
python3 - "$MCP_FLOW/config.json" <<'PYCFG'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
config = json.loads(path.read_text())
config.setdefault("budget", {})["max_usd"] = 0.01
path.write_text(json.dumps(config, indent=2) + "\n")
PYCFG

budget_result="$(PM_DONE_FLAG="$MCP_DONE_FLAG" PATH="$MCP_DRIVER_BIN:/usr/bin:/bin" \
  PYTHONPATH="$REPO_ROOT/src" /usr/bin/python3 "$TEST_ROOT/mcp_client.py" \
  "$MCP_REPO" mcp-repo budget-widget budget)"
assert_contains "$budget_result" "project budget exhausted" "MCP budget tool error"
printf 'PASS: MCP tick reports budget exhaustion as a tool error without dispatching\n'

printf 'PASS: agent bindings MCP suite\n'
