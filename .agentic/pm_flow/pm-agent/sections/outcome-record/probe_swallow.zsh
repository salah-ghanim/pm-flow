#!/bin/zsh -f
# PM probe: with the store unwritable, the review tick that now records three
# outcome rows must still reach its verdict, print the same line and exit 0.
# Built from the developer's own suite so the setup is theirs, not mine.
set -uo pipefail
SRC=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/outcome-record
PROBE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/outcome-record-probe.XXXXXX")"
cp -R "$SRC/template" "$PROBE_DIR/template"
cp -R "$SRC/tests" "$PROBE_DIR/tests"
python3 - "$PROBE_DIR/tests/outcome_record_test.sh" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
lines = p.read_text().splitlines(keepends=True)
marker = 'PM_FLOW_STUB="$REVIEW" PM_FLOW_SECTION=review "$FLOWSH" tick >/dev/null\n'
cut = lines.index(marker)
probe = '''
DB_DIR="$FLOW/demo/runs"
chmod 500 "$DB_DIR"
chmod 444 "$DB_DIR/pm_flow.db"
set +e
OUT="$(PM_FLOW_STUB="$REVIEW" PM_FLOW_SECTION=review "$FLOWSH" tick 2>&1)"
RC=$?
set -e
chmod 700 "$DB_DIR"
chmod 644 "$DB_DIR/pm_flow.db"
printf 'unwritable-store tick exit=%s\\n' "$RC"
printf 'unwritable-store tick output:\\n%s\\n' "$OUT"
printf 'decision.txt=%s\\n' "$(/bin/cat "$FLOW/demo/sections/review/cycles/001/decision.txt")"
printf 'obstruction.txt=%s\\n' "$(/bin/cat "$FLOW/demo/sections/review/cycles/001/obstruction.txt")"
[[ "$RC" == 0 ]] || fail "the unwritable store changed the tick exit status"
printf 'PROBE PASS: the dispatch still reached its verdict and exited 0\\n'
'''
p.write_text(''.join(lines[:cut]) + probe)
PY
zsh "$PROBE_DIR/tests/outcome_record_test.sh"
print "PROBE SCRIPT EXIT=$?"
rm -rf "$PROBE_DIR"
