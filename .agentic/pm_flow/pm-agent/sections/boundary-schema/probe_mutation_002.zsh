#!/bin/zsh -f
# PM review probe, cycle 002. Independent mutation checks on the shell column
# and on the checker column of tests/boundary_schema_test.sh.
set -uo pipefail

SRC=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/boundary-schema
BASE="$(mktemp -d "${TMPDIR:-/tmp}/pm-review-002.XXXXXX")"
print "base=$BASE"

# ---- Mutation A: stub the shell handoff validator to accept everything ----
A="$BASE/mutation-shell-handoff"
mkdir -p "$A"
cp -R "$SRC/template" "$A/template"
cp -R "$SRC/tests" "$A/tests"
python3 - "$A/template/.agentic/pm_flow/pm_flow.sh" <<'PY'
import re, sys
from pathlib import Path
p = Path(sys.argv[1])
text = p.read_text()
new, n = re.subn(
    r"^validate_handoff\(\) \{\n.*?^\}\n",
    "validate_handoff() {\n  return 0\n}\n",
    text, count=1, flags=re.S | re.M)
if n != 1:
    raise SystemExit("could not stub validate_handoff")
p.write_text(new)
print("stubbed validate_handoff to accept")
PY
print "--- mutation A: suite output ---"
zsh "$A/tests/boundary_schema_test.sh"
print "mutation_A_exit=$?"

# ---- Mutation B: loosen the schema so the checker accepts a bad brief ----
B="$BASE/mutation-schema-loosened"
mkdir -p "$B"
cp -R "$SRC/template" "$B/template"
cp -R "$SRC/tests" "$B/tests"
python3 - "$B/template/.agentic/pm_flow/schemas/section_brief.schema.json" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
schema = json.loads(p.read_text())
schema["required"] = [f for f in schema["required"] if f != "priority_loss"]
schema["properties"]["priority_loss"].pop("pattern", None)
p.write_text(json.dumps(schema, indent=2) + "\n")
print("removed the priority_loss requirement from the schema")
PY
print "--- mutation B: suite output ---"
zsh "$B/tests/boundary_schema_test.sh"
print "mutation_B_exit=$?"

print "base_kept=$BASE"
