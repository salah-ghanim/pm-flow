#!/bin/zsh -f
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1

for name in ${(k)parameters[(I)PM_FLOW_*]}; do
  unset "$name"
done
[[ -z "${PM_FLOW_PROJECT:-}${PM_FLOW_ROOT:-}${PM_FLOW_ENGINE_ROOT:-}${PM_FLOW_REPO_ROOT:-}${PM_FLOW_FLOW_DIR:-}" ]] || {
  printf 'FAIL: a PM_FLOW_* override survived into the test environment\n' >&2
  exit 1
}

REPO_ROOT="$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/outcome-record-test.XXXXXX")"
TEST_ROOT="$(cd -P "$TEST_ROOT" && pwd -P)"
case "$TEST_ROOT" in
  */outcome-record-test.*) ;;
  *) printf 'unsafe test temp directory: %s\n' "$TEST_ROOT" >&2; exit 1 ;;
esac

JAEGER_CONTAINER_ID=""
cleanup() {
  if [[ -n "${JAEGER_CONTAINER_ID:-}" ]]; then
    docker rm -f "$JAEGER_CONTAINER_ID" >/dev/null 2>&1 || true
  fi
  if [[ -n "${TEST_ROOT:-}" && -d "$TEST_ROOT" && \
        "$(basename "$TEST_ROOT")" == outcome-record-test.* ]]; then
    rm -rf -- "$TEST_ROOT"
  fi
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local actual="$1" expected="$2" label="$3"
  [[ "$actual" == "$expected" ]] || \
    fail "$label: expected '$expected', got '$actual'"
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
      'SKIP: A2 requires docker run -d -p 4318:4318 -p 16686:16686 jaegertracing/all-in-one'
    return 1
  fi

  JAEGER_CONTAINER_ID="$(docker run -d -p 4318:4318 -p 16686:16686 jaegertracing/all-in-one)" || \
    fail "could not start Jaeger with the brief's docker command"
  [[ -n "$JAEGER_CONTAINER_ID" ]] || fail "Jaeger docker run returned no container id"

  local tries=0
  while ! jaeger_reachable; do
    (( tries += 1 ))
    (( tries <= 300 )) || \
      fail "Jaeger container $JAEGER_CONTAINER_ID did not become reachable"
    sleep 0.1
  done
}

jaeger_evaluations_present() {
  local response="$1" db="$2" semconv="$3" trace_id="$4"
  python3 - "$response" "$db" "$semconv" "$trace_id" <<'PY'
import importlib.util
import json
import sqlite3
import sys
from collections import Counter
from pathlib import Path

response, db_path, semconv_path, trace_id = sys.argv[1:]
try:
    payload = json.loads(Path(response).read_text())
except (json.JSONDecodeError, OSError):
    raise SystemExit(1)

spec = importlib.util.spec_from_file_location("outcome_record_jaeger_semconv", semconv_path)
semconv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(semconv)
names = semconv.evaluation_event()
if names is None:
    raise SystemExit(1)

connection = sqlite3.connect(db_path)
expected = Counter(connection.execute(
    "SELECT s.trace_id, a.span_id, o.metric, o.value_text "
    "FROM outcomes o JOIN attempts a ON a.id = o.attempt_id "
    "JOIN spans s ON s.span_id = a.span_id "
    "WHERE o.source = 'verdict' AND s.trace_id = ?",
    (trace_id,),
))

actual = Counter()
for trace in payload.get("data", []):
    if trace.get("traceID") != trace_id:
        continue
    for span in trace.get("spans", []):
        for log in span.get("logs", []):
            fields = {
                field.get("key"): field.get("value")
                for field in log.get("fields", [])
                if field.get("key")
            }
            if fields.get("event") != names["event_name"]:
                continue
            actual[(
                trace_id,
                span.get("spanID"),
                fields.get(names["evaluation_name"]),
                fields.get(names["score_label"]),
            )] += 1

raise SystemExit(0 if expected and actual == expected else 1)
PY
}

