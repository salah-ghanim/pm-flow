#!/bin/zsh -f
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1

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

cleanup() {
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

record_spans() {
  local tree="$1"
  local db="$2"
  local telemetry="$tree/template/.agentic/pm_flow/telemetry.py"
  local response="$tree/response.json"
  local run_output run_id trace_id run_span attempt_output attempt_id

  printf '%s\n' \
    '{"pm_backend":"codex","model":"gpt-test","difficulty":"high","total_cost_usd":0.5,"usage":{"input_tokens":12,"output_tokens":7}}' \
    > "$response"
  run_output="$(python3 "$telemetry" --db "$db" run-start \
    --project semconv-test --run-key semconv-test)"
  run_id="$(printf '%s\n' "$run_output" | sed -n 's/^run_id=//p')"
  trace_id="$(printf '%s\n' "$run_output" | sed -n 's/^trace_id=//p')"
  run_span="$(printf '%s\n' "$run_output" | sed -n 's/^span_id=//p')"
  [[ -n "$run_id" && -n "$trace_id" && -n "$run_span" ]] || \
    fail "run-start did not return its identifiers"

  python3 "$telemetry" --db "$db" span-start --trace "$trace_id" \
    --parent "$run_span" --run "$run_id" --name semconv.step >/dev/null
  attempt_output="$(python3 "$telemetry" --db "$db" attempt-start \
    --run "$run_id" --parent-span "$run_span" --role developer --task T1 \
    --cli codex --model gpt-test --thinking high)"
  attempt_id="$(printf '%s\n' "$attempt_output" | sed -n 's/^attempt_id=//p')"
  [[ -n "$attempt_id" ]] || fail "attempt-start did not return an attempt id"
  python3 "$telemetry" --db "$db" attempt-end --attempt "$attempt_id" \
    --response "$response"
}

assert_rows() {
  local db="$1"
  local semconv="$2"
  local provider_suffix="$3"
  local forbidden_provider_suffix="$4"
  python3 - "$db" "$semconv" "$provider_suffix" \
    "$forbidden_provider_suffix" <<'PY'
import importlib.util
import json
import sqlite3
import sys
from pathlib import Path

db, semconv_path, provider_suffix, forbidden_suffix = sys.argv[1:]
spec = importlib.util.spec_from_file_location("otel_semconv_pin", semconv_path)
semconv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(semconv)

connection = sqlite3.connect(db)
connection.row_factory = sqlite3.Row
rows = connection.execute(
    "SELECT span_id, attempt_id, attributes FROM spans ORDER BY started_at, rowid"
).fetchall()
if len(rows) != 3:
    raise SystemExit(f"expected 3 recorded spans, got {len(rows)}")

prefix = "gen" + "_ai."
revision_key = "pm_flow.semconv.revision"
for row in rows:
    attributes = json.loads(row["attributes"])
    if attributes.get(revision_key) != semconv.REVISION:
        raise SystemExit(
            f"span {row['span_id']} revision is {attributes.get(revision_key)!r}, "
            f"expected {semconv.REVISION!r}"
        )

attempt_row = next((row for row in rows if row["attempt_id"] is not None), None)
if attempt_row is None:
    raise SystemExit("no attempt span was recorded")
attributes = json.loads(attempt_row["attributes"])
expected = {
    prefix + "operation.name": "invoke_agent",
    prefix + provider_suffix: "openai",
    prefix + "agent.name": "developer",
    prefix + "request.model": "gpt-test",
    prefix + "usage.input_tokens": 12,
    prefix + "usage.output_tokens": 7,
    "pm_flow.thinking": "high",
    "pm_flow.cost_usd": 0.5,
}
for key, value in expected.items():
    if attributes.get(key) != value:
        raise SystemExit(f"{key} is {attributes.get(key)!r}, expected {value!r}")
if prefix + forbidden_suffix in attributes:
    raise SystemExit(f"unexpected provider attribute {prefix + forbidden_suffix}")
allowed_standard = {
    prefix + "operation.name",
    prefix + provider_suffix,
    prefix + "agent.name",
    prefix + "request.model",
    prefix + "usage.input_tokens",
    prefix + "usage.output_tokens",
}
unexpected = sorted(key for key in attributes if key.startswith(prefix)
                    and key not in allowed_standard)
if unexpected:
    raise SystemExit(f"unexpected standard GenAI attributes: {unexpected}")
PY
}

PRIMARY_TREE="$TEST_ROOT/primary"
SECONDARY_TREE="$TEST_ROOT/secondary"
copy_checkout_layout "$PRIMARY_TREE"
cp -R "$PRIMARY_TREE" "$SECONDARY_TREE"

PRIMARY_TELEMETRY="$PRIMARY_TREE/template/.agentic/pm_flow/telemetry.py"
PRIMARY_SEMCONV="$PRIMARY_TREE/src/pm_flow/semconv.py"
PRIMARY_DB="$PRIMARY_TREE/pm_flow.db"
primary_resolved="$(resolved_semconv_path "$PRIMARY_TELEMETRY")"
[[ "$primary_resolved" == "$(cd -P "${PRIMARY_SEMCONV:h}" && pwd -P)/semconv.py" ]] || \
  fail "primary telemetry resolved the wrong semantic-convention module: $primary_resolved"
record_spans "$PRIMARY_TREE" "$PRIMARY_DB"
assert_rows "$PRIMARY_DB" "$PRIMARY_SEMCONV" "provider.name" "system"

SECONDARY_SEMCONV="$SECONDARY_TREE/src/pm_flow/semconv.py"
SECONDARY_TELEMETRY="$SECONDARY_TREE/template/.agentic/pm_flow/telemetry.py"
SECONDARY_DB="$SECONDARY_TREE/pm_flow.db"
sed 's/^REVISION = "v1\.37\.0"$/REVISION = "v1.36.0"/' \
  "$SECONDARY_SEMCONV" > "$SECONDARY_SEMCONV.next"
mv "$SECONDARY_SEMCONV.next" "$SECONDARY_SEMCONV"
grep -q '^REVISION = "v1.36.0"$' "$SECONDARY_SEMCONV" || \
  fail "second semantic-convention pin was not applied"
secondary_resolved="$(resolved_semconv_path "$SECONDARY_TELEMETRY")"
[[ "$secondary_resolved" == "$(cd -P "${SECONDARY_SEMCONV:h}" && pwd -P)/semconv.py" ]] || \
  fail "secondary telemetry resolved the wrong semantic-convention module: $secondary_resolved"
printf 'resolved semconv.py: %s\n' "$secondary_resolved"
record_spans "$SECONDARY_TREE" "$SECONDARY_DB"
assert_rows "$SECONDARY_DB" "$SECONDARY_SEMCONV" "system" "provider.name"

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

while IFS= read -r status_line; do
  [[ -n "$status_line" ]] || continue
  status_path="${status_line[4,-1]}"
  case "$status_path" in
    src/pm_flow/semconv.py|template/.agentic/pm_flow/telemetry.py|tests/otel_semconv_test.sh) ;;
    *) fail "modified path is outside this assignment: $status_line" ;;
  esac
done <<< "$(git -C "$REPO_ROOT" status --porcelain)"

printf 'PASS: every recorded span carries its loaded revision\n'
printf 'PASS: changing only the pin changes the stored provider attribute\n'
printf 'PASS: standard GenAI literals are centralised in semconv.py\n'
