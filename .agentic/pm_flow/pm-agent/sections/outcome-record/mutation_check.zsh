#!/bin/zsh -f
# PM negative check: the suite must fail if the attempt handle is not attached.
# Runs against a throwaway copy of the developer's tree; the tree under review
# is never modified.
set -uo pipefail
SRC=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/outcome-record
MUT="$(mktemp -d "${TMPDIR:-/tmp}/outcome-record-mutation.XXXXXX")"
mkdir -p "$MUT"
cp -R "$SRC/template" "$MUT/template"
cp -R "$SRC/tests" "$MUT/tests"
python3 - "$MUT/template/.agentic/pm_flow/driver.zsh" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
s = p.read_text()
needle = '    args+=(--attempt "$TELEMETRY_LAST_ATTEMPT_ID")\n'
assert s.count(needle) == 1, s.count(needle)
p.write_text(s.replace(needle, '    : mutated-away\n'))
print("mutation applied: the --attempt argument is removed")
PY
zsh "$MUT/tests/outcome_record_test.sh"
print "MUTATED SUITE EXIT=$?"
rm -rf "$MUT"