assert_jaeger_evaluations() {
  local db="$1" semconv="$2"
  if ! ensure_jaeger; then
    return 0
  fi

  local trace_ids trace_id response next_response http_code tries ready
  local -a responses
  trace_ids="$(sqlite3 "$db" "SELECT DISTINCT s.trace_id FROM outcomes o JOIN attempts a ON a.id = o.attempt_id JOIN spans s ON s.span_id = a.span_id WHERE o.source = 'verdict' ORDER BY s.trace_id;")"
  [[ -n "$trace_ids" ]] || fail "no verdict trace ids were available for Jaeger"

  # Every driver invocation that produced these rows has exited. This exporter
  # is a new process and receives only the durable database path.
  python3 "$FLOW/trace_export.py" --db "$db" \
    --otlp http://localhost:4318 --replay >/dev/null

  responses=()
  for trace_id in ${(f)trace_ids}; do
    response="$TEST_ROOT/jaeger-$trace_id.json"
    next_response="$response.next"
    tries=0
    ready=0
    printf "%s\n" "JAEGER query: curl -s 'http://localhost:16686/api/traces/$trace_id'"
    while (( tries < 200 )); do
      (( tries += 1 ))
      http_code="$(curl -s --max-time 2 -o "$next_response" -w '%{http_code}' \
        "http://localhost:16686/api/traces/$trace_id" || true)"
      if [[ "$http_code" == 200 ]]; then
        mv "$next_response" "$response"
        if jaeger_evaluations_present "$response" "$db" "$semconv" "$trace_id"; then
          ready=1
          break
        fi
      else
        rm -f -- "$next_response"
      fi
      sleep 0.1
    done
    (( ready == 1 )) || \
      fail "Jaeger never re-served every evaluation event for trace $trace_id"
    responses+=("$response")
  done

  local fragment
  fragment="$(python3 - "$db" "$semconv" "${responses[@]}" <<'PY'
import importlib.util
import json
import sqlite3
import sys
from collections import Counter
from pathlib import Path

db_path, semconv_path, *response_paths = sys.argv[1:]
spec = importlib.util.spec_from_file_location("outcome_record_jaeger_semconv", semconv_path)
semconv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(semconv)
names = semconv.evaluation_event()
if names is None:
    raise SystemExit("the pinned revision did not provide evaluation event names")

connection = sqlite3.connect(db_path)
expected = Counter(connection.execute(
    "SELECT s.trace_id, a.span_id, o.metric, o.value_text "
    "FROM outcomes o JOIN attempts a ON a.id = o.attempt_id "
    "JOIN spans s ON s.span_id = a.span_id WHERE o.source = 'verdict'"
))

actual = Counter()
fragments = []
for response_path in response_paths:
    payload = json.loads(Path(response_path).read_text())
    for trace in payload.get("data", []):
        trace_id = trace.get("traceID")
        for span in trace.get("spans", []):
            matching = []
            for log in span.get("logs", []):
                fields = {
                    field.get("key"): field.get("value")
                    for field in log.get("fields", [])
                    if field.get("key")
                }
                if fields.get("event") != names["event_name"]:
                    continue
                matching.append(log)
                actual[(
                    trace_id,
                    span.get("spanID"),
                    fields.get(names["evaluation_name"]),
                    fields.get(names["score_label"]),
                )] += 1
            if matching:
                fragments.append({
                    "traceID": trace_id,
                    "spanID": span.get("spanID"),
                    "logs": matching,
                })

if actual != expected:
    raise SystemExit(f"Jaeger events do not match verdict rows: {actual!r} != {expected!r}")
print(json.dumps(fragments, indent=2, sort_keys=True))
PY
)"

  printf 'JAEGER JSON FRAGMENT:\n%s\n' "$fragment"
  printf 'PASS: Jaeger re-serves one evaluation event per verdict on its attempt span\n'
}

WORK="$TEST_ROOT/work"
mkdir -p "$WORK/.agentic" "$WORK/src" "$WORK/lib" "$WORK/docs" "$WORK/tools" \
  "$WORK/complete"
cp -R "$REPO_ROOT/template/.agentic/pm_flow" "$WORK/.agentic/pm_flow"
cp "$REPO_ROOT/src/pm_flow/semconv.py" "$WORK/.agentic/semconv.py"
FLOW="$WORK/.agentic/pm_flow"
rm -rf "$FLOW/project"
mkdir -p "$FLOW/demo/project_state" "$FLOW/demo/sections" "$FLOW/demo/runs"
printf 'demo\n' > "$FLOW/.project-key"
printf '{"domain":"generic"}\n' > "$FLOW/demo/project.json"
printf '# Demo Task Contract\n\nrules\n' > "$FLOW/demo/task_contract.md"
printf '# Plan\n\nbuild the thing\n' > "$FLOW/demo/project_state/plan.md"
printf 'print("hi")\n' > "$WORK/src/main.py"
printf 'x\n' > "$WORK/lib/a.py"
printf 'x\n' > "$WORK/docs/a.md"
printf 'x\n' > "$WORK/tools/a.py"
cp "$REPO_ROOT/tests/fixtures/outcome_record/agent_exec.sh" "$FLOW/agent_exec.sh"
chmod +x "$FLOW/agent_exec.sh" "$FLOW/pm_flow.sh"

