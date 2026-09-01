#!/bin/zsh -f
# Cycle 002 review: two smallest-possible mutations on a throwaway copy of the
# developer's worktree, to show the A3 assertions are load-bearing.
#
#   M1 - delete the owner-process EXIT trap. If the fail-aborted tick still
#        closes, something other than the trap is closing it and the claim is
#        wrong.
#   M2 - drop --only-open from telemetry_end_run. If the completed run still
#        reads `ok`, the guard against the trap clobbering a terminal status is
#        not doing anything.
#
# Nothing here touches the worktree or the repository; both mutations live in a
# mktemp copy that is removed on the way out.
set -uo pipefail
W=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/outcome-record
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/outcome-record-mutation.XXXXXX")"
case "$SANDBOX" in
  */outcome-record-mutation.*) ;;
  *) print -r -- "unsafe sandbox: $SANDBOX" >&2; exit 1 ;;
esac

run_case() {
  local label="$1" root="$SANDBOX/$1"
  mkdir -p "$root"
  cp -R "$W/template" "$root/template"
  cp -R "$W/tests" "$root/tests"
  print -r -- "--- $label ---"
}

run_case baseline
run_case m1_no_trap
/usr/bin/sed -i '' "/^trap 'telemetry_end_run error' EXIT\$/d" \
  "$SANDBOX/m1_no_trap/template/.agentic/pm_flow/driver.zsh"
print -r -- "trap lines left in m1: $(/usr/bin/grep -c "trap 'telemetry_end_run error' EXIT" "$SANDBOX/m1_no_trap/template/.agentic/pm_flow/driver.zsh")"

run_case m2_no_only_open
/usr/bin/sed -i '' 's/--status "\$run_status" --only-open/--status "$run_status"/' \
  "$SANDBOX/m2_no_only_open/template/.agentic/pm_flow/driver.zsh"
print -r -- "only-open flags left in m2: $(/usr/bin/grep -c -- '--only-open' "$SANDBOX/m2_no_only_open/template/.agentic/pm_flow/driver.zsh")"

for case in baseline m1_no_trap m2_no_only_open; do
  print -r -- "===== $case ====="
  zsh "$SANDBOX/$case/tests/outcome_record_test.sh" 2>&1 | /usr/bin/grep -E 'FAIL|PASS: completed run|^run\||^tick\|'
  print -r -- "${case}_exit=${pipestatus[1]}"
done

rm -rf -- "$SANDBOX"
