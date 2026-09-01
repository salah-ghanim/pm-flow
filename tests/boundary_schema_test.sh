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

run_case() {
  local kind="$1"
  local fixture="$2"
  local expected="$3"
  local needle="$4"
  local allowed="${5:-}"
  local output actual
  local -a command
  command=(python3 "$CHECKER" check --kind "$kind")
  [[ -z "$allowed" ]] || command+=(--allowed "$allowed")
  command+=("$FIXTURES/$fixture")

  if output="$("${command[@]}" 2>&1)"; then
    actual="ACCEPT"
  else
    actual="REJECT"
  fi
  assert_eq "$actual" "$expected" "$fixture verdict"
  if [[ "$expected" == "REJECT" && "$output" != *"$needle"* ]]; then
    fail "$fixture rejection did not name '$needle': $output"
  fi
  printf '%s: %s\n' "$fixture" "$actual"
}

run_case brief brief_valid.md ACCEPT ""
run_case brief brief_missing_scope.md REJECT Scope
run_case brief brief_acceptance_missing_id.md REJECT acceptance_ids
run_case handoff handoff_valid.md ACCEPT ""
run_case handoff handoff_missing_unproven.md REJECT "What is unproven"
run_case handoff handoff_over_budget.md REJECT word_count
run_case verdict verdict_valid.md ACCEPT "" "GO,GO_WITH_CHANGES,NO_GO"
run_case verdict verdict_illegal_token.md REJECT Decision "GO,GO_WITH_CHANGES,NO_GO"
run_case config config_valid.json ACCEPT ""
run_case config config_unknown_cli.json REJECT cli

printf 'boundary schema tests passed\n'
