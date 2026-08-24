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

PERSONA_REFUSAL_OUT="$TEST_ROOT/persona-refusal.out"
PERSONA_REFUSAL_ERR="$TEST_ROOT/persona-refusal.err"
if PATH="$STUB_BIN:$PATH" TMPDIR="$TEST_ROOT" \
    zsh "$FLOW/pm_flow.sh" --project "$PROJECT_KEY" compare lean heavy \
    --persona missing:pm=cpo > "$PERSONA_REFUSAL_OUT" 2> "$PERSONA_REFUSAL_ERR"; then
  fail "compare accepted a persona swap for a topology outside its arms"
fi
[[ ! -s "$PERSONA_REFUSAL_OUT" ]] || \
  fail "invalid persona swap copied or announced an arm"
[[ "$(<"$PERSONA_REFUSAL_ERR")" == *"not one of the comparison arms"* ]] || \
  fail "persona topology refusal omitted the arm constraint"
assert_eq "$(sqlite3 "$DB" 'SELECT COUNT(*) FROM attempts')" "0" \
  "invalid persona swap dispatched no arm"

COMPARE_OUT="$TEST_ROOT/compare.out"
PATH="$STUB_BIN:$PATH" TMPDIR="$TEST_ROOT" \
  zsh "$FLOW/pm_flow.sh" --project "$PROJECT_KEY" \
  compare lean heavy --max-ticks 5 --persona lean:pm=cpo --keep-copies \
  > "$COMPARE_OUT"
compare_output="$(<"$COMPARE_OUT")"

assert_eq "$(printf '%s\n' "$compare_output" | grep -c '^starting_commit=')" "1" \
  "compare records one shared starting commit"
assert_eq "$(printf '%s\n' "$compare_output" | sed -n 's/^starting_commit=//p')" \
  "$ORIGIN_COMMIT" "compare records the origin starting commit"

copy_paths=("${(@f)$(printf '%s\n' "$compare_output" | \
  sed -n 's/^arm_key=[^ ]* copy_path=\(.*\) imported_run_key=[^ ]* copy_status=[^ ]*$/\1/p')}")
assert_eq "${#copy_paths[@]}" "2" "compare prints both copy paths"
[[ "${copy_paths[1]}" != "${copy_paths[2]}" ]] || \
  fail "compare used one checkout for both arms"
[[ "${copy_paths[1]}" != "$COMMAND_WORK" && "${copy_paths[2]}" != "$COMMAND_WORK" ]] || \
  fail "compare drove an arm in the origin checkout"

arm_keys=("${(@f)$(printf '%s\n' "$compare_output" | \
  sed -n 's/^arm_key=\([^ ]*\) copy_path=.*$/\1/p')}")
assert_eq "${(F)arm_keys}" $'lean\nheavy' "compare prints both arm keys in order"
assert_eq "$(printf '%s\n' "$compare_output" | grep -c 'copy_status=retained$')" "2" \
  "--keep-copies reports both retained arm copies"
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
  "operator persona swap is confined to the named arm"

metric_order="$(printf '%s\n' "$compare_output" | awk -F'\t' \
  '$1 ~ /^(cost_usd|tokens|cycles_to_done|rescue_rate|abandon_rate|escalation_depth|wall_clock_s|n_runs)$/ {print $1}')"
assert_eq "$metric_order" \
  $'cost_usd\ntokens\ncycles_to_done\nrescue_rate\nabandon_rate\nescalation_depth\nwall_clock_s\nn_runs' \
  "run comparison prints the metric contract in order"
assert_eq "$(printf '%s\n' "$compare_output" | grep '^cycles_to_done' | cut -f2-3)" \
  $'1.00\t1.00' "run comparison imports completion outcomes"
main_arm_personas="$(printf '%s\n' "$compare_output" | awk -F'\t' \
  '$1 == "arm" {arm=$2} $1 == "personas" {print arm "|" $2}')"
printf '%s\n' "$main_arm_personas" | grep '^lean|.*pm=cpo' >/dev/null || \
  fail "lean report block omits the requested pm=cpo persona"
printf '%s\n' "$main_arm_personas" | grep '^heavy|.*pm=pm' >/dev/null || \
  fail "heavy report block omits its base pm persona"
