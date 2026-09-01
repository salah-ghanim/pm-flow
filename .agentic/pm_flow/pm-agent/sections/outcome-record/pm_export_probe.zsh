#!/bin/zsh -f
# PM review probe M4 for outcome-record cycle 003.
# The store-side comparison fires before the export-side one, so M1/M2 do not
# show the exported-JSON assertion is load-bearing. Break only the exporter.
set -uo pipefail

SRC=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/outcome-record
BASE="$(mktemp -d "${TMPDIR:-/tmp}/pm-review-003-m4.XXXXXX")"
printf 'PROBE BASE: %s\n' "$BASE"

mkdir -p "$BASE/m4/template/.agentic" "$BASE/m4/src" "$BASE/m4/tests/fixtures"
cp -R "$SRC/template/.agentic/pm_flow" "$BASE/m4/template/.agentic/pm_flow"
cp -R "$SRC/src/pm_flow" "$BASE/m4/src/pm_flow"
cp -R "$SRC/tests/fixtures/outcome_record" "$BASE/m4/tests/fixtures/outcome_record"
cp "$SRC/tests/outcome_record_test.sh" "$BASE/m4/tests/outcome_record_test.sh"

python3 - "$BASE/m4/template/.agentic/pm_flow/trace_export.py" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
old = '        events = events_by_span.get(row["span_id"]) or []\n'
new = '        events = []\n'
assert text.count(old) == 1, "mutation anchor M4 not unique"
open(path, "w", encoding="utf-8").write(text.replace(old, new))
print("M4 applied: the exporter drops every span event, the store keeps them")
PY

printf '\n===== M4 (store correct, export drops the events) =====\n'
zsh "$BASE/m4/tests/outcome_record_test.sh" > "$BASE/m4.log" 2>&1
printf 'M4 EXIT: %s\n' "$?"
tail -n 5 "$BASE/m4.log"

rm -rf "$BASE/m4"
printf '\nprobe tree removed; log kept under %s\n' "$BASE"
