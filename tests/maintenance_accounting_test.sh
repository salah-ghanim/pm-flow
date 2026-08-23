#!/bin/zsh -f
set -euo pipefail

# The HARNESS escalation path, end to end, without spending a model dispatch.
#
# This path was built to stop a harness obstruction being sent to a consultant
# panel, and it was unproven on a real run for exactly as long as it took a
# usage limit to expose the accounting bug it contained: `do_maintain` wrote
# `attempts.txt` *before* dispatching, so a dispatch the environment killed
# spent a maintenance attempt that never produced a report. Two of those and a
# plumbing problem is in front of the panel.
#
# `dispatch_role` is the only thing stubbed. Everything else is the real driver.

REPO_ROOT="$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pm-flow-maint.XXXXXX")"
TEST_ROOT="$(cd -P "$TEST_ROOT" && pwd -P)"
case "$TEST_ROOT" in
  */pm-flow-maint.*) ;;
  *) printf 'unsafe test temp directory: %s\n' "$TEST_ROOT" >&2; exit 1 ;;
esac
# No EXIT trap: command substitution inherits it, and the fixture would be
# deleted the moment the first helper returned.

FAILED=0
check() {
  if [[ "$2" == "$3" ]]; then
    printf '  ok   %-52s %s\n' "$1" "$2"
  else
    printf '  FAIL %-52s %s (wanted %s)\n' "$1" "$2" "$3"
    FAILED=1
  fi
}

# Overridable so this file can be pointed at a packaged install, and so the
# fix it guards can be mutation-tested against a reverted copy.
SCRIPT_DIR="${PM_FLOW_TEST_ENGINE:-$REPO_ROOT/.agentic/pm_flow}"
[[ -f "$SCRIPT_DIR/driver.zsh" ]] || { printf 'no installed driver at %s\n' "$SCRIPT_DIR" >&2; exit 1; }
AGENT_CONFIG_FILE="$SCRIPT_DIR/config.json"
PROJECT_ROOT="$TEST_ROOT"
STATE_DIR="$TEST_ROOT/project_state"
mkdir -p "$STATE_DIR"

# driver.zsh expects these from pm_flow.sh. The verdict parser is taken from
# the real pm_flow.sh rather than reimplemented: without it, do_maintain's
# `|| printf UNRESOLVED` fallback silently swallows every verdict and the
# CLEARED and NOT_PLUMBING branches would pass this file without ever running.
fail() { printf 'FAIL(driver): %s\n' "$*" >&2; exit 9; }
eval "$(sed -n '/^markdown_verdict_parse() {/,/^}/p' "$SCRIPT_DIR/pm_flow.sh")"
eval "$(sed -n '/^extract_markdown_decision() {/,/^}/p' "$SCRIPT_DIR/pm_flow.sh")"
source "$SCRIPT_DIR/driver.zsh"

# Guard the guard: if the parser ever stops resolving, say so here instead of
# letting the fallback make the verdict tests vacuous.
[[ "$(extract_markdown_decision "$(printf '# Decision\n\nCLEARED - probe\n')" \
      "CLEARED,NOT_PLUMBING,UNRESOLVED" 2>/dev/null)" == "CLEARED" ]] ||
  { printf 'the verdict parser did not resolve; the rest of this file would be vacuous\n' >&2; exit 1; }

# --- stubs, kept to the smallest possible surface ----------------------------
STUB_MODE="report"      # report | die
STUB_VERDICT="CLEARED"
end_worktree_dispatch() { : }
with_repo_git_lock() { "$@" }
# Records the verdict it was called with, so the test can prove a repair is
# committed on every verdict rather than only on CLEARED.
commit_maintenance_work() { printf '%s\n' "${4:-MISSING}" >> "$TEST_ROOT/commits.log" }
commits_for() { grep -c "^$1$" "$TEST_ROOT/commits.log" 2>/dev/null || printf '0\n' }
compose_role_task() { printf 'stub prompt\n' }
task_file() { printf '%s\n' "$SCRIPT_DIR/tasks/section_maintenance.md" }
dispatch_role() {
  local out="$3"
  if [[ "$STUB_MODE" == "die" ]]; then
    # What a usage limit looks like from here: the driver aborts the action and
    # never returns to do_maintain.
    fail "role maintenance_engineer did not produce a usable response"
  fi
  printf '# Decision\n\n%s - stubbed\n' "$STUB_VERDICT" > "$out"
}

mk_section() {   # name -> a section at the maintain threshold (NO_GO/HARNESS)
  local sd="$TEST_ROOT/sections/$1" i cdir
  for i in 1 2; do
    cdir="$(cycle_dir_for "$sd" "$i")"
    mkdir -p "$cdir"
    : > "$cdir/assignment.md"; : > "$cdir/result.md"; : > "$cdir/review.md"
    printf 'NO_GO\n' > "$cdir/decision.txt"
    printf 'HARNESS\n' > "$cdir/obstruction.txt"
  done
  printf 'active\n' > "$sd/status.txt"
  : > "$sd/brief.md"; : > "$sd/state.md"
  printf '%s\n' "$sd"
}

