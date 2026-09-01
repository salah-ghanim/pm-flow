#!/usr/bin/env zsh
# Cycle 003 review: negative/mutation checks against a disposable copy of the
# developer's tree. Never edits the worktree itself.
set -u
WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/boundary-schema
OUT=/Users/salah/code/personal/pm-flow/.agentic/pm_flow/pm-agent/sections/boundary-schema/review_003
mkdir -p "$OUT"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/bs-review-003.XXXXXX")"
REPO="$WORK/repo"
mkdir -p "$REPO/template/.agentic" "$REPO/tests"
cp -R "$WT/template/.agentic/pm_flow" "$REPO/template/.agentic/pm_flow"
cp -R "$WT/tests/fixtures" "$REPO/tests/fixtures"
cp "$WT/tests/boundary_schema_test.sh" "$REPO/tests/boundary_schema_test.sh"
SCHEMA="$REPO/template/.agentic/pm_flow/schemas/config.schema.json"
AGENT="$REPO/template/.agentic/pm_flow/agent_exec.sh"
PMSH="$REPO/template/.agentic/pm_flow/pm_flow.sh"
TOPO="$REPO/template/.agentic/pm_flow/topology.py"
cp "$SCHEMA" "$WORK/schema.orig"
cp "$AGENT" "$WORK/agent.orig"
cp "$PMSH" "$WORK/pmsh.orig"
cp "$TOPO" "$WORK/topo.orig"

run_suite() {
  local label="$1"
  zsh "$REPO/tests/boundary_schema_test.sh" > "$OUT/$label.out" 2>&1
  print -r -- "=== $label: suite exit=$?"
  tail -n 4 "$OUT/$label.out"
}

print -r -- "work=$WORK"

# Baseline on the copy, to prove the copy itself is green.
run_suite mutation_baseline

# M1 - the schema enum is the single definition: drop acp from it.
python3 - "$SCHEMA" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1]); d = json.loads(p.read_text())
e = d["$defs"]["seat"]["properties"]["cli"]["enum"]
e.remove("acp")
p.write_text(json.dumps(d, indent=2) + "\n")
PY
run_suite mutation_m1_schema_drops_acp
cp "$WORK/schema.orig" "$SCHEMA"

# M2 - agent_exec.sh stops reading the schema.
python3 - "$AGENT" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1]); s = p.read_text()
s = s.replace('if cli not in cli_enum:',
              'if cli not in {"claude", "codex", "copilot"}:', 1)
p.write_text(s)
PY
run_suite mutation_m2_agent_exec_literal
cp "$WORK/agent.orig" "$AGENT"

# M3 - pm_flow.sh stops reading the schema.
python3 - "$PMSH" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1]); s = p.read_text()
s = s.replace('        if cli not in cli_enum:',
              '        if cli not in {"claude", "codex", "copilot"}:', 1)
p.write_text(s)
PY
run_suite mutation_m3_pm_flow_literal
cp "$WORK/pmsh.orig" "$PMSH"

# M4 - topology.py goes back to deciding legality from the model registry.
python3 - "$TOPO" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1]); s = p.read_text()
s = s.replace('        if cli not in cli_enum:',
              '        if cli not in registry:', 1)
p.write_text(s)
PY
run_suite mutation_m4_topology_registry
cp "$WORK/topo.orig" "$TOPO"

# M5 - unresolvable pointer must be named, not silently accepted.
python3 - "$SCHEMA" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1]); d = json.loads(p.read_text())
d["properties"]["roles"]["additionalProperties"]["oneOf"][0] = {"$ref": "#/$defs/nosuch"}
p.write_text(json.dumps(d, indent=2) + "\n")
PY
python3 "$REPO/template/.agentic/pm_flow/export.py" check --kind config \
  "$REPO/tests/fixtures/boundary_schema/config_valid.json" \
  > "$OUT/mutation_m5_bad_ref.out" 2>&1
print -r -- "=== m5 unresolvable \$ref: export.py exit=$?"
cat "$OUT/mutation_m5_bad_ref.out"
cp "$WORK/schema.orig" "$SCHEMA"

print -r -- "work kept at $WORK"