python3 - "$FLOW/config.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
config = json.loads(path.read_text().replace('"{{DOMAIN}}"', '"generic"'))
config.setdefault("isolation", {})["worktrees"] = 0
config.setdefault("escalation", {})["cycles_before_convergence_review"] = 0
config.setdefault("governance", {})["portfolio_review_dispatches"] = 0
config.setdefault("governance", {})["portfolio_review_usd"] = 0
config.setdefault("governance", {})["portfolio_review_idle_cycles"] = 0
path.write_text(json.dumps(config, indent=2) + "\n")
PY

cd "$WORK"
git init -q .
git config user.email test@example.invalid
git config user.name outcome-record-test

brief() {
  printf '## Objective\n\n- %s\n\n## Scope\n\n- one thing\n\n## Priority\n\n- must-have: required by the fixture\n\n## Owned paths\n\n- `%s`\n\n## Dependencies\n\n- None.\n\n## Acceptance\n\n- `.venv/bin/python -m pytest -q` exits 0\n\n## Rejection conditions\n\n- nothing runs\n' "$1" "$2"
}

set_project_budget() {
  python3 - "$FLOW/config.json" "$1" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
config = json.loads(path.read_text())
config["budget"]["max_usd"] = float(sys.argv[2])
path.write_text(json.dumps(config, indent=2) + "\n")
PY
}

FLOWSH="$FLOW/pm_flow.sh"
brief review "lib/" > "$TEST_ROOT/brief.md"
"$FLOWSH" init-section review --file "$TEST_ROOT/brief.md" >/dev/null
brief unparsed "docs/" > "$TEST_ROOT/brief.md"
"$FLOWSH" init-section unparsed --file "$TEST_ROOT/brief.md" >/dev/null
brief abandoned "tools/" > "$TEST_ROOT/brief.md"
"$FLOWSH" init-section abandoned --file "$TEST_ROOT/brief.md" >/dev/null
brief complete "complete/" > "$TEST_ROOT/brief.md"
"$FLOWSH" init-section complete --file "$TEST_ROOT/brief.md" >/dev/null
git add -A
git commit -qm fixture

SCOPE='## Workplan task

T1

## Assignment

Inspect lib/a.py.

## Acceptance

- `.venv/bin/python -m pytest -q` exits 0

## Rejection conditions

- nothing runs

## Decision

ASSIGN'
DEVELOP='## What I changed

- Inspected the fixture.

## What I reused or restructured

- Existing file.

## Validation

- Stubbed.

## What I could not do

- Nothing.

## Status

DELIVERED'
REVIEW='## Assessment

The fixture meets its assignment.

## Obstruction

NONE

## Decision

GO_WITH_CHANGES'

PM_FLOW_STUB="$SCOPE" PM_FLOW_SECTION=review "$FLOWSH" tick >/dev/null
PM_FLOW_STUB="$DEVELOP" PM_FLOW_SECTION=review "$FLOWSH" tick >/dev/null
PM_FLOW_STUB="$REVIEW" PM_FLOW_SECTION=review "$FLOWSH" tick >/dev/null

# Exercise the parse-failure branch too: UNPARSED is a decision outcome, not an
# omitted observation.
PM_FLOW_STUB='## Decision

probably assign this' PM_FLOW_SECTION=unparsed "$FLOWSH" tick >/dev/null

# COMPLETE must be parsed from the scope response. Priming decision.txt here
# would skip record_cycle_decision and leave this verdict unobserved.
PM_FLOW_STUB='## Decision

COMPLETE' PM_FLOW_SECTION=complete "$FLOWSH" tick >/dev/null

# The portfolio review has additional per-section parsing after its top-level
# decision. A deliberately minimal response proves the top-level parse is
# recorded immediately even when that later parsing asks for a retry.
PM_FLOW_STUB='## Decision

ON_TRACK' "$FLOWSH" portfolio-review >/dev/null