assert_eq "$(printf '%s\n' "$compare_output" | tail -n 1)" \
  "Limits: lean n=1; heavy n=1. No difference between the arms can be inferred." \
  "one-run arms end with the inference limit"

# Importing an already-seen arm store is a no-op at the run key boundary.
rows_before_reimport="$(sqlite3 "$DB" 'SELECT (SELECT COUNT(*) FROM runs) || '\''|'\'' || (SELECT COUNT(*) FROM attempts) || '\''|'\'' || (SELECT COUNT(*) FROM outcomes) || '\''|'\'' || (SELECT COUNT(*) FROM topology_edges)')"
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
rows_after_reimport="$(sqlite3 "$DB" 'SELECT (SELECT COUNT(*) FROM runs) || '\''|'\'' || (SELECT COUNT(*) FROM attempts) || '\''|'\'' || (SELECT COUNT(*) FROM outcomes) || '\''|'\'' || (SELECT COUNT(*) FROM topology_edges)')"
assert_eq "$rows_after_reimport" "$rows_before_reimport" "run import is idempotent"

# A second comparison omits --persona on purpose. Its output, then its imported
# persona stacks, prove that the command performs no swap of its own. The
# default retention policy is observed from the command's own status lines.
python3 "$FLOW/catalog.py" --db "$DB" sync --flow "$FLOW" --engine "$FLOW" \
  --project "$PROJECT_KEY" --domain generic >/dev/null
REMOVED_OUT="$TEST_ROOT/removed.out"
PATH="$STUB_BIN:$PATH" TMPDIR="$TEST_ROOT" \
  zsh "$FLOW/pm_flow.sh" --project "$PROJECT_KEY" \
  compare lean heavy --max-ticks 5 > "$REMOVED_OUT"
removed_output="$(<"$REMOVED_OUT")"
assert_eq "$(printf '%s\n' "$removed_output" | grep -c 'copy_status=removed$')" "2" \
  "default compare reports both arm copies removed"
removed_run_keys=("${(@f)$(printf '%s\n' "$removed_output" | \
  sed -n 's/^arm_key=[^ ]* copy_path=.* imported_run_key=\([^ ]*\) copy_status=removed$/\1/p')}")
assert_eq "${#removed_run_keys[@]}" "2" "removed comparison prints two run keys"
unswapped_personas="$(sqlite3 "$DB" \
  "SELECT t.key || '|' || json_extract(stack.value, '$.key') FROM attempts a JOIN runs r ON r.id=a.run_id JOIN topologies t ON t.id=r.topology_id JOIN json_each(a.persona_stack) stack WHERE r.run_key IN ('${removed_run_keys[1]}','${removed_run_keys[2]}') AND a.role_key='pm' AND json_extract(stack.value, '$.layer')='base' ORDER BY t.key")"
assert_eq "$unswapped_personas" $'heavy|pm\nlean|pm' \
  "compare without --persona performs no persona swap"

# Exercise compare from the installed layout: the repository owns only project
# data, while topology documents, domain definitions and personas stay in the
# engine. Two complete sections make each arm dispatch twice in one run.
DATA_WORK="$TEST_ROOT/data-only-work"
DATA_FLOW="$DATA_WORK/.agentic/pm_flow"
DATA_PROJECT_KEY="data-topology-project"
DATA_PROJECT_DIR="$DATA_FLOW/$DATA_PROJECT_KEY"
DATA_DB="$DATA_PROJECT_DIR/runs/pm_flow.db"
mkdir -p "$DATA_PROJECT_DIR/runs"
cp "$TEST_ROOT/config.before.json" "$DATA_FLOW/config.json"
printf '%s\n' "$DATA_PROJECT_KEY" > "$DATA_FLOW/.project-key"
printf 'export PATH="%s:$PATH"\n' "$STUB_BIN" > "$DATA_FLOW/local_env.sh"
printf '%s\n' '{"domain":"generic"}' > "$DATA_PROJECT_DIR/project.json"
printf '# Data-only fixture contract\n\n- Use only stubbed CLIs.\n' \
  > "$DATA_PROJECT_DIR/task_contract.md"

