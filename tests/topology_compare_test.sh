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
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/topology-compare-test.XXXXXX")"
TEST_ROOT="$(cd -P "$TEST_ROOT" && pwd -P)"
case "$TEST_ROOT" in
  */topology-compare-test.*) ;;
  *) printf 'unsafe test temp directory: %s\n' "$TEST_ROOT" >&2; exit 1 ;;
esac

cleanup() {
  if [[ -n "${TEST_ROOT:-}" && -d "$TEST_ROOT" && \
        "$(basename "$TEST_ROOT")" == topology-compare-test.* ]]; then
    rm -rf -- "$TEST_ROOT"
  fi
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  [[ "$actual" == "$expected" ]] || \
    fail "$label: expected '$expected', got '$actual'"
}

COMMAND_WORK="$TEST_ROOT/command-work"
mkdir -p "$COMMAND_WORK/.agentic"
cp -R "$REPO_ROOT/template/.agentic/pm_flow" "$COMMAND_WORK/.agentic/pm_flow"
FLOW="$COMMAND_WORK/.agentic/pm_flow"
TOPOLOGY="$FLOW/topology.py"
PROJECT_KEY="topology-project"
PROJECT_DIR="$FLOW/$PROJECT_KEY"
DB="$PROJECT_DIR/runs/pm_flow.db"
mkdir -p "$PROJECT_DIR/runs"
printf '%s\n' "$PROJECT_KEY" > "$FLOW/.project-key"
printf '%s\n' '{"domain":"generic"}' > "$PROJECT_DIR/project.json"
sed 's/{{DOMAIN}}/generic/' "$FLOW/config.json" > "$TEST_ROOT/config.json"
mv -- "$TEST_ROOT/config.json" "$FLOW/config.json"
cp "$FLOW/config.json" "$TEST_ROOT/config.before.json"

# Validation must also work before a project store exists.
lean_summary="$(python3 "$TOPOLOGY" validate lean --flow "$FLOW")"
heavy_summary="$(python3 "$TOPOLOGY" validate heavy --flow "$FLOW")"
[[ "$lean_summary" == *"developer: seats=1"* ]] || fail "lean validation omitted developer summary"
[[ "$heavy_summary" == *"consultant: seats=3"* ]] || fail "heavy validation omitted consultant summary"

assert_eq "$(python3 "$TOPOLOGY" list --flow "$FLOW")" $'heavy\nlean' \
  "topology list"

python3 "$FLOW/catalog.py" --db "$DB" sync \
  --flow "$FLOW" --project "$PROJECT_KEY" --domain generic >/dev/null

LEAN_OVERLAY="$TEST_ROOT/lean.json"
HEAVY_OVERLAY="$TEST_ROOT/heavy.json"
python3 "$TOPOLOGY" overlay lean --flow "$FLOW" > "$LEAN_OVERLAY"
python3 "$TOPOLOGY" overlay heavy --flow "$FLOW" > "$HEAVY_OVERLAY"

overlay_values="$(python3 - "$FLOW/config.json" "$LEAN_OVERLAY" "$HEAVY_OVERLAY" <<'PY'
import json
import sys

config, lean, heavy = [json.load(open(path)) for path in sys.argv[1:]]
print(config["roles"]["developer"]["model"])
print(lean["roles"]["developer"]["model"])
print(heavy["roles"]["developer"]["model"])
print(len(config["roles"]["consultant"]))
print(len(lean["roles"]["consultant"]))
print(len(heavy["roles"]["consultant"]))
for overlay in (lean, heavy):
    assert {key: value for key, value in overlay.items() if key != "roles"} == {
        key: value for key, value in config.items() if key != "roles"
    }
    for role in config["roles"]:
        if role not in {"developer", "consultant"}:
            assert overlay["roles"][role] == config["roles"][role]
PY
)"
assert_eq "$overlay_values" $'gpt-5.6-sol\ngpt-5.1-codex\ngpt-5.6-sol\n2\n1\n3' \
  "overlay models and consultant seat counts"

registered_models="$(sqlite3 "$DB" \
  "SELECT json_extract(capabilities, '$.models') FROM clis ORDER BY key")"
assert_eq "$registered_models" \
  $'["claude-fable-5","claude-opus-5","claude-sonnet-5","claude-haiku-4-5-20251001"]\n["gpt-5.6-sol","gpt-5.1-codex"]\n[]' \
  "registered model lists"

attempts_before="$(sqlite3 "$DB" 'SELECT COUNT(*) FROM attempts')"
MISSING_ERR="$TEST_ROOT/missing.err"
if python3 "$TOPOLOGY" validate missing --flow "$FLOW" 2> "$MISSING_ERR"; then
  fail "missing topology validated"
fi
missing_error="$(<"$MISSING_ERR")"
[[ "$missing_error" == *"missing"* ]] || fail "missing refusal omitted key"
[[ "$missing_error" == *"$FLOW/topologies/missing.json"* ]] || \
  fail "missing refusal omitted expected path"

printf '%s\n' \
  '{"version":1,"key":"invalid-model","name":"Invalid model","description":"fixture","roles":{"developer":{"cli":"codex","model":"gpt-not-a-model","difficulty":"high"}}}' \
  > "$FLOW/topologies/invalid-model.json"
MODEL_ERR="$TEST_ROOT/model.err"
if python3 "$TOPOLOGY" validate invalid-model --flow "$FLOW" 2> "$MODEL_ERR"; then
  fail "unsupported model validated"
fi
model_error="$(<"$MODEL_ERR")"
[[ "$model_error" == *"developer"* ]] || fail "model refusal omitted role"
[[ "$model_error" == *"codex"* ]] || fail "model refusal omitted cli"
[[ "$model_error" == *"gpt-not-a-model"* ]] || fail "model refusal omitted model"

cmp "$FLOW/config.json" "$TEST_ROOT/config.before.json" || \
  fail "topology commands changed config.json"

# Model constraints belong to topology seats only. Existing suites deliberately
# use fixture models in config.json, and an inherited binding must keep passing.
printf '%s\n' \
  '{"version":1,"key":"partial","name":"Partial","description":"fixture","roles":{"developer":{"cli":"codex","model":"gpt-5.6-sol","difficulty":"high"}}}' \
  > "$FLOW/topologies/partial.json"
python3 - "$FLOW/config.json" <<'PY'
import json
import sys

path = sys.argv[1]
config = json.load(open(path))
config["roles"]["maintenance_engineer"]["model"] = "fixture-model"
with open(path, "w") as destination:
    json.dump(config, destination, indent=2)
    destination.write("\n")
PY
python3 "$TOPOLOGY" validate partial --flow "$FLOW" >/dev/null
cp "$TEST_ROOT/config.before.json" "$FLOW/config.json"

attempts_after="$(sqlite3 "$DB" 'SELECT COUNT(*) FROM attempts')"
assert_eq "$attempts_after" "$attempts_before" "refusals did not add attempts"

config_output="$(zsh "$FLOW/pm_flow.sh" --project "$PROJECT_KEY" config)"
[[ "$config_output" == *"developer: seats=1"* ]] || \
  fail "engine config command rejected existing config"

printf 'PASS: topology documents validate, overlay read-only, and refusals precede dispatch\n'
