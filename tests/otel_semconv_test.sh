#!/bin/zsh -f
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
unsetopt BG_NICE

for name in ${(k)parameters[(I)PM_FLOW_*]}; do
  unset "$name"
done

REPO_ROOT="$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/otel-semconv-test.XXXXXX")"
TEST_ROOT="$(cd -P "$TEST_ROOT" && pwd -P)"
case "$TEST_ROOT" in
  */otel-semconv-test.*) ;;
  *) printf 'unsafe test temp directory: %s\n' "$TEST_ROOT" >&2; exit 1 ;;
esac

RECEIVER_PID=""
cleanup() {
  if [[ -n "${RECEIVER_PID:-}" ]]; then
    kill "$RECEIVER_PID" >/dev/null 2>&1 || true
    wait "$RECEIVER_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "${TEST_ROOT:-}" && -d "$TEST_ROOT" && \
        "$(basename "$TEST_ROOT")" == otel-semconv-test.* ]]; then
    rm -rf -- "$TEST_ROOT"
  fi
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

wait_for_file() {
  local target="$1" tries=0
  while [[ ! -s "$target" ]]; do
    (( tries += 1 ))
    (( tries <= 100 )) || fail "timed out waiting for $target"
    sleep 0.05
  done
}

wait_for_payload_count() {
  local wanted="$1" tries=0 count
  while true; do
    count="$(python3 - "$RECEIVED" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
print(len(path.read_text().splitlines()) if path.exists() else 0)
PY
)"
    (( count >= wanted )) && return 0
    (( tries += 1 ))
    (( tries <= 100 )) || fail "receiver got $count payloads, expected $wanted"
    sleep 0.05
  done
}

copy_checkout_layout() {
  local destination="$1"
  mkdir -p "$destination/template/.agentic" "$destination/src/pm_flow"
  cp -R "$REPO_ROOT/template/.agentic/pm_flow" \
    "$destination/template/.agentic/pm_flow"
  cp "$REPO_ROOT/src/pm_flow/semconv.py" "$destination/src/pm_flow/semconv.py"
}

resolved_semconv_path() {
  local telemetry="$1"
  python3 - "$telemetry" <<'PY'
import importlib.util
import sys
from pathlib import Path

path = Path(sys.argv[1]).resolve()
spec = importlib.util.spec_from_file_location("otel_semconv_telemetry", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
print(module.SEMCONV_PATH or "")
PY
}

RECEIVER="$TEST_ROOT/receiver.py"
PORT_FILE="$TEST_ROOT/receiver.port"
RECEIVED="$TEST_ROOT/received.jsonl"
cat > "$RECEIVER" <<'PY'
import gzip
import json
import os
import socketserver
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

port_file = Path(sys.argv[1])
received_file = Path(sys.argv[2])


def record(payload):
    with received_file.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, sort_keys=True) + "\n")


def proto_value(value):
    selected = value.WhichOneof("value")
    return getattr(value, selected) if selected else None


def from_protobuf(body):
    from opentelemetry.proto.collector.trace.v1.trace_service_pb2 import (
        ExportTraceServiceRequest,
    )

    request = ExportTraceServiceRequest()
    request.ParseFromString(body)
    spans = []
    for resource in request.resource_spans:
        for scope in resource.scope_spans:
            for span in scope.spans:
                spans.append({
                    "traceId": span.trace_id.hex(),
                    "spanId": span.span_id.hex(),
                    "parentSpanId": span.parent_span_id.hex(),
                    "name": span.name,
                    "attributes": {
                        item.key: proto_value(item.value) for item in span.attributes
                    },
                })
    return {"spans": spans}


def json_value(value):
    for key in (
        "stringValue", "boolValue", "intValue", "doubleValue", "bytesValue"
    ):
        if key in value:
            result = value[key]
            return int(result) if key == "intValue" else result
    return None


def from_json(body):
    request = json.loads(body)
    spans = []
    for resource in request.get("resourceSpans", []):
        scopes = resource.get("scopeSpans") or resource.get("instrumentationLibrarySpans") or []
        for scope in scopes:
            for span in scope.get("spans", []):
                spans.append({
                    "traceId": span.get("traceId", ""),
                    "spanId": span.get("spanId", ""),
                    "parentSpanId": span.get("parentSpanId", ""),
                    "name": span.get("name", ""),
                    "attributes": {
                        item["key"]: json_value(item.get("value", {}))
                        for item in span.get("attributes", [])
                    },
                })
    return {"spans": spans}


