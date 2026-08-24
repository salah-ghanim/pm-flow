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
printf '# Fixture contract\n\n- Use only stubbed CLIs.\n' > "$PROJECT_DIR/task_contract.md"
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

# Prepare one section whose manager has already declared it complete. Both
# cloned arms then finish in one PM handoff dispatch under the success fixture.
STUB_BIN="$TEST_ROOT/driver-bin"
mkdir -p "$STUB_BIN"
install_driver_stub() {
  /bin/cp "$1" "$STUB_BIN/stub_success.zsh"
  /bin/cp "$1" "$STUB_BIN/claude"
  chmod +x "$STUB_BIN/stub_success.zsh" "$STUB_BIN/claude"
  cat > "$STUB_BIN/codex" <<'CODEX_STUB'
#!/bin/zsh -f
output=""
prompt="${@[-1]}"
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "-o" ]]; then
    output="$2"
    shift 2
    continue
  fi
  shift || true
done
payload="$(zsh "${0:A:h}/stub_success.zsh" "$prompt")" || exit $?
python3 -c 'import json, pathlib, sys; pathlib.Path(sys.argv[1]).write_text(json.loads(sys.argv[2])["result"] + "\n")' "$output" "$payload"
print -r -- '{"type":"turn.completed"}'
CODEX_STUB
  chmod +x "$STUB_BIN/codex"
}
install_driver_stub "$REPO_ROOT/tests/fixtures/stub_success.zsh"
printf 'export PATH="%s:$PATH"\n' "$STUB_BIN" > "$FLOW/local_env.sh"

zsh "$FLOW/pm_flow.sh" --project "$PROJECT_KEY" init-section widget <<'SECTIONBRIEF' \
  > "$TEST_ROOT/init-section.out"
## Objective

- Build the comparison fixture.

## Scope

- The fixture only.

## Priority

- must-have: the comparison needs one real dispatch

## Owned paths

- `fixture/**`

## Dependencies

- None.

## Acceptance

- The fixture run completes.

## Rejection conditions

- A real backend is reached.
SECTIONBRIEF

# A COMPLETE manager decision makes the project finish in one PM dispatch. That
# gives each arm exactly one run while still exercising persona provenance.
CYCLE_DIR="$PROJECT_DIR/sections/widget/cycles/001"
mkdir -p "$CYCLE_DIR"
printf 'COMPLETE\n' > "$CYCLE_DIR/decision.txt"
FIXTURE_RUN_REL="$(<"$PROJECT_DIR/sections/widget/run_path.txt")"

# Start the compared observations with a schema-only origin store.
rm -f -- "$DB" "$DB-wal" "$DB-shm"
python3 - "$FLOW" "$DB" <<'PY'
import sys

sys.path.insert(0, sys.argv[1])
import store

store.connect(sys.argv[2]).close()
PY
assert_eq "$(sqlite3 "$DB" 'SELECT COUNT(*) FROM attempts')" "0" \
  "compare origin starts without attempts"

git -C "$COMMAND_WORK" init --quiet
git -C "$COMMAND_WORK" add .
git -C "$COMMAND_WORK" add -f \
  ".agentic/pm_flow/$PROJECT_KEY/sections/widget/cycles/001/decision.txt" \
  ".agentic/pm_flow/local_env.sh" "$FIXTURE_RUN_REL"
git -C "$COMMAND_WORK" -c user.name=pm-flow -c user.email=pm-flow@localhost \
  commit --quiet -m "comparison fixture"
ORIGIN_COMMIT="$(git -C "$COMMAND_WORK" rev-parse HEAD)"

# A compare refusal happens before a copy is announced or telemetry opens a
# run, even though this repository is otherwise ready to dispatch both arms.
REFUSAL_OUT="$TEST_ROOT/refusal.out"
REFUSAL_ERR="$TEST_ROOT/refusal.err"
if PATH="$STUB_BIN:$PATH" TMPDIR="$TEST_ROOT" \
    zsh "$FLOW/pm_flow.sh" --project "$PROJECT_KEY" \
    compare lean missing --max-ticks 5 > "$REFUSAL_OUT" 2> "$REFUSAL_ERR"; then
  fail "compare accepted a missing topology"
