#!/bin/zsh -f
# Run every pm-flow check. Nothing here calls a model: the dispatcher is stubbed
# and the verdict parser is exercised directly, so the whole suite is free.
#
#   ./.agentic/pm_flow/tests/run.zsh
set -uo pipefail

# --- no inherited selector may reach the fixture -----------------------------
#
# A pm-flow run that dispatches this suite exports PM_FLOW_PROJECT and
# PM_FLOW_REPO_ROOT. Inherited, the driver under test honours them and writes
# its synthetic sections into the *caller's* live project instead of the work
# directory below. That is not hypothetical: portfolio review 002 found six
# fixture sections (alpha delta epsilon eta gamma zeta) and six run directories
# in the live `pm-agent` project, put there by this code path.
#
# The suites set PM_FLOW_STUB and PM_FLOW_SECTION themselves, per command, so
# clearing the whole namespace here costs them nothing.
for name in ${(k)parameters[(I)PM_FLOW_*]}; do
  unset "$name"
done

TESTS_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pm-flow-tests.XXXXXX")"
trap 'rm -rf -- "$WORK_ROOT"' EXIT HUP INT TERM

overall=0
for suite in verdict_parser transitions recovery governance on_demand; do
  printf '\n########## %s ##########\n' "$suite"
  case "$suite" in
    verdict_parser) zsh "$TESTS_DIR/$suite.zsh" || overall=1 ;;
    *)              zsh "$TESTS_DIR/$suite.zsh" "$WORK_ROOT/$suite" || overall=1 ;;
  esac
done

printf '\n'
if (( overall == 0 )); then
  printf 'all suites passed\n'
else
  printf 'at least one suite failed\n'
fi
exit "$overall"
