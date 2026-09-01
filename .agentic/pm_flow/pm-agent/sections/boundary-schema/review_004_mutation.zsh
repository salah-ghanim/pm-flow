#!/bin/zsh
# PM review, cycle 004: suite green on a disposable copy, then the
# handoff.schema.json title mutation must turn it red.
set -u
WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/boundary-schema
COPY=/tmp/pm-review-004/mutcopy
rm -rf "$COPY"
mkdir -p "$COPY"
cp -R "$WT/template" "$COPY/template"
cp -R "$WT/tests" "$COPY/tests"

print "=== baseline on the disposable copy ==="
zsh "$COPY/tests/boundary_schema_test.sh"
print "baseline-exit=$?"

print
print "=== mutate handoff.schema.json: unproven.title ==="
python3 - "$COPY/template/.agentic/pm_flow/schemas/handoff.schema.json" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
s = json.loads(p.read_text())
before = s["properties"]["unproven"]["title"]
s["properties"]["unproven"]["title"] = "Loose ends"
p.write_text(json.dumps(s, indent=2) + "\n")
print("title %r -> %r" % (before, "Loose ends"))
PY

print
print "=== re-run the suite on the mutated copy ==="
zsh "$COPY/tests/boundary_schema_test.sh"
print "mutated-exit=$?"
