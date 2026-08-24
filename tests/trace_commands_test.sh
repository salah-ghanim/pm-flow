#!/bin/zsh -f
set -euo pipefail
unsetopt BG_NICE
export PYTHONDONTWRITEBYTECODE=1

for name in ${(k)parameters[(I)PM_FLOW_*]}; do
  unset "$name"
done
[[ -z "${PM_FLOW_PROJECT:-}${PM_FLOW_ROOT:-}${PM_FLOW_ENGINE_ROOT:-}${PM_FLOW_REPO_ROOT:-}${PM_FLOW_FLOW_DIR:-}" ]] || {
  printf 'FAIL: a PM_FLOW_* override survived into the test environment\n' >&2
  exit 1
}

REPO_ROOT="$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)"
ENGINE="$REPO_ROOT/template/.agentic/pm_flow"
EXPORTER="$ENGINE/trace_export.py"
STORE="$ENGINE/store.py"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/trace-commands-test.XXXXXX")"
TEST_ROOT="$(cd -P "$TEST_ROOT" && pwd -P)"
case "$TEST_ROOT" in
  */trace-commands-test.*) ;;
  *) printf 'unsafe test temp directory: %s\n' "$TEST_ROOT" >&2; exit 1 ;;
esac

RECEIVER_PID=""
cleanup() {
  if [[ -n "${RECEIVER_PID:-}" ]]; then
    kill "$RECEIVER_PID" 2>/dev/null || true
    wait "$RECEIVER_PID" 2>/dev/null || true
  fi
  if [[ -n "${TEST_ROOT:-}" && -d "$TEST_ROOT" && \
        "$(basename "$TEST_ROOT")" == trace-commands-test.* ]]; then
    rm -rf -- "$TEST_ROOT"
  fi
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

offline_only=0
case "${1:-}" in
  --offline) offline_only=1 ;;
  "") ;;
  *) fail "unknown test argument: $1" ;;
esac

assert_eq() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  [[ "$actual" == "$expected" ]] || \
    fail "$label: expected '$expected', got '$actual'"
}

TRACE_REPO="$TEST_ROOT/trace repo"
TRACE_FLOW="$TRACE_REPO/.agentic/pm_flow"
TRACE_PROJECT="trace-project"
mkdir -p "$TRACE_FLOW/$TRACE_PROJECT/runs"
cp "$ENGINE/config.json" "$TRACE_FLOW/config.json"
printf '%s\n' "$TRACE_PROJECT" > "$TRACE_FLOW/.project-key"
printf '{"domain":"generic"}\n' > "$TRACE_FLOW/$TRACE_PROJECT/project.json"

trace_command() {
  env PM_FLOW_ENGINE_ROOT="$ENGINE" PM_FLOW_FLOW_DIR="$TRACE_FLOW" \
    PM_FLOW_REPO_ROOT="$TRACE_REPO" PM_FLOW_PROJECT="$TRACE_PROJECT" \
    zsh -f "$ENGINE/pm_flow.sh" trace "$@"
}

DB="$TRACE_FLOW/$TRACE_PROJECT/runs/pm_flow.db"
STATUS_FILE="$TEST_ROOT/status"
REQUESTS_FILE="$TEST_ROOT/requests.jsonl"
PORT_FILE="$TEST_ROOT/port"
ERROR_FILE="$TEST_ROOT/export.err"
SPAN_COUNT=3

python3 - "$STORE" "$DB" <<'PY'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("store", sys.argv[1])
store = importlib.util.module_from_spec(spec)
spec.loader.exec_module(store)
connection = store.connect(sys.argv[2])
trace_id = "0123456789abcdef0123456789abcdef"
rows = [
    ("1111111111111111", None, "root", 1.0, 2.0),
    ("2222222222222222", "1111111111111111", "child-one", 1.1, 1.5),
    ("3333333333333333", "1111111111111111", "child-two", 1.2, 1.8),
]
with connection:
    connection.executemany(
        "INSERT INTO spans (span_id, trace_id, parent_span_id, name, kind, "
        "started_at, ended_at, status, attributes) "
        "VALUES (?, ?, ?, ?, 'INTERNAL', ?, ?, 'OK', ?)",
        [(span_id, trace_id, parent, name, started, ended,
          store.dumps({"fixture.index": index}))
         for index, (span_id, parent, name, started, ended) in enumerate(rows)],
    )
    connection.execute(
        "INSERT INTO span_events (span_id, at, name, attributes) "
        "VALUES (?, ?, ?, ?)",
        (rows[1][0], 1.25, "fixture-event", store.dumps({"seen": True})),
    )