class Receiver(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/v1/traces":
            self.send_error(404)
            return
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        if self.headers.get("Content-Encoding", "").lower() == "gzip":
            body = gzip.decompress(body)
        content_type = self.headers.get("Content-Type", "").lower()
        payload = from_json(body.decode()) if "json" in content_type else from_protobuf(body)
        record(payload)
        self.send_response(200)
        if "json" in content_type:
            self.send_header("Content-Type", "application/json")
            response = b"{}"
        else:
            self.send_header("Content-Type", "application/x-protobuf")
            response = b""
        self.send_header("Content-Length", str(len(response)))
        self.end_headers()
        self.wfile.write(response)

    def log_message(self, *_args):
        pass


try:
    server = ThreadingHTTPServer(("127.0.0.1", 0), Receiver)
except PermissionError:
    class UnixHTTPServer(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
        daemon_threads = True

    socket_path = str(port_file.with_suffix(".sock"))
    try:
        os.unlink(socket_path)
    except FileNotFoundError:
        pass
    try:
        server = UnixHTTPServer(socket_path, Receiver)
    except PermissionError:
        fifo_path = str(port_file.with_suffix(".fifo"))
        try:
            os.unlink(fifo_path)
        except FileNotFoundError:
            pass
        os.mkfifo(fifo_path)
        port_file.write_text("pipe:" + fifo_path)
        while True:
            with open(fifo_path, "rb") as stream:
                request = stream.read()
            if not request:
                continue
            head, separator, body = request.partition(b"\r\n\r\n")
            if not separator or not head.startswith(b"POST /v1/traces HTTP/1.1\r\n"):
                raise SystemExit("fallback receiver got a malformed HTTP request")
            record(from_json(body.decode()))
    else:
        port_file.write_text("unix:" + socket_path)
else:
    port_file.write_text("tcp:" + str(server.server_address[1]))
server.serve_forever()
PY

python3 "$RECEIVER" "$PORT_FILE" "$RECEIVED" &
RECEIVER_PID=$!
wait_for_file "$PORT_FILE"
RECEIVER_ADDRESS="$(<"$PORT_FILE")"
RECEIVER_CURL_ARGS=()
case "$RECEIVER_ADDRESS" in
  tcp:*) ENDPOINT="http://127.0.0.1:${RECEIVER_ADDRESS#tcp:}" ;;
  unix:*)
    ENDPOINT="http://localhost"
    RECEIVER_CURL_ARGS=(--unix-socket "${RECEIVER_ADDRESS#unix:}")
    ;;
  pipe:*) ENDPOINT="http://localhost" ;;
  *) fail "receiver reported an unknown address: $RECEIVER_ADDRESS" ;;
esac

if python3 - <<'PY' >/dev/null 2>&1
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.proto.collector.trace.v1.trace_service_pb2 import ExportTraceServiceRequest
from opentelemetry.sdk.trace import ReadableSpan
PY
then
  [[ "$RECEIVER_ADDRESS" == tcp:* ]] || \
    fail "SDK imports are available but this host prohibited the OTLP TCP receiver"
  EXPORT_ROUTE="SDK OTLP/HTTP via trace_export.py"
else
  if [[ "$RECEIVER_ADDRESS" == unix:* ]]; then
    EXPORT_ROUTE="stdlib OTLP/JSON fallback via trace_export.py --file --replay (HTTP over Unix socket)"
  elif [[ "$RECEIVER_ADDRESS" == pipe:* ]]; then
    EXPORT_ROUTE="stdlib OTLP/JSON fallback via trace_export.py --file --replay (HTTP request stream; bind prohibited)"
  else
    EXPORT_ROUTE="stdlib OTLP/JSON fallback via trace_export.py --file --replay"
  fi
fi
printf 'ROUTE: %s\n' "$EXPORT_ROUTE"

