#!/bin/zsh -f
set -euo pipefail
unsetopt BG_NICE

REPO_ROOT="$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pm-flow-agent-bindings.XXXXXX")"
case "$TEST_ROOT" in
  */pm-flow-agent-bindings.*) ;;
  *) printf 'unsafe test temp directory: %s\n' "$TEST_ROOT" >&2; exit 1 ;;
esac
trap 'rm -rf -- "$TEST_ROOT"' EXIT

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
if mode == "invalid_json":
    print("not-json", flush=True)
    raise SystemExit(0)
if mode == "invalid_envelope":
    print(json.dumps({"result": {}}), flush=True)
    raise SystemExit(0)
capabilities = {} if mode == "no_sandbox" else {"_meta": {"sandbox": True}}
reply(request, {"protocolVersion": 1, "agentCapabilities": capabilities})

request = read_frame()
assert request["method"] == "session/new"
assert os.path.isabs(request["params"]["cwd"])
assert request["params"]["mcpServers"] == []
reply(request, {"sessionId": "test-session"})

request = read_frame()
assert request["method"] == "session/prompt"
assert request["params"]["sessionId"] == "test-session"
assert request["params"]["prompt"] == [{"type": "text", "text": "hello ACP"}]
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

print(json.dumps({
    "jsonrpc": "2.0", "method": "session/update",
    "params": {"sessionId": "test-session", "update": {
        "sessionUpdate": "agent_message_chunk",
        "content": {"type": "text", "text": "agent reply"}}}}), flush=True)
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

printf 'PASS: agent bindings ACP suite\n'
