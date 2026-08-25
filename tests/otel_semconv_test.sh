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
JAEGER_CONTAINER_ID=""
cleanup() {
  if [[ -n "${RECEIVER_PID:-}" ]]; then
    kill "$RECEIVER_PID" >/dev/null 2>&1 || true
    wait "$RECEIVER_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "${JAEGER_CONTAINER_ID:-}" ]]; then
    docker rm -f "$JAEGER_CONTAINER_ID" >/dev/null 2>&1 || true
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

received_trace_tree_present() {
  local trace_id="$1"
  python3 - "$RECEIVED" "$trace_id" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
trace_id = sys.argv[2]
spans_by_id = {}
if path.exists():
    for line in path.read_text().splitlines():
        try:
            payload = json.loads(line)
        except json.JSONDecodeError:
            continue
        for span in payload.get("spans", []):
            if span.get("traceId") == trace_id and span.get("spanId"):
                spans_by_id[span["spanId"]] = span

operation_key = "gen" + "_ai.operation.name"
parents = [
    span for span in spans_by_id.values()
    if span.get("attributes", {}).get(operation_key) == "invoke_agent"
]
present = any(
    span.get("parentSpanId") == parent["spanId"]
    and span.get("attributes", {}).get(operation_key) == "chat"
    for parent in parents
    for span in spans_by_id.values()
)
raise SystemExit(0 if present else 1)
PY
}

wait_for_trace_tree() {
  local trace_id="$1" tries=0
  while ! received_trace_tree_present "$trace_id"; do
    (( tries += 1 ))
    (( tries <= 100 )) || \
      fail "receiver never got trace $trace_id with invoke_agent parent and chat child"
    sleep 0.05
  done
}

jaeger_reachable() {
  [[ "$(curl -s --max-time 5 -o /dev/null -w '%{http_code}' \
    http://localhost:16686/api/services || true)" == 200 ]]
}

ensure_jaeger() {
  if jaeger_reachable; then
    return 0
  fi

  if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    printf '%s\n' \
      'SKIP: A6 requires docker run -d -p 4318:4318 -p 16686:16686 jaegertracing/all-in-one'
    return 1
  fi

  JAEGER_CONTAINER_ID="$(docker run -d -p 4318:4318 -p 16686:16686 jaegertracing/all-in-one)" || \
    fail "could not start Jaeger with the brief's docker command"
  [[ -n "$JAEGER_CONTAINER_ID" ]] || fail "Jaeger docker run returned no container id"

  local tries=0
  while ! jaeger_reachable; do
    (( tries += 1 ))
    (( tries <= 300 )) || fail "Jaeger container $JAEGER_CONTAINER_ID did not become reachable"
    sleep 0.1
  done
}

jaeger_trace_tree_present() {
  local response="$1" trace_id="$2"
  python3 - "$response" "$trace_id" <<'PY'
import json
import sys
from pathlib import Path

response, trace_id = sys.argv[1:]
try:
    payload = json.loads(Path(response).read_text())
except (json.JSONDecodeError, OSError):
    raise SystemExit(1)

spans = [
    span
    for trace in payload.get("data", [])
    if trace.get("traceID") == trace_id
    for span in trace.get("spans", [])
]
operation_key = "gen" + "_ai.operation.name"

def tags(span):
    return {
        tag.get("key"): tag.get("value")
        for tag in span.get("tags", [])
        if tag.get("key")
    }

parents = [span for span in spans if tags(span).get(operation_key) == "invoke_agent"]
children = [span for span in spans if tags(span).get(operation_key) == "chat"]
present = len(parents) == 1 and len(children) == 1 and any(
    reference.get("refType") == "CHILD_OF"
    and reference.get("spanID") == parents[0].get("spanID")
    for reference in children[0].get("references", [])
)
raise SystemExit(0 if present else 1)
PY
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
  local tree="$1" db="$2" label="$3"
  local exporter="$tree/template/.agentic/pm_flow/trace_export.py"
  local trace_id
  trace_id="$(python3 - "$db" <<'PY'
import sqlite3
import sys

connection = sqlite3.connect(sys.argv[1])
rows = connection.execute("SELECT DISTINCT trace_id FROM spans").fetchall()
if len(rows) != 1 or not rows[0][0]:
    raise SystemExit(f"expected exactly one store trace id, got {rows!r}")
print(rows[0][0])
PY
)"

  if received_trace_tree_present "$trace_id"; then
    printf 'ROUTE %s: driver telemetry_autoexport\n' "$label"
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

    if [[ "$RECEIVER_ADDRESS" == unix:* ]]; then
      printf 'ROUTE %s: test replay POST (OTLP/JSON over Unix socket)\n' "$label"
    elif [[ "$RECEIVER_ADDRESS" == pipe:* ]]; then
      printf 'ROUTE %s: test replay POST (OTLP/JSON request stream; bind prohibited)\n' "$label"
    else
      printf 'ROUTE %s: test replay POST (OTLP/JSON over TCP)\n' "$label"
    fi
  fi
  wait_for_trace_tree "$trace_id"
}

