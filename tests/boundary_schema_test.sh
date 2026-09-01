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
run_case config config_valid.json ACCEPT ""
run_case config config_unknown_cli.json REJECT cli

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
