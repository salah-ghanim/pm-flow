#!/bin/zsh
# PM review, cycle 004: would the suite notice if the promised emit behaviour
# were absent? Three reversible mutations of export.py on a disposable copy.
set -u
WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/boundary-schema
BASE=/tmp/pm-review-004/neg
rm -rf "$BASE"

mutate() {
  local label="$1" mutation="$2"
  local copy="$BASE/$label"
  mkdir -p "$copy"
  cp -R "$WT/template" "$copy/template"
  cp -R "$WT/tests" "$copy/tests"
  python3 - "$copy/template/.agentic/pm_flow/export.py" "$mutation" <<'PY'
import sys
from pathlib import Path
p, kind = Path(sys.argv[1]), sys.argv[2]
text = p.read_text()
if kind == "heading-keyed":
    old = '''    evidence = "\\n".join(
        body
        for heading, body in sections.items()
        if heading not in {"blockers", "next eligible task"}
    )'''
    new = '''    evidence = sections.get("completed tasks and evidence", "")'''
elif kind == "no-exclusion":
    old = '''        if heading not in {"blockers", "next eligible task"}
    )'''
    new = '''    )'''
elif kind == "blank-deps":
    old = '''        for line in _read_text(path, section_key, field).splitlines()
        if line.strip()
    ]'''
    new = '''        for line in _read_text(path, section_key, field).splitlines()
    ]'''
assert old in text, "mutation anchor not found: " + kind
p.write_text(text.replace(old, new, 1))
print("mutated:", kind)
PY
  print "--- $label ---"
  zsh "$copy/tests/boundary_schema_test.sh" > "$BASE/$label.out" 2> "$BASE/$label.err"
  print "exit=$?"
  grep -E 'FAIL|project export|Traceback|Error' "$BASE/$label.out" "$BASE/$label.err" | head -8
  print
}

mutate heading-keyed heading-keyed
mutate no-exclusion no-exclusion
mutate blank-deps blank-deps