for section_key in alpha beta; do
  PM_FLOW_ENGINE_ROOT="$FLOW" PM_FLOW_FLOW_DIR="$DATA_FLOW" \
    PM_FLOW_REPO_ROOT="$DATA_WORK" \
    zsh "$FLOW/pm_flow.sh" --project "$DATA_PROJECT_KEY" \
    init-section "$section_key" <<SECTIONBRIEF \
    > "$TEST_ROOT/data-init-$section_key.out"
## Objective

- Build data-only comparison fixture $section_key.

## Scope

- The fixture only.

## Priority

- must-have: the comparison needs a real dispatch

## Owned paths

- \`fixture/$section_key/**\`

## Dependencies

- None.

## Acceptance

- The fixture run completes.

## Rejection conditions

- A real backend is reached.
SECTIONBRIEF
  mkdir -p "$DATA_PROJECT_DIR/sections/$section_key/cycles/001"
  printf 'COMPLETE\n' \
    > "$DATA_PROJECT_DIR/sections/$section_key/cycles/001/decision.txt"
done

data_flow_entries="$(for entry in "$DATA_FLOW"/*(DN); do
  basename "$entry"
done | sort)"
assert_eq "$data_flow_entries" \
  $'.project-key\nconfig.json\ndata-topology-project\nlocal_env.sh' \
  "data-only flow directory contains no engine assets"

git -C "$DATA_WORK" init --quiet
git -C "$DATA_WORK" add .
git -C "$DATA_WORK" add -f \
  ".agentic/pm_flow/$DATA_PROJECT_KEY/sections/alpha/cycles/001/decision.txt" \
  ".agentic/pm_flow/$DATA_PROJECT_KEY/sections/beta/cycles/001/decision.txt"
git -C "$DATA_WORK" -c user.name=pm-flow -c user.email=pm-flow@localhost \
  commit --quiet -m "data-only comparison fixture"

python3 - "$FLOW" "$DATA_DB" <<'PY'
import sys

sys.path.insert(0, sys.argv[1])
import store

store.connect(sys.argv[2]).close()
PY

# The data-only refusal names both places searched and leaves the origin store
# untouched, before a checkout or report can write anything to stdout.
DATA_REFUSAL_OUT="$TEST_ROOT/data-refusal.out"
DATA_REFUSAL_ERR="$TEST_ROOT/data-refusal.err"
data_attempts_before="$(sqlite3 "$DATA_DB" 'SELECT COUNT(*) FROM attempts')"
if (cd "$DATA_WORK" && PATH="$STUB_BIN:$PATH" \
    PM_FLOW_ENGINE_ROOT="$FLOW" PM_FLOW_FLOW_DIR="$DATA_FLOW" \
    PM_FLOW_REPO_ROOT="$DATA_WORK" \
    zsh "$FLOW/pm_flow.sh" --project "$DATA_PROJECT_KEY" \
    compare heavy missing --max-ticks 5) \
    > "$DATA_REFUSAL_OUT" 2> "$DATA_REFUSAL_ERR"; then
  fail "data-only compare accepted a missing topology"
fi
[[ ! -s "$DATA_REFUSAL_OUT" ]] || \
  fail "data-only refusal wrote to stdout"
data_refusal_error="$(<"$DATA_REFUSAL_ERR")"
[[ "$data_refusal_error" == *"$DATA_FLOW/topologies/missing.json"* ]] || \
  fail "data-only refusal omitted the flow topology path"
[[ "$data_refusal_error" == *"$FLOW/topologies/missing.json"* ]] || \
  fail "data-only refusal omitted the engine topology path"
assert_eq "$(sqlite3 "$DATA_DB" 'SELECT COUNT(*) FROM attempts')" \
  "$data_attempts_before" "data-only refusal dispatched no arm"

python3 - "$FLOW/compare.py" "$DATA_FLOW" "$FLOW" <<'PY' || \
  fail "data-only persona swap could not resolve a packaged persona"
import importlib.util
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location("pm_flow_compare", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
flow = Path(sys.argv[2])
engine = Path(sys.argv[3])
overlays = {
    key: module.topology.validate(key, flow, engine)[0]
    for key in ("lean", "heavy")
}
assert module.parse_persona_swaps(
    ["lean:pm=cpo"], ("lean", "heavy"), overlays, flow, engine
) == {"lean": [("pm", "cpo")], "heavy": []}
PY

DATA_COMPARE_OUT="$TEST_ROOT/data-compare.out"
(cd "$DATA_WORK" && PATH="$STUB_BIN:$PATH" \
  PM_FLOW_ENGINE_ROOT="$FLOW" PM_FLOW_FLOW_DIR="$DATA_FLOW" \
  PM_FLOW_REPO_ROOT="$DATA_WORK" \
  zsh "$FLOW/pm_flow.sh" --project "$DATA_PROJECT_KEY" \
  compare lean heavy --max-ticks 5 --keep-copies) \
  > "$DATA_COMPARE_OUT"
data_compare_output="$(<"$DATA_COMPARE_OUT")"

data_copy_paths=("${(@f)$(printf '%s\n' "$data_compare_output" | \
  sed -n 's/^arm_key=[^ ]* copy_path=\(.*\) imported_run_key=[^ ]* copy_status=[^ ]*$/\1/p')}")
assert_eq "${#data_copy_paths[@]}" "2" \
  "data-only compare prints both copy paths"
[[ "${data_copy_paths[1]}" != "${data_copy_paths[2]}" ]] || \
  fail "data-only compare used one checkout for both arms"
[[ "${data_copy_paths[1]}" != "$DATA_WORK" && \
   "${data_copy_paths[2]}" != "$DATA_WORK" ]] || \
  fail "data-only compare drove an arm in the origin checkout"

data_project_topologies="$(sqlite3 "$DATA_DB" \
  "SELECT DISTINCT t.key || '|' || p.key FROM runs r JOIN topologies t ON t.id=r.topology_id JOIN projects p ON p.id=r.project_id ORDER BY t.key")"
assert_eq "$data_project_topologies" \
  $'heavy|data-topology-project\nlean|data-topology-project' \
  "data-only compare imports both topology runs under one project"

data_arm_sizes="$(sqlite3 "$DATA_DB" \
  "SELECT t.key || '|' || COUNT(DISTINCT r.id) || '|' || COUNT(a.id) FROM runs r JOIN topologies t ON t.id=r.topology_id JOIN attempts a ON a.run_id=r.id GROUP BY t.key ORDER BY t.key")"
assert_eq "$data_arm_sizes" $'heavy|1|2\nlean|1|2' \
  "data-only arm size counts one run containing two attempts"
assert_eq "$(printf '%s\n' "$data_compare_output" | tail -n 1)" \
  "Limits: lean n=1; heavy n=1. No difference between the arms can be inferred." \
  "data-only limits count runs rather than dispatches"

printf '%s\n' "$data_compare_output" | awk -F'\t' \
  '$1 == "wall_clock_s" && $2 + 0 > 0 && $3 + 0 > 0 {found=1} END {exit !found}' || \
  fail "data-only compare wall clocks are not both greater than zero"
data_finished_runs="$(sqlite3 "$DATA_DB" \
  "SELECT t.key || '|' || COUNT(*) FROM runs r JOIN topologies t ON t.id=r.topology_id WHERE r.ended_at IS NOT NULL AND r.status <> 'running' GROUP BY t.key ORDER BY t.key")"
assert_eq "$data_finished_runs" $'heavy|1\nlean|1' \
  "data-only compare imports finished runs"

data_arm_personas="$(sqlite3 "$DATA_DB" \
  "SELECT DISTINCT t.key || '|' || json_extract(stack.value, '$.key') FROM attempts a JOIN runs r ON r.id=a.run_id JOIN topologies t ON t.id=r.topology_id JOIN json_each(a.persona_stack) stack WHERE a.role_key='pm' AND json_extract(stack.value, '$.layer')='base' ORDER BY t.key")"
assert_eq "$data_arm_personas" $'heavy|pm\nlean|pm' \
  "data-only compare records base personas from the engine"

data_origin_edges="$(sqlite3 "$DATA_DB" \
  "SELECT e.from_role || '|' || e.to_role || '|' || e.kind FROM topology_edges e JOIN topologies t ON t.id=e.topology_id WHERE t.key='lean' ORDER BY e.from_role, e.to_role, e.kind")"
[[ -n "$data_origin_edges" ]] || fail "data-only import omitted topology edges"
data_arm_edges="$(sqlite3 \
  "${data_copy_paths[1]}/.agentic/pm_flow/$DATA_PROJECT_KEY/runs/pm_flow.db" \
  "SELECT e.from_role || '|' || e.to_role || '|' || e.kind FROM topology_edges e JOIN topologies t ON t.id=e.topology_id WHERE t.key='lean' ORDER BY e.from_role, e.to_role, e.kind")"
assert_eq "$data_origin_edges" "$data_arm_edges" \
  "imported topology edges equal the retained arm store"

# Seed a separate report-only project through the public telemetry commands.
# Timestamps are normalized afterwards so wall-clock expectations are literal,
# while attempts, prices, tokens, personas, cycles and outcomes all enter
# through the same engine interface a live run uses.
REPORT_PROJECT_KEY="report-project"
REPORT_PROJECT_DIR="$FLOW/$REPORT_PROJECT_KEY"
REPORT_DB="$REPORT_PROJECT_DIR/runs/pm_flow.db"
mkdir -p "$REPORT_PROJECT_DIR/runs"
printf '%s\n' '{"domain":"generic"}' > "$REPORT_PROJECT_DIR/project.json"
printf '# Report fixture\n' > "$REPORT_PROJECT_DIR/task_contract.md"
for topology_key in lean heavy; do
  python3 "$FLOW/catalog.py" --db "$REPORT_DB" sync --flow "$FLOW" \
    --engine "$FLOW" --project "$REPORT_PROJECT_KEY" --domain generic \
    --topology "$topology_key" >/dev/null
done

TELEMETRY="$FLOW/telemetry.py"
response_index=0
seed_attempt() {
  local run_key="$1" role="$2" task="$3" cycle="$4" amount="$5"
  local input_tokens="$6" output_tokens="$7" attempt_output attempt_id response
  response_index=$(( response_index + 1 ))
  response="$REPORT_PROJECT_DIR/response-$response_index.json"
  printf '{"usage":{"input_tokens":%s,"output_tokens":%s},"total_cost_usd":%s}\n' \
    "$input_tokens" "$output_tokens" "$amount" > "$response"
  attempt_output="$(python3 "$TELEMETRY" --db "$REPORT_DB" attempt-start \
    --run "$run_key" --role "$role" --task "$task" --cycle "$cycle" \
    --label "$role-$task")"
  attempt_id="$(printf '%s\n' "$attempt_output" | sed -n 's/^attempt_id=//p')"
  python3 "$TELEMETRY" --db "$REPORT_DB" attempt-end --attempt "$attempt_id" \
    --response "$response" --cost-usd "$amount"
  printf '%s\n' "$attempt_id"
}

for run_spec in 'lean-fixture-1 lean' 'lean-fixture-2 lean' 'heavy-fixture-1 heavy'; do
  set -- ${(z)run_spec}
  python3 "$TELEMETRY" --db "$REPORT_DB" run-start \
    --project "$REPORT_PROJECT_KEY" --topology "$2" --run-key "$1" >/dev/null
done

alpha_attempt="$(seed_attempt lean-fixture-1 developer alpha 2 1.25 80 20)"
seed_attempt lean-fixture-1 consultant alpha 2 0.25 15 5 >/dev/null
seed_attempt lean-fixture-1 10x_developer alpha 3 0.50 40 10 >/dev/null
seed_attempt lean-fixture-1 pm beta 4 0.75 20 10 >/dev/null
seed_attempt lean-fixture-1 cpo beta 4 0.25 5 5 >/dev/null
seed_attempt lean-fixture-2 developer delta 1 0.50 30 10 >/dev/null
seed_attempt lean-fixture-2 consultant delta 1 0.50 40 20 >/dev/null
seed_attempt heavy-fixture-1 developer gamma 2 2.00 160 40 >/dev/null
seed_attempt heavy-fixture-1 consultant gamma 2 0.50 40 10 >/dev/null

python3 "$TELEMETRY" --db "$REPORT_DB" outcome --run lean-fixture-1 \
  --task alpha --attempt "$alpha_attempt" --metric section_status \
  --text complete --source derived
python3 "$TELEMETRY" --db "$REPORT_DB" outcome --run lean-fixture-1 \
  --task beta --metric section_status --text abandoned --source derived
python3 "$TELEMETRY" --db "$REPORT_DB" outcome --run lean-fixture-2 \
  --task delta --metric section_status --text complete --source derived
python3 "$TELEMETRY" --db "$REPORT_DB" outcome --run heavy-fixture-1 \
  --task gamma --metric section_status --text complete --source derived
for run_key in lean-fixture-1 lean-fixture-2 heavy-fixture-1; do
  python3 "$TELEMETRY" --db "$REPORT_DB" run-end --run "$run_key" \
    --status finished
done
sqlite3 "$REPORT_DB" <<'SQL'
UPDATE runs SET started_at = 1000.0, ended_at = 1010.0 WHERE run_key = 'lean-fixture-1';
UPDATE runs SET started_at = 2000.0, ended_at = 2020.0 WHERE run_key = 'lean-fixture-2';
UPDATE runs SET started_at = 3000.0, ended_at = 3012.5 WHERE run_key = 'heavy-fixture-1';
SQL

REPORT_OUT="$TEST_ROOT/report.out"
zsh "$FLOW/pm_flow.sh" --project "$REPORT_PROJECT_KEY" compare --report \
  lean-fixture-1 heavy-fixture-1 > "$REPORT_OUT"
report_output="$(<"$REPORT_OUT")"
assert_eq "$(printf '%s\n' "$report_output" | head -n 1)" $'metric\tlean\theavy' \
  "report header names both arms"
printf '%s\n' "$report_output" | grep -Fx $'cost_usd\t4.0000\t2.5000' >/dev/null || \
  fail "cost_usd metric differs from literal fixture values"
printf '%s\n' "$report_output" | grep -Fx $'tokens\t310\t250' >/dev/null || \
  fail "tokens metric differs from literal fixture values"
printf '%s\n' "$report_output" | grep -Fx $'cycles_to_done\t2.00\t2.00' >/dev/null || \
  fail "cycles_to_done metric differs from literal fixture values"
printf '%s\n' "$report_output" | grep -Fx $'rescue_rate\t0.33\t0.00' >/dev/null || \
  fail "rescue_rate metric differs from literal fixture values"
printf '%s\n' "$report_output" | grep -Fx $'abandon_rate\t0.33\t0.00' >/dev/null || \
  fail "abandon_rate metric differs from literal fixture values"
printf '%s\n' "$report_output" | grep -Fx $'escalation_depth\t1\t1' >/dev/null || \
  fail "escalation_depth metric differs from literal fixture values"
printf '%s\n' "$report_output" | grep -Fx $'wall_clock_s\t30.0\t12.5' >/dev/null || \
  fail "wall_clock_s metric differs from literal fixture values"
printf '%s\n' "$report_output" | grep -Fx $'n_runs\t2\t1' >/dev/null || \
  fail "n_runs metric differs from literal fixture values"
assert_eq "$(printf '%s\n' "$report_output" | tail -n 1)" \
  "Limits: lean n=2; heavy n=1. No difference between the arms can be inferred." \
  "limits read differently-sized arms from the store"
assert_eq "$(python3 "$FLOW/cost.py" total "$REPORT_PROJECT_DIR")" "6.5000" \
  "report arm costs reconcile with cost.py total"

# The cost formula's forbidden alternative is observationally equivalent on a
# normalized store, so this source guard makes that required mutation fail.
grep -F 'import cost' "$FLOW/compare.py" >/dev/null || \
  fail "report does not import cost.py accounting"
grep -F 'cost.import_legacy(project_dir)' "$FLOW/compare.py" >/dev/null || \
  fail "report does not import legacy cost records before accounting"
! grep -F 'topology_comparison' "$FLOW/compare.py" >/dev/null || \
  fail "report reads cost from topology_comparison"
driver_source="$(<"$FLOW/driver.zsh")"
[[ "$driver_source" == *'telemetry_record_outcome "$(basename "$section_dir")" abandoned'* ]] || \
  fail "abandonment does not emit section_status"
[[ "$driver_source" == *'telemetry_record_outcome "$section_key" complete'* ]] || \
  fail "completion does not emit section_status"

printf 'PASS: topology compare reports literal metrics, limits, personas, and copy retention\n'
