#!/bin/zsh -f
# Corrected: delete only the three closure assertions (252-253, 256, 257-258),
# not the SELECT assignments between them, so the without_trap leg reaches the
# unwritable-store block and its dispatch streams can be compared byte for byte
# against the same block with the trap installed.
set -uo pipefail
W=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/outcome-record
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/outcome-record-trapout2.XXXXXX")"
case "$SANDBOX" in
  */outcome-record-trapout2.*) ;;
  *) print -r -- "unsafe sandbox: $SANDBOX" >&2; exit 1 ;;
esac
for case in with_trap without_trap; do
  mkdir -p "$SANDBOX/$case"
  cp -R "$W/template" "$SANDBOX/$case/template"
  cp -R "$W/tests" "$SANDBOX/$case/tests"
done
/usr/bin/sed -i '' "/^trap 'telemetry_end_run error' EXIT\$/d" \
  "$SANDBOX/without_trap/template/.agentic/pm_flow/driver.zsh"
/usr/bin/sed -i '' -e '257,258d' -e '256d' -e '252,253d' \
  "$SANDBOX/without_trap/tests/outcome_record_test.sh"

for case in with_trap without_trap; do
  zsh "$SANDBOX/$case/tests/outcome_record_test.sh" > "$SANDBOX/$case.out" 2>&1
  print -r -- "${case}_exit=$?"
  /usr/bin/sed -n '/UNWRITABLE RUN EXIT/,/PASS: run and tick dispatch/p' \
    "$SANDBOX/$case.out" > "$SANDBOX/$case.streams"
done
print -r -- "--- diff without_trap vs with_trap, unwritable-store block ---"
/usr/bin/diff "$SANDBOX/without_trap.streams" "$SANDBOX/with_trap.streams"
print -r -- "streams_diff_exit=$?"
/usr/bin/wc -l "$SANDBOX/with_trap.streams"
rm -rf -- "$SANDBOX"
