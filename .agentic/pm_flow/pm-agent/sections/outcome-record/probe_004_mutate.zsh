#!/bin/zsh
# Mutation M3: strip span events from the OTLP wire payload only.
# The store, the span_events table and the --file export are untouched;
# only what the backend receives loses its events. If the Jaeger assertion
# is load-bearing, the suite must fail there and nowhere earlier.
set -u
WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/outcome-record
MUT="$(mktemp -d "${TMPDIR:-/tmp}/outcome-record-mutation.XXXXXX")"
OUT=/Users/salah/code/personal/pm-flow/.agentic/pm_flow/pm-agent/sections/outcome-record/probe_004

print "MUTATION_TREE=$MUT"
mkdir -p "$MUT"
/usr/bin/rsync -a --exclude '.git' "$WT/" "$MUT/"

TE="$MUT/template/.agentic/pm_flow/trace_export.py"
/usr/bin/sed -i '' \
  's|^            to_otlp_json(rows, events_by_span, resource_attributes)$|            to_otlp_json(rows, {}, resource_attributes)  # MUTATION M3|' \
  "$TE"

print '--- mutated line ---'
/usr/bin/grep -n 'MUTATION M3' "$TE"

print '--- suite under mutation ---'
zsh "$MUT/tests/outcome_record_test.sh" > "$OUT/mutation_m3.log" 2>&1
print "MUTATION_EXIT=$?"
/usr/bin/grep -nE '^(PASS|FAIL|SKIP)' "$OUT/mutation_m3.log"

/bin/rm -rf -- "$MUT"