write_stub() {
  local target="$1"
  cat > "$target" <<'ZSH'
#!/bin/zsh -f
prompt="${@[-1]}"
workplan="$(printf '%s\n' "$prompt" | sed -n 's/^- *`\{0,1\}\([^`]*workplan\.md\)`\{0,1\} *$/\1/p' | head -n 1)"
if [[ -n "$workplan" ]]; then
  [[ "$workplan" == /* ]] || workplan="${PROJECT_ROOT:-$PWD}/$workplan"
  if [[ -f "$workplan" ]]; then
    grep -v 'pm-flow-workplan-template' "$workplan" > "$workplan.tmp"
    mv "$workplan.tmp" "$workplan"
  fi
fi
python3 - <<'PY'
import json

print(json.dumps({
    "is_error": False,
    "result": """## Where the section stands
Starting.

## Workplan task
T1

## Assignment
Build the bounded fixture.

## Acceptance
Tests pass.

## Rejection conditions
Scope drift.

## Decision
ASSIGN - first piece""",
    "session_id": "",
    "total_cost_usd": 0.25,
    "usage": {"input_tokens": 31, "output_tokens": 13},
}))
PY
ZSH
  chmod +x "$target"
}

drive_dispatch() {
  local tree="$1" fixture="$2" name="$3"
  local engine="$tree/template/.agentic/pm_flow"
  local flow="$fixture/.agentic/pm_flow"
  local stub_dir="$fixture/stub-bin"
  local config="$flow/config.json"
  local project_key db

  mkdir -p "$fixture" "$stub_dir"
  "$REPO_ROOT/install.sh" "$fixture" --name "$name" >/dev/null
  write_stub "$stub_dir/claude"
  python3 - "$config" "$ENDPOINT" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
config = json.loads(path.read_text())
for role in ("cpo", "pm", "developer", "10x_developer"):
    config["roles"][role] = {"cli": "claude", "model": "fixture-model", "difficulty": "low"}
config["telemetry"] = {"enabled": True, "otlp_endpoint": sys.argv[2]}
config["supervision"] = {
    "heartbeat_stall_seconds": 30,
    "max_attempts": 1,
    "retry_backoff_seconds": 1,
    "usage_limit_pause_seconds": 1,
}
path.write_text(json.dumps(config, indent=2) + "\n")
PY

  local pm=(env PM_FLOW_ENGINE_ROOT="$engine" PM_FLOW_FLOW_DIR="$flow" \
    PM_FLOW_REPO_ROOT="$fixture" zsh -f "$engine/pm_flow.sh")
  "${pm[@]}" init-section receiver-proof <<'BRIEF' >/dev/null
## Objective

- Exercise one public driver dispatch.

## Scope

- The disposable fixture only.

## Priority

- must-have: the receiver needs a real dispatch.

## Owned paths

- `fixture/**`

## Dependencies

- None.

## Acceptance

- The stub response is recorded.

## Rejection conditions

- No dispatch occurs.
BRIEF
  PATH="$stub_dir:$PATH" "${pm[@]}" tick >/dev/null

  project_key="$(head -n 1 "$flow/.project-key")"
  db="$flow/$project_key/runs/pm_flow.db"
  [[ -f "$db" ]] || fail "driver did not create its telemetry store"
  printf '%s\n' "$db"
}

export_tree() {
  local tree="$1" db="$2" ordinal="$3"
  local exporter="$tree/template/.agentic/pm_flow/trace_export.py"
  if [[ "$EXPORT_ROUTE" == SDK* ]]; then
    python3 "$exporter" --db "$db" --otlp "$ENDPOINT" --replay >/dev/null
  else
    local payloads="$tree/trace.otlp.jsonl"
    python3 "$exporter" --db "$db" --file "$payloads" --replay >/dev/null
    while IFS= read -r payload; do
      if [[ "$RECEIVER_ADDRESS" == pipe:* ]]; then
        python3 - "${RECEIVER_ADDRESS#pipe:}" "$payload" <<'PY'
import sys

target, payload = sys.argv[1:]
body = payload.encode()
request = (
    b"POST /v1/traces HTTP/1.1\r\n"
    b"Host: localhost\r\n"
    b"Content-Type: application/json\r\n"
    + f"Content-Length: {len(body)}\r\n\r\n".encode()
    + body
)
with open(target, "wb") as stream:
    stream.write(request)
PY
      else
        curl --fail --silent --show-error \
          "${RECEIVER_CURL_ARGS[@]}" \
          -H 'Content-Type: application/json' --data-binary "$payload" \
          "$ENDPOINT/v1/traces" >/dev/null
      fi
    done < "$payloads"
  fi
  wait_for_payload_count "$ordinal"
}

assert_received_tree() {
  local ordinal="$1" db="$2" semconv="$3" provider_suffix="$4"
  local forbidden_provider_suffix="$5" label="$6"
  python3 - "$RECEIVED" "$ordinal" "$db" "$semconv" "$provider_suffix" \
    "$forbidden_provider_suffix" "$label" <<'PY'
import importlib.util
import json
import sqlite3
import sys
from pathlib import Path

received, ordinal, db, semconv_path, provider_suffix, forbidden_suffix, label = sys.argv[1:]
payload = json.loads(Path(received).read_text().splitlines()[int(ordinal) - 1])
spans = payload["spans"]
prefix = "gen" + "_ai."
operation_key = prefix + "operation.name"
revision_key = "pm_flow.semconv.revision"

spec = importlib.util.spec_from_file_location("otel_semconv_pin", semconv_path)
semconv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(semconv)

parents = [span for span in spans if span["attributes"].get(operation_key) == "invoke_agent"]
if len(parents) != 1:
    raise SystemExit(f"{label}: expected one invoke_agent span, got {len(parents)}")
parent = parents[0]
children = [
    span for span in spans
    if span["parentSpanId"] == parent["spanId"]
    and span["attributes"].get(operation_key) == "chat"
]
if len(children) != 1:
    raise SystemExit(f"{label}: expected exactly one chat child, got {len(children)}")
child = children[0]

for span in spans:
    revision = span["attributes"].get(revision_key)
    if revision != semconv.REVISION:
        raise SystemExit(
            f"{label}: span {span['spanId']} revision is {revision!r}, "
            f"expected {semconv.REVISION!r}"
        )

provider_key = prefix + provider_suffix
forbidden_key = prefix + forbidden_suffix
for span in (parent, child):
    if span["attributes"].get(provider_key) != "anthropic":
        raise SystemExit(f"{label}: {provider_key} missing from {span['spanId']}")
    if forbidden_key in span["attributes"]:
        raise SystemExit(f"{label}: unexpected provider attribute {forbidden_key}")

input_key = prefix + "usage.input_tokens"
output_key = prefix + "usage.output_tokens"
if input_key in parent["attributes"] or output_key in parent["attributes"]:
    raise SystemExit(f"{label}: convention usage remained on invoke_agent parent")

connection = sqlite3.connect(db)
connection.row_factory = sqlite3.Row
attempt = connection.execute(
    "SELECT a.input_tokens, a.output_tokens FROM spans child "
    "JOIN attempts a ON child.parent_span_id = a.span_id "
    "WHERE child.span_id = ?",
    (child["spanId"],),
).fetchone()
if attempt is None:
    raise SystemExit(f"{label}: chat child did not join to its attempts row")
expected_input = attempt["input_tokens"]
expected_output = attempt["output_tokens"]
if child["attributes"].get(input_key) != expected_input:
    raise SystemExit(
        f"{label}: child input usage is {child['attributes'].get(input_key)!r}, "
        f"attempt has {expected_input!r}"
    )
if child["attributes"].get(output_key) != expected_output:
    raise SystemExit(
        f"{label}: child output usage is {child['attributes'].get(output_key)!r}, "
        f"attempt has {expected_output!r}"
    )
if child["attributes"].get("openinference.span.kind") != "LLM":
    raise SystemExit(f"{label}: child lost openinference.span.kind=LLM")
if not child["attributes"].get("llm.model_name"):
    raise SystemExit(f"{label}: child lost llm.model_name")

parent_only_candidates = (
    "llm.token_count.prompt",
    "llm.token_count.completion",
    "llm.token_count.total",
    "pm_flow.cost_usd",
    "pm_flow.cache_read_tokens",
    "pm_flow.cache_write_tokens",
    "pm_flow.reasoning_tokens",
    "input.value",
    "input.mime_type",
    "output.value",
    "output.mime_type",
)
produced_parent_only = [
    key for key in parent_only_candidates
    if key in parent["attributes"] or key in child["attributes"]
]
for key in produced_parent_only:
    if key not in parent["attributes"]:
        raise SystemExit(f"{label}: {key} moved off the invoke_agent parent")
for key in parent_only_candidates:
    if key in child["attributes"]:
        raise SystemExit(f"{label}: non-convention attribute duplicated on chat child: {key}")

if parent["attributes"].get("llm.token_count.prompt") != expected_input:
    raise SystemExit(f"{label}: parent llm prompt token count changed")
if parent["attributes"].get("llm.token_count.completion") != expected_output:
    raise SystemExit(f"{label}: parent llm completion token count changed")

print(
    f"TREE {label}: {parent['spanId']} invoke_agent -> "
    f"{child['spanId']} chat parent={child['parentSpanId']} "
    f"input_tokens={expected_input} output_tokens={expected_output}"
)
print(
    f"SPLIT {label}: parent_only={','.join(produced_parent_only)} "
    f"child_kept={input_key},{output_key},openinference.span.kind,llm.model_name"
)
PY
}

PRIMARY_TREE="$TEST_ROOT/primary"
SECONDARY_TREE="$TEST_ROOT/secondary"
copy_checkout_layout "$PRIMARY_TREE"
cp -R "$PRIMARY_TREE" "$SECONDARY_TREE"

PRIMARY_TELEMETRY="$PRIMARY_TREE/template/.agentic/pm_flow/telemetry.py"
PRIMARY_SEMCONV="$PRIMARY_TREE/src/pm_flow/semconv.py"
primary_resolved="$(resolved_semconv_path "$PRIMARY_TELEMETRY")"
[[ "$primary_resolved" == "$(cd -P "${PRIMARY_SEMCONV:h}" && pwd -P)/semconv.py" ]] || \
  fail "primary telemetry resolved the wrong semantic-convention module: $primary_resolved"
PRIMARY_DB="$(drive_dispatch "$PRIMARY_TREE" "$TEST_ROOT/primary-repo" "Semconv Primary")"
export_tree "$PRIMARY_TREE" "$PRIMARY_DB" 1
assert_received_tree 1 "$PRIMARY_DB" "$PRIMARY_SEMCONV" \
  "provider.name" "system" "primary"

SECONDARY_SEMCONV="$SECONDARY_TREE/src/pm_flow/semconv.py"
SECONDARY_TELEMETRY="$SECONDARY_TREE/template/.agentic/pm_flow/telemetry.py"
sed 's/^REVISION = "v1\.37\.0"$/REVISION = "v1.36.0"/' \
  "$SECONDARY_SEMCONV" > "$SECONDARY_SEMCONV.next"
mv "$SECONDARY_SEMCONV.next" "$SECONDARY_SEMCONV"
grep -q '^REVISION = "v1.36.0"$' "$SECONDARY_SEMCONV" || \
  fail "second semantic-convention pin was not applied"
secondary_resolved="$(resolved_semconv_path "$SECONDARY_TELEMETRY")"
[[ "$secondary_resolved" == "$(cd -P "${SECONDARY_SEMCONV:h}" && pwd -P)/semconv.py" ]] || \
  fail "secondary telemetry resolved the wrong semantic-convention module: $secondary_resolved"
printf 'resolved semconv.py: %s\n' "$secondary_resolved"
SECONDARY_DB="$(drive_dispatch "$SECONDARY_TREE" "$TEST_ROOT/secondary-repo" "Semconv Secondary")"
export_tree "$SECONDARY_TREE" "$SECONDARY_DB" 2
assert_received_tree 2 "$SECONDARY_DB" "$SECONDARY_SEMCONV" \
  "system" "provider.name" "secondary"

GEN_AI_PREFIX='gen''_ai\.'
A4_PERSONA_CARDS_COMMENT_EXEMPTION='template/.agentic/pm_flow/catalog.py'
a4_matches="$(cd "$REPO_ROOT" && grep -rn "$GEN_AI_PREFIX" template/ src/ \
  --include='*.py' --include='*.zsh' --include='*.sh' || true)"
while IFS= read -r match; do
  [[ -n "$match" ]] || continue
  case "$match" in
    src/pm_flow/semconv.py:*) ;;
    "$A4_PERSONA_CARDS_COMMENT_EXEMPTION":*)
      source_line="${match#*:}"
      source_line="${source_line#*:}"
      trimmed="$(printf '%s\n' "$source_line" | sed 's/^[[:space:]]*//')"
      [[ "$trimmed" == \#* ]] || \
        fail "persona-cards exemption matched a code line: $match"
      ;;
    *) fail "standard GenAI literal outside the mapping module: $match" ;;
  esac
done <<< "$a4_matches"

printf 'PASS: receiver decoded invoke_agent with exactly one chat child\n'
printf 'PASS: receiver usage equals the attempts row and stays off the parent\n'
printf 'PASS: non-convention usage and bodies stay only on the invoke_agent parent\n'
printf 'PASS: every received span carries its loaded revision\n'
printf 'PASS: changing only the pin changes the receiver provider attribute\n'
printf 'PASS: standard GenAI literals are centralised in semconv.py\n'
