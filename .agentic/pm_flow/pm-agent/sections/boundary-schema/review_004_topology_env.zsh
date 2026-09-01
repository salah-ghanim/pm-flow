#!/bin/zsh
# PM review, cycle 004: does the dispatch's PM_FLOW_* env explain the
# persona_card failure the developer reported?
set -u
WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/boundary-schema
OUT=/tmp/pm-review-004/topo-env
rm -rf "$OUT"
mkdir -p "$OUT"

print "=== does the suite scrub PM_FLOW_* itself? ==="
grep -n 'PM_FLOW_' "$WT/tests/topology_compare_test.sh" | head -20
print "(end of grep)"

print
print "=== run with the dispatch env still set (as the developer's shell had it) ==="
export PM_FLOW_ENGINE_ROOT=/Users/salah/code/personal/pm-flow/template/.agentic/pm_flow
export PM_FLOW_FLOW_DIR=/Users/salah/code/personal/pm-flow/.agentic/pm_flow
export PM_FLOW_REPO_ROOT=/Users/salah/code/personal/pm-flow
export PM_FLOW_ROOT=/Users/salah/code/personal/pm-flow/template/.agentic/pm_flow
export PM_FLOW_PROJECT=pm-agent
export PM_FLOW_PROJECT_DIR=/Users/salah/code/personal/pm-flow/.agentic/pm_flow/pm-agent
export PM_FLOW_STATE_DIR=/Users/salah/code/personal/pm-flow/.agentic/pm_flow/pm-agent/project_state
export PM_FLOW_SECTIONS_DIR=/Users/salah/code/personal/pm-flow/.agentic/pm_flow/pm-agent/sections
export PM_FLOW_RUNS_DIR=/Users/salah/code/personal/pm-flow/.agentic/pm_flow/pm-agent/runs
export PM_FLOW_STORE=/Users/salah/code/personal/pm-flow/.agentic/pm_flow/pm-agent/runs/pm_flow.db
export PM_FLOW_DIR_NAME=.agentic

cd "$WT" && zsh tests/topology_compare_test.sh > "$OUT/env.out" 2> "$OUT/env.err"
print "exit=$?"
print "stdout:"
cat "$OUT/env.out"
print "stderr:"
cat "$OUT/env.err"
