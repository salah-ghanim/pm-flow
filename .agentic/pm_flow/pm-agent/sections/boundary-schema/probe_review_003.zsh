#!/usr/bin/env zsh
# Cycle 003 review probe: exit codes for the A5 suites, run from the worktree.
set -u
WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/boundary-schema
OUT=/Users/salah/code/personal/pm-flow/.agentic/pm_flow/pm-agent/sections/boundary-schema/review_003
mkdir -p "$OUT"
cd "$WT" || exit 9

for suite in tests/boundary_schema_test.sh tests/topology_compare_test.sh \
             tests/agent_bindings_test.sh tests/pm_flow_test.sh \
             template/.agentic/pm_flow/tests/verdict_parser.zsh; do
  name="${suite:t:r}"
  zsh "$WT/$suite" > "$OUT/$name.out" 2>&1
  print -r -- "$suite exit=$? cwd=$WT"
done