DB="$FLOW/demo/runs/pm_flow.db"
[[ -f "$DB" ]] || fail "the driver did not create the telemetry store"

JOIN_SQL="SELECT o.metric || '|' || o.value_text || '|' || o.source || '|' || a.role_key || '|' || r.command FROM outcomes o JOIN attempts a ON a.id = o.attempt_id JOIN runs r ON r.id = o.run_id AND r.id = a.run_id WHERE o.metric IN ('scope_decision','review_verdict','portfolio_verdict','obstruction_class') ORDER BY o.metric, o.id;"
JOIN_ROWS="$(sqlite3 "$DB" "$JOIN_SQL")"
EXPECTED_JOIN_ROWS=$'obstruction_class|NONE|verdict|pm|tick\nportfolio_verdict|ON_TRACK|verdict|cpo|portfolio-review\nreview_verdict|GO_WITH_CHANGES|verdict|pm|tick\nscope_decision|ASSIGN|verdict|pm|tick\nscope_decision|UNPARSED|verdict|pm|tick\nscope_decision|COMPLETE|verdict|pm|tick'
assert_eq "$JOIN_ROWS" "$EXPECTED_JOIN_ROWS" \
  "every decision joins to its producing attempt and run"
assert_eq "$(sqlite3 "$DB" "SELECT COUNT(*) FROM outcomes WHERE source = 'verdict' AND attempt_id IS NULL;")" \
  "0" "verdict outcomes never have a NULL attempt"

printf 'RAW SELECT:\n%s\n' "$JOIN_SQL"
printf '%s\n' "$JOIN_ROWS"
printf 'PASS: every parsed decision joins to its producing attempt and run\n'

SEMCONV="$WORK/.agentic/semconv.py"
EVENT_NAME="$(python3 - "$SEMCONV" <<'PY'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("outcome_record_semconv", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
print(module.evaluation_event()["event_name"])
PY
)"
VERDICT_COUNT="$(sqlite3 "$DB" "SELECT COUNT(*) FROM outcomes WHERE source = 'verdict';")"
EVENT_COUNT="$(sqlite3 "$DB" "SELECT COUNT(*) FROM span_events WHERE name = '$EVENT_NAME';")"
assert_eq "$EVENT_COUNT" "$VERDICT_COUNT" \
  "evaluation event count equals verdict-row count"

EVENT_SQL="SELECT a.id || '|' || a.span_id || '|' || se.name || '|' || se.attributes FROM span_events se JOIN attempts a ON a.span_id = se.span_id WHERE se.name = '$EVENT_NAME' ORDER BY a.id, se.rowid;"
EVENT_ROWS="$(sqlite3 "$DB" "$EVENT_SQL")"
[[ -n "$EVENT_ROWS" ]] || fail "no evaluation events joined to attempts"

OTLP_FILE="$TEST_ROOT/outcome.otlp.jsonl"
python3 "$FLOW/trace_export.py" --db "$DB" --file "$OTLP_FILE" --replay >/dev/null
EXPORTED_FRAGMENT="$(python3 - "$DB" "$OTLP_FILE" "$SEMCONV" <<'PY'
import importlib.util
import json
import sqlite3
import sys
from collections import Counter

db_path, otlp_path, semconv_path = sys.argv[1:]
spec = importlib.util.spec_from_file_location("outcome_record_semconv", semconv_path)
semconv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(semconv)
names = semconv.evaluation_event()
if names is None:
    raise SystemExit("the pinned revision did not provide evaluation event names")

connection = sqlite3.connect(db_path)
connection.row_factory = sqlite3.Row
expected = Counter(
    (row["attempt_id"], row["metric"], row["value_text"])
    for row in connection.execute(
        "SELECT attempt_id, metric, value_text FROM outcomes "
        "WHERE source = 'verdict'"
    )
)
attempt_by_span = {
    row["span_id"]: row["id"]
    for row in connection.execute("SELECT id, span_id FROM attempts")
}
stored = Counter()
for row in connection.execute(
    "SELECT span_id, attributes FROM span_events WHERE name = ?",
    (names["event_name"],),
):
    attributes = json.loads(row["attributes"])
    wanted = {names["evaluation_name"], names["score_label"]}
    if set(attributes) != wanted:
        raise SystemExit(f"unexpected stored evaluation attributes: {attributes!r}")
    if row["span_id"] not in attempt_by_span:
        raise SystemExit(f"event is not on an attempt span: {row['span_id']}")
    stored[(
        attempt_by_span[row["span_id"]],
        attributes[names["evaluation_name"]],
        attributes[names["score_label"]],
    )] += 1