PY

cat > "$TEST_ROOT/receiver.py" <<'PY'
import http.server
import json
import sys
import time
from pathlib import Path

status_path = Path(sys.argv[1])
requests_path = Path(sys.argv[2])

class Receiver(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        with requests_path.open("ab") as handle:
            handle.write(body + b"\n")
            handle.flush()

        mode = status_path.read_text().strip()
        if self.path != "/v1/traces" or self.headers.get_content_type() != "application/json":
            code, response = 400, b""
        elif mode == "partial":
            code = 200
            response = json.dumps(
                {"partialSuccess": {"rejectedSpans": 1}}
            ).encode()
        elif mode.startswith("sleep:"):
            time.sleep(float(mode.partition(":")[2]))
            code, response = 200, b""
        elif mode.startswith("header:"):
            key, _, expected = mode.partition(":")[2].partition("=")
            code = 200 if self.headers.get(key) == expected else 400
            response = b""
        else:
            code, response = int(mode), b""

        try:
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(response)))
            self.end_headers()
            self.wfile.write(response)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, format, *args):
        pass

class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True

server = Server(("127.0.0.1", 0), Receiver)
print(server.server_port, flush=True)
server.serve_forever()
PY

if (( ! offline_only )); then
  printf '200\n' > "$STATUS_FILE"
  : > "$REQUESTS_FILE"
  python3 "$TEST_ROOT/receiver.py" "$STATUS_FILE" "$REQUESTS_FILE" \
    > "$PORT_FILE" 2> "$TEST_ROOT/receiver.err" &
  RECEIVER_PID=$!

  for attempt in {1..100}; do
    [[ -s "$PORT_FILE" ]] && break
    kill -0 "$RECEIVER_PID" 2>/dev/null || {
      /bin/cat "$TEST_ROOT/receiver.err" >&2
      fail "receiver exited before reporting its port"
    }
    sleep 0.02
  done
  [[ -s "$PORT_FILE" ]] || fail "receiver did not report its port"
  PORT="$(head -n 1 "$PORT_FILE")"
  ENDPOINT="http://127.0.0.1:$PORT"
fi

exported_count() {
  python3 - "$DB" <<'PY'
import sqlite3
import sys
connection = sqlite3.connect(sys.argv[1])
print(connection.execute(
    "SELECT COUNT(*) FROM spans WHERE exported_at IS NOT NULL"
).fetchone()[0])
PY
}

reset_exports() {
  python3 - "$DB" <<'PY'
import sqlite3
import sys
connection = sqlite3.connect(sys.argv[1])
with connection:
    connection.execute("UPDATE spans SET exported_at = NULL")
PY
}

request_count() {
  python3 - "$REQUESTS_FILE" <<'PY'
from pathlib import Path
import sys
print(len(Path(sys.argv[1]).read_bytes().splitlines()))
PY
}

body_ids() {
  python3 - "$REQUESTS_FILE" "$1" <<'PY'
import json
import sys
from pathlib import Path
requests = Path(sys.argv[1]).read_text().splitlines()
payload = json.loads(requests[int(sys.argv[2])])
spans = payload["resourceSpans"][0]["scopeSpans"][0]["spans"]
print(",".join(span["spanId"] for span in spans))
PY
}

if (( ! offline_only )); then
output="$(trace_command export --otlp "$ENDPOINT")"
assert_eq "$output" "exported $SPAN_COUNT span(s)" "successful export count"
assert_eq "$(exported_count)" "$SPAN_COUNT" "successful export checkpoint"
assert_eq "$(request_count)" "1" "successful export request count"
python3 - "$REQUESTS_FILE" "$SPAN_COUNT" <<'PY'
import json
import sys
from pathlib import Path
payload = json.loads(Path(sys.argv[1]).read_text().splitlines()[0])
spans = payload["resourceSpans"][0]["scopeSpans"][0]["spans"]
assert len(spans) == int(sys.argv[2]), (len(spans), sys.argv[2])
assert any(span.get("events", [{}])[0].get("name") == "fixture-event"
           for span in spans), "seeded span event was not exported"
