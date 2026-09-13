#!/bin/zsh -f
# Knowledge state tests: discovers every tests/database_state/state/*/scenario.zsh
# and runs each in its own temp root with its own copy of the engine. Scenarios
# are owned separately; add a directory rather than editing this file.
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
SCENARIOS_DIR="$REPO_ROOT/tests/database_state/state"
SUITE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/knowledge-state-test.XXXXXX")"
SUITE_ROOT="$(cd -P "$SUITE_ROOT" && pwd -P)"
case "$SUITE_ROOT" in
  */knowledge-state-test.*) ;;
  *) printf 'unsafe test temp directory: %s\n' "$SUITE_ROOT" >&2; exit 1 ;;
esac

cleanup() {
  if [[ -n "${SUITE_ROOT:-}" && -d "$SUITE_ROOT" && \
        "$(basename "$SUITE_ROOT")" == knowledge-state-test.* ]]; then
    rm -rf -- "$SUITE_ROOT"
  fi
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

scenarios=("$SCENARIOS_DIR"/*/scenario.zsh(N))
(( ${#scenarios} > 0 )) || fail "no scenarios under $SCENARIOS_DIR"

for scenario in "${scenarios[@]}"; do
  scenario_name="${scenario:h:t}"
  # Nothing is shared between scenarios: each gets a fresh root, an engine copy
  # inside it, and a TMPDIR inside it, so one scenario's leftovers cannot make
  # another pass or fail.
  scenario_root="$SUITE_ROOT/$scenario_name"
  mkdir -p "$scenario_root/root/tmp"
  cp -R "$REPO_ROOT/template/.agentic/pm_flow" "$scenario_root/flow"
  if ! ( cd "$scenario_root/root" && \
         REPO_ROOT="$REPO_ROOT" FLOW="$scenario_root/flow" \
         TEST_ROOT="$scenario_root/root" TMPDIR="$scenario_root/root/tmp" \
         zsh -f "$scenario" ); then
    fail "$scenario_name"
  fi
  printf 'ok %s\n' "$scenario_name"
done

printf 'knowledge state tests passed\n'
