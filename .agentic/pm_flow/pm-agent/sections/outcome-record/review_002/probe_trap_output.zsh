#!/bin/zsh -f
# Cycle 002 review: the rejection condition says a trap firing on the way out
# must not add a line to stdout or alter the exit code. The suite asserts the
# exit codes but never compares the streams, so do that here.
#
# Both copies get the same instrumentation - the fail-aborted tick's captured
# output is echoed verbatim. Only the without_trap copy loses the trap line and
# the three closure assertions, which necessarily fail without it and would
# otherwise stop the suite before the unwritable-store block.
set -uo pipefail
W=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/outcome-record
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/outcome-record-trapout.XXXXXX")"
case "$SANDBOX" in
  */outcome-record-trapout.*) ;;
  *) print -r -- "unsafe sandbox: $SANDBOX" >&2; exit 1 ;;
esac

for case in with_trap without_trap; do
  mkdir -p "$SANDBOX/$case"
  cp -R "$W/template" "$SANDBOX/$case/template"
  cp -R "$W/tests" "$SANDBOX/$case/tests"
  /usr/bin/sed -i '' \
    "245a\\
printf 'FAILEDTICK_BEGIN\\\\n%s\\\\nFAILEDTICK_END\\\\n' \"\$FAILED_TICK_OUTPUT\"
" "$SANDBOX/$case/tests/outcome_record_test.sh"
done

/usr/bin/sed -i '' "/^trap 'telemetry_end_run error' EXIT\$/d" \
  "$SANDBOX/without_trap/template/.agentic/pm_flow/driver.zsh"
# 252-258 shifted by the one inserted line.
/usr/bin/sed -i '' '253,259d' "$SANDBOX/without_trap/tests/outcome_record_test.sh"

for case in with_trap without_trap; do
  zsh "$SANDBOX/$case/tests/outcome_record_test.sh" > "$SANDBOX/$case.out" 2>&1
  print -r -- "${case}_exit=$?"
  /usr/bin/sed -n '/FAILEDTICK_BEGIN/,/FAILEDTICK_END/p' "$SANDBOX/$case.out" \
    > "$SANDBOX/$case.streams"
  /usr/bin/sed -n '/UNWRITABLE RUN EXIT/,/PASS: run and tick dispatch/p' \
    "$SANDBOX/$case.out" >> "$SANDBOX/$case.streams"
done

print -r -- "--- diff without_trap vs with_trap (empty means the trap added nothing) ---"
/usr/bin/diff "$SANDBOX/without_trap.streams" "$SANDBOX/with_trap.streams"
print -r -- "streams_diff_exit=$?"
print -r -- "--- fail-aborted tick, with the trap installed ---"
/usr/bin/sed -n '/FAILEDTICK_BEGIN/,/FAILEDTICK_END/p' "$SANDBOX/with_trap.out"

rm -rf -- "$SANDBOX"