PY

output="$(trace_command export --otlp "$ENDPOINT")"
assert_eq "$output" "exported 0 span(s)" "second export count"
assert_eq "$(request_count)" "1" "second export sends no request"

reset_exports
: > "$REQUESTS_FILE"
printf '503\n' > "$STATUS_FILE"
http_code=0
output="$(trace_command export --otlp "$ENDPOINT" \
  2> "$ERROR_FILE")" || http_code=$?
[[ "$http_code" -ne 0 ]] || fail "503 export exited zero"
assert_eq "$output" "exported 0 span(s)" "503 acknowledged count"
assert_eq "$(exported_count)" "0" "503 leaves spans unmarked"
grep -F 'HTTP 503' "$ERROR_FILE" >/dev/null || fail "503 status was not reported"
grep -F 'kept for retry' "$ERROR_FILE" >/dev/null || fail "503 retention was not reported"
! grep -F 'Traceback' "$ERROR_FILE" >/dev/null || fail "503 printed a traceback"
failed_ids="$(body_ids 0)"

printf 'sleep:0.4\n' > "$STATUS_FILE"
http_code=0
output="$(trace_command export --otlp "$ENDPOINT" --timeout 0.05 \
  2> "$ERROR_FILE")" || http_code=$?
[[ "$http_code" -ne 0 ]] || fail "timeout export exited zero"
assert_eq "$output" "exported 0 span(s)" "timeout acknowledged count"
assert_eq "$(exported_count)" "0" "timeout leaves spans unmarked"
grep -F 'kept for retry' "$ERROR_FILE" >/dev/null || fail "timeout retention was not reported"
! grep -F 'Traceback' "$ERROR_FILE" >/dev/null || fail "timeout printed a traceback"
timeout_ids="$(body_ids 1)"

printf '200\n' > "$STATUS_FILE"
output="$(trace_command export --otlp "$ENDPOINT")"
assert_eq "$output" "exported $SPAN_COUNT span(s)" "retry export count"
assert_eq "$(exported_count)" "$SPAN_COUNT" "retry export checkpoint"
retry_ids="$(body_ids 2)"
assert_eq "$timeout_ids" "$failed_ids" "timeout retries the same span ids"
assert_eq "$retry_ids" "$failed_ids" "successful retry sends the same span ids"

reset_exports
printf 'partial\n' > "$STATUS_FILE"
http_code=0
output="$(trace_command export --otlp "$ENDPOINT" \
  2> "$ERROR_FILE")" || http_code=$?
[[ "$http_code" -ne 0 ]] || fail "partial-success export exited zero"
assert_eq "$output" "exported 0 span(s)" "partial-success checkpointed count"
assert_eq "$(exported_count)" "0" "partial success leaves every span unmarked"
grep -F 'acknowledged 2 of 3 span(s)' "$ERROR_FILE" >/dev/null || \
  fail "partial-success shortfall was not reported"

# Mutation guard: run a copy that checkpoints before delivery. The same
# unmarked-on-timeout assertion above must reject it.
mkdir -p "$TEST_ROOT/mutant"
cp "$EXPORTER" "$STORE" "$TEST_ROOT/mutant/"
python3 - "$TEST_ROOT/mutant/trace_export.py" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
source = path.read_text()
needle = "    if args.file:\n"
mutation = (
    "    if not args.replay:\n"
    "        mark_exported(connection, [row[\"span_id\"] for row in rows])\n\n"
    + needle
)
assert source.count(needle) == 1
path.write_text(source.replace(needle, mutation, 1))
PY
reset_exports
printf 'sleep:0.4\n' > "$STATUS_FILE"
python3 "$TEST_ROOT/mutant/trace_export.py" --db "$DB" --otlp "$ENDPOINT" \
  --timeout 0.05 > /dev/null 2> "$ERROR_FILE" || true
