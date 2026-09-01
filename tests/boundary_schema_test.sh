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
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/boundary-schema-test.XXXXXX")"
TEST_ROOT="$(cd -P "$TEST_ROOT" && pwd -P)"
case "$TEST_ROOT" in
  */boundary-schema-test.*) ;;
  *) printf 'unsafe test temp directory: %s\n' "$TEST_ROOT" >&2; exit 1 ;;
esac

cleanup() {
  if [[ -n "${TEST_ROOT:-}" && -d "$TEST_ROOT" && \
        "$(basename "$TEST_ROOT")" == boundary-schema-test.* ]]; then
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
cp -R "$REPO_ROOT/tests/fixtures/boundary_schema" "$TEST_ROOT/fixtures"
FLOW="$COMMAND_WORK/.agentic/pm_flow"
CHECKER="$FLOW/export.py"
FIXTURES="$TEST_ROOT/fixtures"
SCRIPT_DIR="$FLOW"
PROJECT_KEY="boundary-schema-project"
PROJECT_DIR="$FLOW/$PROJECT_KEY"
DB="$PROJECT_DIR/runs/pm_flow.db"
TOPOLOGY_KEY="boundary-config"
mkdir -p "$PROJECT_DIR/runs"
printf '%s\n' "$PROJECT_KEY" > "$FLOW/.project-key"
printf '%s\n' '{"domain":"generic"}' > "$PROJECT_DIR/project.json"

python3 - "$DB" <<'PY'
import json
import sqlite3
import sys

connection = sqlite3.connect(sys.argv[1])
connection.execute(
    "CREATE TABLE clis (key TEXT PRIMARY KEY, capabilities TEXT NOT NULL)"
)
for key, models in (
    ("claude", ["claude-fable-5"]),
    ("codex", ["gpt-5.6-sol"]),
    ("copilot", []),
):
    connection.execute(
        "INSERT INTO clis (key, capabilities) VALUES (?, ?)",
        (key, json.dumps({"models": models})),
    )
connection.commit()
connection.close()
PY

# Pull only the validators under test out of pm_flow.sh without running main.
eval "$(python3 - "$FLOW/pm_flow.sh" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text()
functions = []
for name in (
    "markdown_verdict_parse",
    "validate_section_brief",
    "extract_section_priority",
    "validate_handoff",
):
    match = re.search(rf"^{name}\(\) \{{\n(.*?)^\}}\n", text, re.S | re.M)
    if not match:
        raise SystemExit(f"cannot extract {name} from {sys.argv[1]}")
    functions.append(match.group(0))
sys.stdout.write("\n".join(functions))
PY
)"

# Exercise the real role-binding guard without dispatching a CLI. Keep the
# extracted block tied to agent_exec.sh so the test cannot drift into a fourth
# implementation of the binding rules.
AGENT_BINDING_CHECK="$TEST_ROOT/agent_binding_check.py"
python3 - "$FLOW/agent_exec.sh" "$AGENT_BINDING_CHECK" <<'PY'
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text()
start = source.index("role_binding=\"$(python3 - ")
start = source.index("<<'PY'\n", start) + len("<<'PY'\n")
end = source.index("\nPY\n)\" || fail", start)
Path(sys.argv[2]).write_text(source[start:end] + "\n")
PY

shell_check() (
  fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
  }

  local kind="$1"
  local fixture="$2"
  local allowed="${3:-}"
  local body="$(/bin/cat "$FIXTURES/$fixture")"
  case "$kind" in
    brief)
      validate_section_brief "$body"
      extract_section_priority "$body" >/dev/null
      ;;
    handoff)
      validate_handoff "$body"
      ;;
    verdict)
      markdown_verdict_parse "$body" "$allowed" >/dev/null
      ;;
    *)
      printf 'no shell validator for %s\n' "$kind" >&2
      exit 2
      ;;
  esac
)

run_case() {
  local kind="$1"
  local fixture="$2"
  local expected="$3"
  local needle="$4"
  local allowed="${5:-}"
  local checker_output checker_verdict shell_output shell_verdict
  local -a command
  command=(python3 "$CHECKER" check --kind "$kind")
  [[ -z "$allowed" ]] || command+=(--allowed "$allowed")
  command+=("$FIXTURES/$fixture")

  if checker_output="$("${command[@]}" 2>&1)"; then
    checker_verdict="ACCEPT"
  else
    checker_verdict="REJECT"
  fi
  if [[ "$kind" == brief || "$kind" == handoff || "$kind" == verdict ]]; then
    if shell_output="$(shell_check "$kind" "$fixture" "$allowed" 2>&1)"; then
      shell_verdict="ACCEPT"
    else
      shell_verdict="REJECT"
    fi
    if [[ "$checker_verdict" != "$shell_verdict" ]]; then
      fail "$fixture disagreement: checker=$checker_verdict shell=$shell_verdict"
    fi
    assert_eq "$checker_verdict" "$expected" "$fixture checker verdict"
    assert_eq "$shell_verdict" "$expected" "$fixture shell verdict"
    if [[ "$expected" == "REJECT" && "$checker_output" != *"$needle"* ]]; then
      fail "$fixture checker rejection did not name '$needle': $checker_output"
    fi
    printf '%s: checker=%s shell=%s\n' \
      "$fixture" "$checker_verdict" "$shell_verdict"
  else
    assert_eq "$checker_verdict" "$expected" "$fixture checker verdict"
    if [[ "$expected" == "REJECT" && "$checker_output" != *"$needle"* ]]; then
      fail "$fixture checker rejection did not name '$needle': $checker_output"
    fi
    printf '%s: checker=%s shell=N/A\n' "$fixture" "$checker_verdict"
  fi
}