assert_jaeger_tree() {
  local tree="$1" db="$2" semconv="$3" label="$4"
  if ! ensure_jaeger; then
    return 0
  fi

  local exporter="$tree/template/.agentic/pm_flow/trace_export.py"
  local trace_id response next_response http_code tries=0 ready=0
  trace_id="$(python3 - "$db" <<'PY'
import sqlite3
import sys

connection = sqlite3.connect(sys.argv[1])
rows = connection.execute("SELECT DISTINCT trace_id FROM spans").fetchall()
if len(rows) != 1 or not rows[0][0]:
    raise SystemExit(f"expected exactly one store trace id, got {rows!r}")
print(rows[0][0])
PY
)"

  printf "%s\n" "JAEGER brief query: curl -s 'http://localhost:16686/api/traces?service=pm-flow'"
  python3 "$exporter" --db "$db" --otlp http://localhost:4318 --replay >/dev/null

  response="$TEST_ROOT/jaeger-$trace_id.json"
  next_response="$response.next"
  while (( tries < 200 )); do
    (( tries += 1 ))
    http_code="$(curl -s --max-time 2 -o "$next_response" -w '%{http_code}' \
      "http://localhost:16686/api/traces/$trace_id" || true)"
    if [[ "$http_code" == 200 ]]; then
      mv "$next_response" "$response"
      if jaeger_trace_tree_present "$response" "$trace_id"; then
        ready=1
        break
      fi
    else
      rm -f -- "$next_response"
    fi
    sleep 0.1
  done
  (( ready == 1 )) || \
    fail "Jaeger never re-served trace $trace_id with invoke_agent parent and chat child"

  python3 - "$response" "$db" "$semconv" "$label" "$trace_id" <<'PY'
import importlib.util
import json
import sqlite3
import sys
from pathlib import Path

response, db, semconv_path, label, trace_id = sys.argv[1:]
payload = json.loads(Path(response).read_text())
traces = [trace for trace in payload.get("data", []) if trace.get("traceID") == trace_id]
if len(traces) != 1:
    raise SystemExit(
        f"{label}: Jaeger returned {len(traces)} records for trace {trace_id}"
    )
spans = traces[0].get("spans", [])
if not spans:
    raise SystemExit(f"{label}: Jaeger returned no spans for trace {trace_id}")

prefix = "gen" + "_ai."
operation_key = prefix + "operation.name"
input_key = prefix + "usage.input_tokens"
output_key = prefix + "usage.output_tokens"
revision_key = "pm_flow.semconv.revision"

def tags(span):
    return {
        tag.get("key"): tag.get("value")
        for tag in span.get("tags", [])
        if tag.get("key")
    }

parents = [span for span in spans if tags(span).get(operation_key) == "invoke_agent"]
if len(parents) != 1:
    raise SystemExit(
        f"{label}: trace {trace_id} has {len(parents)} invoke_agent spans in Jaeger"
    )