mutation_guard_status=0
[[ "$(exported_count)" == "0" ]] || mutation_guard_status=1
assert_eq "$mutation_guard_status" "1" \
  "pre-acknowledgement checkpoint mutation is rejected"

# The project config supplies the endpoint and headers. An explicit endpoint
# remains authoritative when the configured one is unusable.
set_trace_config() {
  python3 - "$TRACE_FLOW/config.json" "$1" "$2" "$3" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
config = json.loads(path.read_text())
config["telemetry"] = {
    "enabled": int(sys.argv[4]),
    "otlp_endpoint": sys.argv[2],
    "headers": {"X-Trace-Config": sys.argv[3]} if sys.argv[3] else {},
}
path.write_text(json.dumps(config, indent=2) + "\n")
PY
}

reset_exports
set_trace_config "$ENDPOINT" configured 1
printf 'header:X-Trace-Config=configured\n' > "$STATUS_FILE"
output="$(trace_command export)"
assert_eq "$output" "exported $SPAN_COUNT span(s)" \
  "configured endpoint and header export count"
assert_eq "$(exported_count)" "$SPAN_COUNT" \
  "configured endpoint export checkpoint"

reset_exports
set_trace_config "http://127.0.0.1:1" configured 1
printf '200\n' > "$STATUS_FILE"
output="$(trace_command export --otlp "$ENDPOINT")"
assert_eq "$output" "exported $SPAN_COUNT span(s)" \
  "explicit endpoint overrides config"
fi

# A venv with a poison opentelemetry package proves the file path imports no
# optional SDK. The written request passes the exporter's own check and a
# separate JSON-Schema subset validator implemented only in this test.
reset_exports
NO_SDK_VENV="$TEST_ROOT/no-sdk"
POISON_PATH="$TEST_ROOT/poison"
OTLP_FILE="$TEST_ROOT/traces.otlp.jsonl"
python3 -m venv "$NO_SDK_VENV"
mkdir -p "$POISON_PATH/opentelemetry"
printf 'raise ImportError("opentelemetry must not be imported")\n' \
  > "$POISON_PATH/opentelemetry/__init__.py"
sdk_code=0
PYTHONPATH="$POISON_PATH" PATH="$NO_SDK_VENV/bin:$PATH" \
  trace_command export --file "$OTLP_FILE" \
  > "$TEST_ROOT/no-sdk.out" 2> "$TEST_ROOT/no-sdk.err" || sdk_code=$?
if (( sdk_code != 0 )); then
  /bin/cat "$TEST_ROOT/no-sdk.err" >&2
  fail "SDK-less file export exited $sdk_code"
fi
output="$(/bin/cat "$TEST_ROOT/no-sdk.out")"
assert_eq "$output" "exported $SPAN_COUNT span(s)" "SDK-less file export count"

PYTHONPATH="$POISON_PATH" "$NO_SDK_VENV/bin/python" \
  - "$EXPORTER" "$OTLP_FILE" <<'PY'