run_case brief brief_valid.md ACCEPT ""
run_case brief brief_missing_scope.md REJECT Scope
run_case brief brief_acceptance_missing_id.md REJECT acceptance_ids
run_case brief brief_priority_missing_loss.md REJECT priority_loss
run_case brief brief_priority_unknown.md REJECT priority
run_case handoff handoff_valid.md ACCEPT ""
run_case handoff handoff_missing_unproven.md REJECT "What is unproven"
run_case handoff handoff_over_budget.md REJECT word_count
run_case handoff handoff_over_bytes.md REJECT byte_count
run_case verdict verdict_valid.md ACCEPT "" "GO,GO_WITH_CHANGES,NO_GO"
run_case verdict verdict_illegal_token.md REJECT Decision "GO,GO_WITH_CHANGES,NO_GO"

write_config_topology() {
  local flow="$1"
  local fixture="$2"
  python3 - "$fixture" "$flow/topologies/$TOPOLOGY_KEY.json" "$TOPOLOGY_KEY" <<'PY'
import json
import sys
from pathlib import Path

config = json.loads(Path(sys.argv[1]).read_text())
document = {
    "version": 1,
    "key": sys.argv[3],
    "name": "Boundary config fixture",
    "description": "Exercises the configured developer binding.",
    "roles": {"developer": config["roles"]["developer"]},
}
Path(sys.argv[2]).write_text(json.dumps(document, indent=2) + "\n")
PY
}

run_config_case() {
  local fixture="$1"
  local expected="$2"
  local needle="$3"
  local checker_output checker_verdict
  local pm_output pm_verdict
  local topology_output topology_verdict topology_exit
  local agent_output agent_verdict

  cp "$FIXTURES/$fixture" "$FLOW/config.json"
  write_config_topology "$FLOW" "$FIXTURES/$fixture"

  if checker_output="$(python3 "$CHECKER" check --kind config \
      "$FIXTURES/$fixture" 2>&1)"; then
    checker_verdict="ACCEPT"
  else
    checker_verdict="REJECT"
  fi
  if pm_output="$(zsh "$FLOW/pm_flow.sh" config 2>&1)"; then
    pm_verdict="ACCEPT"
  else
    pm_verdict="REJECT"
  fi
  if topology_output="$(python3 "$FLOW/topology.py" validate "$TOPOLOGY_KEY" \
      --flow "$FLOW" 2>&1)"; then
    topology_verdict="ACCEPT"
    topology_exit=0
  else
    topology_exit=$?
    topology_verdict="REJECT"
  fi
  if agent_output="$(python3 "$AGENT_BINDING_CHECK" "$FLOW/config.json" \
      developer 1 "$PROJECT_DIR/project.json" "$COMMAND_WORK" "$PROJECT_DIR" \
      "$FLOW/schemas/config.schema.json" 2>&1)"; then
    agent_verdict="ACCEPT"
  else
    agent_verdict="REJECT"
  fi

  assert_eq "$checker_verdict" "$expected" "$fixture checker verdict"
  assert_eq "$pm_verdict" "$expected" "$fixture pm-flow verdict"
  assert_eq "$topology_verdict" "$expected" "$fixture topology verdict"
  assert_eq "$agent_verdict" "$expected" "$fixture agent-exec verdict"
  if [[ "$expected" == "REJECT" ]]; then
    [[ "$checker_output" == *"$needle"* ]] || \
      fail "$fixture checker rejection did not name '$needle': $checker_output"
    [[ "$pm_output" == *"$needle"* ]] || \
      fail "$fixture pm-flow rejection did not name '$needle': $pm_output"
    [[ "$topology_output" == *"$needle"* ]] || \
      fail "$fixture topology rejection did not name '$needle': $topology_output"
    [[ "$agent_output" == *"$needle"* ]] || \
      fail "$fixture agent-exec rejection did not name '$needle': $agent_output"
  fi

  printf '%s: pm-flow=%s topology=%s agent-exec=%s\n' \
    "$fixture" "$pm_verdict" "$topology_verdict" "$agent_verdict"
  if [[ "$fixture" == "config_valid.json" ]]; then
    local store_clis
    store_clis="$(python3 - "$DB" <<'PY'
import sqlite3
import sys

connection = sqlite3.connect(sys.argv[1])
print(",".join(row[0] for row in connection.execute("SELECT key FROM clis ORDER BY key")))
connection.close()
PY
)"
    printf '%s: store-clis=%s topology-exit=%s\n' \
      "$fixture" "$store_clis" "$topology_exit"
  fi
}