printf 'threshold=%s maintenance_budget=%s step_ceiling=%s\n\n' \
  "$(escalation_threshold)" "$(maintenance_budget)" "$(step_claim_ceiling)"

# --- 1. routing: the obstruction decides, most recent wins -------------------
printf 'routing\n'
sd="$(mk_section route)"
check "HARNESS at threshold routes to maintenance" "$(section_next_action "$sd")" maintain
printf 'TASK\n' > "$(cycle_dir_for "$sd" 2)/obstruction.txt"
check "TASK at threshold convenes the panel" "$(section_next_action "$sd")" escalate
rm -f "$(cycle_dir_for "$sd" 2)/obstruction.txt"
check "an unclassified rejection is read as TASK" "$(section_next_action "$sd")" escalate

# --- 2. a killed dispatch must not spend an attempt --------------------------
printf '\nattempt accounting\n'
sd="$(mk_section killed)"
STUB_MODE="die"
( do_maintain "$sd" ) >/dev/null 2>&1 || true
check "killed dispatch leaves the budget unspent" "$(maintenance_attempts "$sd")" 0
check "killed dispatch records no verdict" \
  "$([[ -f "$sd/maintenance/decision.txt" ]] && echo present || echo absent)" absent
check "section is still routed to maintenance, not the panel" \
  "$(section_next_action "$sd")" maintain
check "a dispatch that died committed nothing" \
  "$([[ -f "$TEST_ROOT/commits.log" ]] && echo some || echo none)" none

# a second and third killed dispatch still spend nothing, but the step claim
# accumulates so this cannot retry forever.
( do_maintain "$sd" ) >/dev/null 2>&1 || true
( do_maintain "$sd" ) >/dev/null 2>&1 || true
check "three killed dispatches still spend no attempt" "$(maintenance_attempts "$sd")" 0
claimed="$(first_line_or "$sd/maintenance/.claim-maintain-1/attempts.txt" 0)"
check "the step claim counted the retries instead" "$claimed" 3
ceiling_status=0
( do_maintain "$sd" ) >/dev/null 2>&1 || ceiling_status=$?
check "a fourth dispatch is refused by the step ceiling" "$ceiling_status" 9
check "the claim, not the budget, is what bounded it" \
  "$(first_line_or "$sd/maintenance/.claim-maintain-1/attempts.txt" 0)" 4
check "the budget survived all four" "$(maintenance_attempts "$sd")" 0

# --- 3. a reported verdict is what spends the budget ------------------------
printf '\nverdicts\n'
STUB_MODE="report"

sd="$(mk_section unresolved)"; STUB_VERDICT="UNRESOLVED"
do_maintain "$sd" >/dev/null 2>&1
check "UNRESOLVED spends one attempt" "$(maintenance_attempts "$sd")" 1
check "an UNRESOLVED repair is still committed" "$(commits_for UNRESOLVED)" 1
check "UNRESOLVED stays with maintenance while budget remains" \
  "$(section_next_action "$sd")" maintain
do_maintain "$sd" >/dev/null 2>&1
check "a second UNRESOLVED exhausts the budget" "$(maintenance_attempts "$sd")" 2
check "an exhausted budget hands the section to the panel" \
  "$(section_next_action "$sd")" escalate

sd="$(mk_section cleared)"; STUB_VERDICT="CLEARED"
do_maintain "$sd" >/dev/null 2>&1
check "CLEARED wipes the failure streak" \
  "$(first_line_or "$sd/failure_streak_reset.txt" none)" "$(latest_cycle "$sd")"
check "CLEARED returns the budget" "$(maintenance_attempts "$sd")" 0
check "a CLEARED repair is committed" "$(commits_for CLEARED)" 1
check "CLEARED returns the section to ordinary work" "$(section_next_action "$sd")" scope

sd="$(mk_section notplumbing)"; STUB_VERDICT="NOT_PLUMBING"
do_maintain "$sd" >/dev/null 2>&1
check "NOT_PLUMBING stands the budget down" \
  "$(maintenance_attempts "$sd")" "$(maintenance_budget)"
check "NOT_PLUMBING sends the section to the panel" "$(section_next_action "$sd")" escalate
# The defect this guards: an engineer that fixed a real fault on the way to
# deciding the rest is a product question had its repair left uncommitted in
# the main tree, because only the CLEARED branch committed.
check "a NOT_PLUMBING repair is committed, not abandoned" "$(commits_for NOT_PLUMBING)" 1

rm -rf -- "$TEST_ROOT"
printf '\n'
if (( FAILED == 0 )); then
  printf 'PASS: maintenance routing, attempt accounting, and verdicts\n'
else
  printf 'FAIL: maintenance accounting\n' >&2
  exit 1
fi