import importlib.util
import json
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location("trace_export", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
lines = Path(sys.argv[2]).read_text().splitlines()
assert len(lines) == 1, lines
module.validate_otlp_json(json.loads(lines[0]))
PY

"$NO_SDK_VENV/bin/python" - "$OTLP_FILE" "$SPAN_COUNT" <<'PY'
import json
import re
import sys
from pathlib import Path

def validate(instance, schema, path="$"):
    expected = schema.get("type")
    types = {
        "object": dict, "array": list, "string": str, "integer": int,
    }
    if expected and (not isinstance(instance, types[expected])
                     or expected == "integer" and isinstance(instance, bool)):
        raise AssertionError(f"{path}: expected {expected}")
    for key in schema.get("required", []):
        assert key in instance, f"{path}: missing {key}"
    for key, child in schema.get("properties", {}).items():
        if key in instance:
            validate(instance[key], child, f"{path}.{key}")
    if expected == "array":
        assert len(instance) >= schema.get("minItems", 0), path
        for index, item in enumerate(instance):
            validate(item, schema["items"], f"{path}[{index}]")
    if expected == "string" and "pattern" in schema:
        assert re.fullmatch(schema["pattern"], instance), path

attribute_schema = {
    "type": "object", "required": ["key", "value"],
    "properties": {"key": {"type": "string"}, "value": {"type": "object"}},
}
span_schema = {
    "type": "object",
    "required": ["traceId", "spanId", "name", "kind", "startTimeUnixNano",
                 "endTimeUnixNano", "attributes", "status"],
    "properties": {
        "traceId": {"type": "string", "pattern": "[0-9a-f]{32}"},
        "spanId": {"type": "string", "pattern": "[0-9a-f]{16}"},
        "name": {"type": "string"},
        "kind": {"type": "integer"},
        "startTimeUnixNano": {"type": "string", "pattern": "[0-9]+"},
        "endTimeUnixNano": {"type": "string", "pattern": "[0-9]+"},
        "attributes": {"type": "array", "items": attribute_schema},
        "status": {
            "type": "object", "required": ["code"],
            "properties": {"code": {"type": "integer"}},
        },
    },
}
schema = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object", "required": ["resourceSpans"],
    "properties": {"resourceSpans": {
        "type": "array", "minItems": 1, "items": {
            "type": "object", "required": ["resource", "scopeSpans"],
            "properties": {
                "resource": {
                    "type": "object", "required": ["attributes"],
                    "properties": {"attributes": {
                        "type": "array", "items": attribute_schema,
                    }},
                },
                "scopeSpans": {
                    "type": "array", "minItems": 1, "items": {
                        "type": "object", "required": ["scope", "spans"],
                        "properties": {
                            "scope": {
                                "type": "object", "required": ["name"],
                                "properties": {"name": {"type": "string"}},
                            },
                            "spans": {
                                "type": "array", "items": span_schema,
                            },
                        },
                    },
                },
            },
        },
    }},
}
payload = json.loads(Path(sys.argv[1]).read_text().splitlines()[0])
validate(payload, schema)
spans = payload["resourceSpans"][0]["scopeSpans"][0]["spans"]
assert len(spans) == int(sys.argv[2]), len(spans)
PY

# Reuse the headless stub harness: a disabled project performs one normal
# scope tick while the pre-created store remains byte-for-byte span-neutral.
DISABLED_REPO="$TEST_ROOT/disabled repo"
mkdir "$DISABLED_REPO"
"$REPO_ROOT/install.sh" "$DISABLED_REPO" --name "Disabled Project" \
  > "$TEST_ROOT/disabled-install.out"
DISABLED_FLOW="$DISABLED_REPO/.agentic/pm_flow"
DISABLED_PROJECT="disabled-repo"
DISABLED_DB="$DISABLED_FLOW/$DISABLED_PROJECT/runs/pm_flow.db"

disabled_pm() {
  env PM_FLOW_ENGINE_ROOT="$ENGINE" PM_FLOW_FLOW_DIR="$DISABLED_FLOW" \
    PM_FLOW_REPO_ROOT="$DISABLED_REPO" PM_FLOW_PROJECT="$DISABLED_PROJECT" \
    zsh -f "$ENGINE/pm_flow.sh" "$@"
}

python3 - "$DISABLED_FLOW/config.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
config = json.loads(path.read_text())
for role in ("cpo", "pm", "developer", "10x_developer"):
    config["roles"][role] = {"cli": "claude", "model": "", "difficulty": "low"}
config["telemetry"]["enabled"] = False
path.write_text(json.dumps(config, indent=2) + "\n")
PY

BRIEF_FILE="$TEST_ROOT/disabled-brief.md"
cat > "$BRIEF_FILE" <<'BRIEF'
## Objective

- Exercise one disabled-recording tick.

## Scope

- The stub only.

## Priority

- must-have: acceptance fixture

## Owned paths

- `src/stub/**`

## Dependencies

- None.

## Acceptance

- The tick exits normally.

## Rejection conditions

- The tick records a span.
BRIEF
disabled_pm init-section widget --file "$BRIEF_FILE" > /dev/null
python3 - "$STORE" "$DISABLED_DB" <<'PY'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("store", sys.argv[1])
store = importlib.util.module_from_spec(spec)
spec.loader.exec_module(store)
store.connect(sys.argv[2]).close()
PY

