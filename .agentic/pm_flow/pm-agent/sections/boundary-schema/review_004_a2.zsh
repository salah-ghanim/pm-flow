#!/bin/zsh
# PM review, cycle 004, A2: the three refusal paths, with their real messages.
set -u
WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/boundary-schema
LIVE=/Users/salah/code/personal/pm-flow
OUT=/tmp/pm-review-004/a2
rm -rf "$OUT"
mkdir -p "$OUT"

for name in ${(k)parameters[(I)PM_FLOW_*]}; do
  unset "$name"
done

print "=== 1. corrupt handoff, on a copy of the LIVE project ==="
cp -R "$WT/template/.agentic/pm_flow" "$OUT/engine"
mkdir -p "$OUT/engine/pm-agent"
cp -R "$LIVE/.agentic/pm_flow/pm-agent/sections" "$OUT/engine/pm-agent/sections"
cp -R "$WT/tests/fixtures/boundary_schema/project_export_invalid/." \
   "$OUT/engine/pm-agent/sections/"
print "corrupt section injected: $(ls -d $OUT/engine/pm-agent/sections/corrupt-handoff)"
grep -c '^## ' "$OUT/engine/pm-agent/sections/corrupt-handoff/handoff.md"
grep '^## ' "$OUT/engine/pm-agent/sections/corrupt-handoff/handoff.md"
python3 "$OUT/engine/export.py" emit --json "$OUT/engine" pm-agent \
  > "$OUT/corrupt.out" 2> "$OUT/corrupt.err"
print "exit=$?"
print "stdout bytes=$(wc -c < $OUT/corrupt.out)"
print "stderr:"
cat "$OUT/corrupt.err"

print
print "=== 2. check --kind export on an illegal acceptance state ==="
cat "$WT/tests/fixtures/boundary_schema/project_export_illegal_state.json"
python3 "$WT/template/.agentic/pm_flow/export.py" check --kind export \
  "$WT/tests/fixtures/boundary_schema/project_export_illegal_state.json" \
  > "$OUT/state.out" 2> "$OUT/state.err"
print "exit=$?"
print "stdout: $(cat $OUT/state.out)"
print "stderr: $(cat $OUT/state.err)"

print
print "=== 3. project_export.schema.json deleted from an engine copy ==="
cp -R "$OUT/engine" "$OUT/engine-noschema"
rm -rf "$OUT/engine-noschema/pm-agent/sections/corrupt-handoff"
rm -- "$OUT/engine-noschema/schemas/project_export.schema.json"
python3 "$OUT/engine-noschema/export.py" emit --json "$OUT/engine-noschema" pm-agent \
  > "$OUT/noschema.out" 2> "$OUT/noschema.err"
print "exit=$?"
print "stdout bytes=$(wc -c < $OUT/noschema.out)"
print "stderr:"
cat "$OUT/noschema.err"

print
print "=== 4. grep: are the six handoff names or the ID pattern written twice? ==="
grep -rn 'What is unproven\|Next action\|"Outcome"\|"Decisions"\|"Interfaces"\|"Risks"' \
  "$WT/template/.agentic/pm_flow/schemas/project_export.schema.json" \
  "$WT/template/.agentic/pm_flow/export.py" || print "(no occurrence in either file)"
print "--- A-id regex literals in export.py ---"
grep -n 'A\[0-9\]' "$WT/template/.agentic/pm_flow/export.py" || print "(none in export.py)"
grep -rn 'A\[0-9\]' "$WT/template/.agentic/pm_flow/schemas/" || print "(none in schemas beyond the brief)"