run_config_case config_valid.json ACCEPT ""
run_config_case config_unknown_cli.json REJECT unknown

missing_config_schema_case() {
  local engine_copy="$TEST_ROOT/missing-config"
  local schema_path="$engine_copy/schemas/config.schema.json"
  local pm_output topology_output agent_output
  local pm_verdict topology_verdict agent_verdict

  cp -R "$FLOW" "$engine_copy"
  cp "$FIXTURES/config_valid.json" "$engine_copy/config.json"
  write_config_topology "$engine_copy" "$FIXTURES/config_valid.json"
  rm -- "$schema_path"

  if pm_output="$(zsh "$engine_copy/pm_flow.sh" config 2>&1)"; then
    pm_verdict="ACCEPT"
  else
    pm_verdict="REJECT"
  fi
  if topology_output="$(python3 "$engine_copy/topology.py" validate \
      "$TOPOLOGY_KEY" --flow "$engine_copy" 2>&1)"; then
    topology_verdict="ACCEPT"
  else
    topology_verdict="REJECT"
  fi
  if agent_output="$(python3 "$AGENT_BINDING_CHECK" "$engine_copy/config.json" \
      developer 1 "$engine_copy/$PROJECT_KEY/project.json" "$COMMAND_WORK" \
      "$engine_copy/$PROJECT_KEY" "$schema_path" 2>&1)"; then
    agent_verdict="ACCEPT"
  else
    agent_verdict="REJECT"
  fi

  assert_eq "$pm_verdict" REJECT "pm-flow missing config schema verdict"
  assert_eq "$topology_verdict" REJECT "topology missing config schema verdict"
  assert_eq "$agent_verdict" REJECT "agent-exec missing config schema verdict"
  for output in "$pm_output" "$topology_output" "$agent_output"; do
    [[ "$output" == *"cannot load config schema at $schema_path"* ]] || \
      fail "missing config schema rejection was not loud: $output"
  done
  printf 'config.schema.json missing: pm-flow=%s topology=%s agent-exec=%s\n' \
    "$pm_verdict" "$topology_verdict" "$agent_verdict"
}

missing_config_schema_case

missing_schema_case() {
  local kind="$1"
  local schema="$2"
  local fixture="$3"
  local engine_copy="$TEST_ROOT/missing-$kind"
  local output verdict
  cp -R "$FLOW" "$engine_copy"
  rm -- "$engine_copy/schemas/$schema"
  if output="$(SCRIPT_DIR="$engine_copy" shell_check "$kind" "$fixture" 2>&1)"; then
    verdict="ACCEPT"
  else
    verdict="REJECT"
  fi
  assert_eq "$verdict" REJECT "$kind missing schema verdict"
  [[ "$output" == *"$schema"* ]] || \
    fail "$kind missing schema rejection did not name '$schema': $output"
  printf '%s missing: shell=%s error=%s\n' "$schema" "$verdict" "$output"
}

missing_schema_case brief section_brief.schema.json brief_valid.md
missing_schema_case handoff handoff.schema.json handoff_valid.md

python3 - "$FLOW/driver.zsh" "$FLOW/schemas/verdict.schema.json" <<'PY'
import json
import re
import sys
from pathlib import Path

driver_path = Path(sys.argv[1])
schema_path = Path(sys.argv[2])
driver = driver_path.read_text()
schema = json.loads(schema_path.read_text())
sets = schema["x-allowed-token-sets"]
if len(sets) != 9:
    raise SystemExit(f"expected nine schema verdict token sets, got {len(sets)}")
allowed = {tuple(tokens) for tokens in sets.values()}
literals = re.findall(
    r'''["']([A-Z][A-Z_]*(?:,[A-Z][A-Z_]*)+)["']''', driver
)
if not literals:
    raise SystemExit(f"no verdict CSV literals found in {driver_path}")
for literal in literals:
    tokens = tuple(literal.split(","))
    if tokens not in allowed:
        raise SystemExit(
            f"driver verdict CSV literal {literal!r} is absent from {schema_path.name}"
        )
print(
    f"driver verdict token sets: {len(literals)} literals use "
    f"{len(set(literals))} schema-defined sets"
)
PY

printf 'boundary schema tests passed\n'
