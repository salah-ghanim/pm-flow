#!/bin/zsh -f
set -euo pipefail
S=/Users/salah/code/personal/pm-flow/.agentic/pm_flow/pm-agent/sections
P=/Users/salah/code/personal/pm-flow/.agentic/pm_flow/pm-agent/project_state
print -- "=== heading depths per file reported as missing headings ==="
for f in \
  $S/packaging/brief.md $S/agents-md/brief.md $S/agents-md/state.md \
  $S/green-suite/brief.md $S/green-suite/state.md \
  $S/installer/brief.md $S/installer/state.md \
  $S/run-detach/brief.md $S/worktree-isolation/brief.md $S/worktree-isolation/state.md \
  $P/plan.md
do
  print -- "--- $f"
  grep -c -E '^##[^#]' $f || true
  grep -n -E '^#{1,6} ' $f | head -20
done