if stored != expected:
    raise SystemExit(f"stored events do not match verdict rows: {stored!r} != {expected!r}")

spans = []
for line in open(otlp_path, encoding="utf-8"):
    payload = json.loads(line)
    for resource in payload.get("resourceSpans", []):
        for scope in resource.get("scopeSpans", []):
            spans.extend(scope.get("spans", []))

def decode_attributes(items):
    decoded = {}
    for item in items:
        value = item["value"]
        decoded[item["key"]] = next(iter(value.values()))
    return decoded

exported = Counter()
fragments = []
for span in spans:
    matching = [event for event in span.get("events", [])
                if event.get("name") == names["event_name"]]
    if not matching:
        continue
    if span["spanId"] not in attempt_by_span:
        raise SystemExit(f"exported event is not on an attempt span: {span['spanId']}")
    fragments.append({"spanId": span["spanId"], "events": matching})
    for event in matching:
        attributes = decode_attributes(event.get("attributes", []))
        exported[(
            attempt_by_span[span["spanId"]],
            attributes.get(names["evaluation_name"]),
            attributes.get(names["score_label"]),
        )] += 1
if exported != expected:
    raise SystemExit(f"exported events do not match verdict rows: {exported!r} != {expected!r}")

print(json.dumps(fragments, indent=2, sort_keys=True))
PY
)"

printf 'RAW SELECT:\n%s\n' "$EVENT_SQL"
printf '%s\n' "$EVENT_ROWS"
printf 'EXPORTED JSON FRAGMENT:\n%s\n' "$EXPORTED_FRAGMENT"
printf 'PASS: every verdict exports one evaluation event on its attempt span\n'

assert_jaeger_evaluations "$DB" "$SEMCONV"

# Prime the two terminal actions without bypassing them. Each tick executes the
# real complete/abandon caller; only the role response is stubbed.
review_dir="$FLOW/demo/sections/review"
mkdir -p "$review_dir/cycles/002"
printf 'COMPLETE\n' > "$review_dir/cycles/002/decision.txt"
printf '## Decision\n\nCOMPLETE\n' > "$review_dir/cycles/002/scope.md"

HANDOFF='## Outcome

- Complete.

## Decisions

- Keep the fixture small.

## Interfaces

- None.

## Risks

- None.

## What is unproven

- Nothing in this local contract.

## Next action

- None.'
PM_FLOW_STUB="$HANDOFF" PM_FLOW_SECTION=review "$FLOWSH" tick >/dev/null

abandoned_dir="$FLOW/demo/sections/abandoned"
mkdir -p "$abandoned_dir/escalation"
printf 'exhausted\n' > "$abandoned_dir/escalation/exhausted.txt"
PM_FLOW_SECTION=abandoned "$FLOWSH" tick >/dev/null

DERIVED_SQL="SELECT o.metric || '|' || o.value_text || '|' || o.source FROM outcomes o JOIN runs r ON r.id = o.run_id WHERE o.metric = 'section_status' ORDER BY o.value_text;"
DERIVED_ROWS="$(sqlite3 "$DB" "$DERIVED_SQL")"
assert_eq "$DERIVED_ROWS" $'section_status|abandoned|derived\nsection_status|complete|derived' \
  "complete and abandoned remain derived section_status outcomes"
printf 'RAW SELECT:\n%s\n' "$DERIVED_SQL"
printf '%s\n' "$DERIVED_ROWS"
printf 'PASS: complete and abandoned section_status rows remain derived\n'

# A completed run closes explicitly as ok. The following tick dies in fail()
# at the budget check, before reaching cmd_tick's straight-line close, so only
# the owner-process EXIT trap can close it as error.
mkdir -p "$WORK/closure"
brief closure "closure/" > "$TEST_ROOT/brief.md"
"$FLOWSH" init-section closure --file "$TEST_ROOT/brief.md" >/dev/null
RUN_BASELINE="$(sqlite3 "$DB" "SELECT COALESCE(MAX(id), 0) FROM runs;")"
PM_FLOW_STUB="$SCOPE" PM_FLOW_SECTION=closure \
  "$FLOWSH" run --max-ticks 1 >/dev/null