span_count() {
  python3 - "$1" <<'PY'
import sqlite3
import sys
connection = sqlite3.connect(sys.argv[1])
print(connection.execute("SELECT COUNT(*) FROM spans").fetchone()[0])
PY
}

mkdir "$TEST_ROOT/disabled-bin"
cp "$REPO_ROOT/tests/fixtures/stub_success.zsh" "$TEST_ROOT/disabled-bin/claude"
chmod +x "$TEST_ROOT/disabled-bin/claude"
before_spans="$(span_count "$DISABLED_DB")"
tick_code=0
PM_DONE_FLAG="$TEST_ROOT/disabled-done.flag" \
  PATH="$TEST_ROOT/disabled-bin:$PATH" disabled_pm tick \
  > "$TEST_ROOT/disabled-tick.out" 2>&1 || tick_code=$?
assert_eq "$tick_code" "0" "disabled-recording stub tick status"
after_spans="$(span_count "$DISABLED_DB")"
assert_eq "$after_spans" "$before_spans" "disabled tick span count"
disabled_status="$(disabled_pm trace status)"
[[ "$disabled_status" == *"recording: disabled"* ]] || \
  fail "trace status did not report disabled recording"
[[ "$disabled_status" == *"endpoint: none"* ]] || \
  fail "trace status did not report the missing endpoint"
[[ "$disabled_status" == *"unexported spans: 0"* ]] || \
  fail "trace status did not report the unexported count"
[[ "$disabled_status" == *"exported spans: 0"* ]] || \
  fail "trace status did not report the exported count"

# Fault-inject an exception whose origin is the exporter into the telemetry
# subprocess used by a real tick. The marker proves the exception executed;
# the driver must still preserve the tick's normal status.
MUTANT_ENGINE="$TEST_ROOT/exporter-failure-engine"
cp -R "$ENGINE" "$MUTANT_ENGINE"
TRACE_FAILURE_MARKER="$TEST_ROOT/exporter-failure-called"
python3 - "$MUTANT_ENGINE/trace_export.py" "$MUTANT_ENGINE/telemetry.py" <<'PY'
import sys
from pathlib import Path

exporter = Path(sys.argv[1])
exporter.write_text(
    exporter.read_text()
    + "\n\ndef injected_failure():\n"
      "    Path(os.environ['TRACE_FAILURE_MARKER']).write_text('called')\n"
      "    raise RuntimeError('injected exporter failure')\n"
)
telemetry = Path(sys.argv[2])
source = telemetry.read_text()
needle = "def main(argv):\n"
mutation = (
    needle
    + "    import trace_export\n"
      "    trace_export.injected_failure()\n"
)
assert source.count(needle) == 1
telemetry.write_text(source.replace(needle, mutation, 1))
PY
python3 - "$DISABLED_FLOW/config.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
config = json.loads(path.read_text())
config["telemetry"]["enabled"] = True
path.write_text(json.dumps(config, indent=2) + "\n")
PY

mutant_pm() {
  env PM_FLOW_ENGINE_ROOT="$MUTANT_ENGINE" PM_FLOW_FLOW_DIR="$DISABLED_FLOW" \
    PM_FLOW_REPO_ROOT="$DISABLED_REPO" PM_FLOW_PROJECT="$DISABLED_PROJECT" \
    zsh -f "$MUTANT_ENGINE/pm_flow.sh" "$@"
}

mutant_tick_code=0
TRACE_FAILURE_MARKER="$TRACE_FAILURE_MARKER" \
  PM_DONE_FLAG="$TEST_ROOT/disabled-done.flag" \
  PATH="$TEST_ROOT/disabled-bin:$PATH" mutant_pm tick \
  > "$TEST_ROOT/mutant-tick.out" 2>&1 || mutant_tick_code=$?
assert_eq "$mutant_tick_code" "0" "exporter exception preserves tick status"
[[ -f "$TRACE_FAILURE_MARKER" ]] || \
  fail "exporter failure mutation did not execute"

if (( offline_only )); then
  printf 'A2 and A4 trace command tests passed; receiver-backed A1/A3 not run in offline mode\n'
else
  printf 'trace command tests passed\n'
fi