parent = parents[0]
children = [span for span in spans if tags(span).get(operation_key) == "chat"]
if len(children) != 1:
    raise SystemExit(
        f"{label}: trace {trace_id} has {len(children)} chat spans in Jaeger"
    )
child = children[0]
child_of_parent = any(
    reference.get("refType") == "CHILD_OF"
    and reference.get("spanID") == parent.get("spanID")
    for reference in child.get("references", [])
)
if not child_of_parent:
    raise SystemExit(
        f"{label}: trace {trace_id} chat span {child.get('spanID')} "
        f"is not CHILD_OF invoke_agent span {parent.get('spanID')}"
    )

spec = importlib.util.spec_from_file_location("otel_semconv_jaeger_pin", semconv_path)
semconv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(semconv)
for span in spans:
    revision = tags(span).get(revision_key)
    if revision != semconv.REVISION:
        raise SystemExit(
            f"{label}: Jaeger span {span.get('spanID')} in trace {trace_id} "
            f"has revision {revision!r}, expected {semconv.REVISION!r}"
        )

connection = sqlite3.connect(db)
connection.row_factory = sqlite3.Row
attempt = connection.execute(
    "SELECT a.input_tokens, a.output_tokens FROM spans child "
    "JOIN attempts a ON child.parent_span_id = a.span_id "
    "WHERE child.span_id = ?",
    (child.get("spanID"),),
).fetchone()
if attempt is None:
    raise SystemExit(
        f"{label}: Jaeger chat span {child.get('spanID')} in trace {trace_id} "
        "did not join to its attempts row"
    )
child_tags = tags(child)
for key, column in ((input_key, "input_tokens"), (output_key, "output_tokens")):
    actual = child_tags.get(key)
    expected = attempt[column]
    if actual != expected and str(actual) != str(expected):
        raise SystemExit(
            f"{label}: Jaeger {key} on trace {trace_id} is {actual!r}, "
            f"attempt has {expected!r}"
        )

print(
    f"JAEGER {label}: {trace_id} invoke_agent -> "
    f"{child['spanID']} chat"
)
PY
  printf 'PASS: a stock backend re-serves the invoke_agent -> chat tree\n'
}

assert_received_tree() {
  local db="$1" semconv="$2" provider_suffix="$3"
  local forbidden_provider_suffix="$4" label="$5"
  python3 - "$RECEIVED" "$db" "$semconv" "$provider_suffix" \
    "$forbidden_provider_suffix" "$label" <<'PY'
import importlib.util
import json
import sqlite3
import sys
from pathlib import Path

received, db, semconv_path, provider_suffix, forbidden_suffix, label = sys.argv[1:]
connection = sqlite3.connect(db)
trace_rows = connection.execute("SELECT DISTINCT trace_id FROM spans").fetchall()
if len(trace_rows) != 1 or not trace_rows[0][0]:
    raise SystemExit(
        f"{label}: expected exactly one store trace id, got {trace_rows!r}"
    )
trace_id = trace_rows[0][0]

spans_by_id = {}
for line in Path(received).read_text().splitlines():
    payload = json.loads(line)
    for span in payload.get("spans", []):
        if span.get("traceId") == trace_id:
            spans_by_id[span["spanId"]] = span
spans = list(spans_by_id.values())
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
    f"input_tokens={expected_input} output_tokens={expected_output} "
    f"trace_id={trace_id}"
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
export_tree "$PRIMARY_TREE" "$PRIMARY_DB" "primary"
assert_received_tree "$PRIMARY_DB" "$PRIMARY_SEMCONV" \
  "provider.name" "system" "primary"
assert_jaeger_tree "$PRIMARY_TREE" "$PRIMARY_DB" "$PRIMARY_SEMCONV" "primary"

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
export_tree "$SECONDARY_TREE" "$SECONDARY_DB" "secondary"
assert_received_tree "$SECONDARY_DB" "$SECONDARY_SEMCONV" \
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