set_project_budget 0.0001
set +e
FAILED_TICK_OUTPUT="$(PM_FLOW_SECTION=closure "$FLOWSH" tick 2>&1)"
FAILED_TICK_EXIT=$?
set -e
assert_eq "$FAILED_TICK_EXIT" "1" "budget-exhausted tick exits through fail"
[[ "$FAILED_TICK_OUTPUT" == *"project budget exhausted"* ]] || \
  fail "budget-exhausted tick did not reach the documented fail path"
set_project_budget 0

CLOSE_SQL="SELECT command || '|' || status FROM runs WHERE id > $RUN_BASELINE ORDER BY id;"
CLOSE_ROWS="$(sqlite3 "$DB" "$CLOSE_SQL")"
assert_eq "$CLOSE_ROWS" $'run|ok\ntick|error' \
  "completed run and failed tick retain distinct terminal statuses"
OPEN_SQL="SELECT COUNT(*) FROM runs WHERE id > $RUN_BASELINE AND ended_at IS NULL;"
OPEN_ROWS="$(sqlite3 "$DB" "$OPEN_SQL")"
assert_eq "$OPEN_ROWS" "0" "completed run and failed tick both have ended_at"
assert_eq "$(sqlite3 "$DB" "SELECT COUNT(*) FROM runs WHERE ended_at IS NULL;")" \
  "0" "on-demand and loop commands leave no run open"
RUNS_SQL="SELECT id || '|' || command || '|' || status || '|' || CASE WHEN ended_at IS NULL THEN 'open' ELSE 'closed' END FROM runs ORDER BY id;"
RUNS_ROWS="$(sqlite3 "$DB" "$RUNS_SQL")"
printf 'RAW SELECT:\n%s\n' "$CLOSE_SQL"
printf '%s\n' "$CLOSE_ROWS"
printf 'RAW SELECT:\n%s\n' "$OPEN_SQL"
printf '%s\n' "$OPEN_ROWS"
printf 'RUNS TABLE:\n%s\n' "$RUNS_SQL"
printf '%s\n' "$RUNS_ROWS"
printf 'PASS: completed run and fail-aborted tick close with distinct statuses\n'

# Recording is best effort even from the EXIT trap. A read-only database in a
# non-writable runs directory must not change dispatch output or exit status.
mkdir -p "$WORK/swallow-run" "$WORK/swallow-tick"
brief swallow-run "swallow-run/" > "$TEST_ROOT/brief.md"
"$FLOWSH" init-section swallow-run --file "$TEST_ROOT/brief.md" >/dev/null
brief swallow-tick "swallow-tick/" > "$TEST_ROOT/brief.md"
"$FLOWSH" init-section swallow-tick --file "$TEST_ROOT/brief.md" >/dev/null
chmod 444 "$DB"
chmod 500 "$FLOW/demo/runs"
set +e
UNWRITABLE_RUN_OUTPUT="$(PM_FLOW_STUB="$SCOPE" PM_FLOW_SECTION=swallow-run \
  "$FLOWSH" run --max-ticks 1 2>&1)"
UNWRITABLE_RUN_EXIT=$?
UNWRITABLE_TICK_OUTPUT="$(PM_FLOW_STUB="$SCOPE" PM_FLOW_SECTION=swallow-tick \
  "$FLOWSH" tick 2>&1)"
UNWRITABLE_TICK_EXIT=$?
set -e
chmod 700 "$FLOW/demo/runs"
chmod 600 "$DB"
assert_eq "$UNWRITABLE_RUN_EXIT" "0" "run exits zero with unwritable store"
assert_eq "$UNWRITABLE_TICK_EXIT" "0" "tick exits zero with unwritable store"
[[ "$UNWRITABLE_RUN_OUTPUT" == *"[tick 1] swallow-run: scope"* ]] || \
  fail "run did not print normal tick output with unwritable store"
[[ "$UNWRITABLE_TICK_OUTPUT" == *"result="* ]] || \
  fail "tick did not print its normal result with unwritable store"
printf 'UNWRITABLE RUN EXIT: %s\n%s\n' "$UNWRITABLE_RUN_EXIT" "$UNWRITABLE_RUN_OUTPUT"
printf 'UNWRITABLE TICK EXIT: %s\n%s\n' "$UNWRITABLE_TICK_EXIT" "$UNWRITABLE_TICK_OUTPUT"
printf 'PASS: run and tick dispatch and exit zero with unwritable store\n'