fi
[[ ! -s "$REFUSAL_OUT" ]] || fail "invalid compare copied or announced an arm"
refusal_error="$(<"$REFUSAL_ERR")"
[[ "$refusal_error" == *"missing"* ]] || fail "compare refusal omitted missing key"
[[ "$refusal_error" == *"$FLOW/topologies/missing.json"* ]] || \
  fail "compare refusal omitted expected path"
assert_eq "$(sqlite3 "$DB" 'SELECT COUNT(*) FROM attempts')" "0" \
  "invalid compare dispatched no arm"

COMPARE_OUT="$TEST_ROOT/compare.out"
PATH="$STUB_BIN:$PATH" TMPDIR="$TEST_ROOT" \
  zsh "$FLOW/pm_flow.sh" --project "$PROJECT_KEY" \
  compare lean heavy --max-ticks 5 > "$COMPARE_OUT"
compare_output="$(<"$COMPARE_OUT")"

assert_eq "$(printf '%s\n' "$compare_output" | grep -c '^starting_commit=')" "1" \
  "compare records one shared starting commit"
assert_eq "$(printf '%s\n' "$compare_output" | sed -n 's/^starting_commit=//p')" \
  "$ORIGIN_COMMIT" "compare records the origin starting commit"

copy_paths=("${(@f)$(printf '%s\n' "$compare_output" | \
  sed -n 's/^arm_key=[^ ]* copy_path=\(.*\) imported_run_key=[^ ]*$/\1/p')}")
assert_eq "${#copy_paths[@]}" "2" "compare prints both copy paths"
[[ "${copy_paths[1]}" != "${copy_paths[2]}" ]] || \
  fail "compare used one checkout for both arms"
[[ "${copy_paths[1]}" != "$COMMAND_WORK" && "${copy_paths[2]}" != "$COMMAND_WORK" ]] || \
  fail "compare drove an arm in the origin checkout"

arm_keys=("${(@f)$(printf '%s\n' "$compare_output" | \
  sed -n 's/^arm_key=\([^ ]*\) copy_path=.*$/\1/p')}")
assert_eq "${(F)arm_keys}" $'lean\nheavy' "compare prints both arm keys in order"
cmp "${copy_paths[1]}/.agentic/pm_flow/config.json" "$LEAN_OVERLAY" || \
  fail "lean copy config does not equal the lean overlay"
cmp "${copy_paths[2]}/.agentic/pm_flow/config.json" "$HEAVY_OVERLAY" || \
  fail "heavy copy config does not equal the heavy overlay"
cmp "$FLOW/config.json" "$TEST_ROOT/config.before.json" || \
  fail "compare changed origin config.json"

project_topologies="$(sqlite3 "$DB" \
  "SELECT t.key || '|' || p.key FROM runs r JOIN topologies t ON t.id=r.topology_id JOIN projects p ON p.id=r.project_id ORDER BY t.key")"
assert_eq "$project_topologies" $'heavy|topology-project\nlean|topology-project' \
  "compare imports both topology runs under one project"

arm_personas="$(sqlite3 "$DB" \
  "SELECT t.key || '|' || json_extract(stack.value, '$.key') FROM attempts a JOIN runs r ON r.id=a.run_id JOIN topologies t ON t.id=r.topology_id JOIN json_each(a.persona_stack) stack WHERE a.role_key='pm' AND json_extract(stack.value, '$.layer')='base' ORDER BY t.key")"
assert_eq "$arm_personas" $'heavy|pm\nlean|cpo' \
  "persona swap is confined to the first arm"

# Importing an already-seen arm store is a no-op at the run key boundary.
rows_before_reimport="$(sqlite3 "$DB" 'SELECT (SELECT COUNT(*) FROM runs) || '\''|'\'' || (SELECT COUNT(*) FROM attempts)')"
python3 - "$FLOW/compare.py" \
  "${copy_paths[1]}/.agentic/pm_flow/$PROJECT_KEY/runs/pm_flow.db" "$DB" <<'PY'
import importlib.util
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location("pm_flow_compare", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.import_store(Path(sys.argv[2]), Path(sys.argv[3]))
PY
rows_after_reimport="$(sqlite3 "$DB" 'SELECT (SELECT COUNT(*) FROM runs) || '\''|'\'' || (SELECT COUNT(*) FROM attempts)')"
assert_eq "$rows_after_reimport" "$rows_before_reimport" "run import is idempotent"

printf 'PASS: topology compare runs isolated arms and imports topology/persona provenance\n'
