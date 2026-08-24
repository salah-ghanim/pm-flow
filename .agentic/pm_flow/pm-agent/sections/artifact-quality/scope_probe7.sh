#!/bin/zsh -f
set -euo pipefail
S=/Users/salah/code/personal/pm-flow/.agentic/pm_flow/pm-agent/sections
P=/Users/salah/code/personal/pm-flow/.agentic/pm_flow/pm-agent/project_state
print -r -- "=== heading depths (missing-heading files) ==="
for f in "$S/agents-md/brief.md" "$S/agents-md/state.md" "$S/green-suite/brief.md" \
         "$S/green-suite/state.md" "$S/installer/brief.md" "$S/installer/state.md" \
         "$S/run-detach/brief.md" "$S/worktree-isolation/brief.md" \
         "$S/worktree-isolation/state.md" "$P/plan.md"; do
  d2=$(grep -cE '^## ' "$f" || true)
  d3=$(grep -cE '^### ' "$f" || true)
  print -r -- "$(basename $(dirname $f))/$(basename $f): '## '=$d2 '### '=$d3"
  grep -nE '^#{1,6} ' "$f" | head -9 | sed 's/^/    /'
done
print -r -- "=== coverage table rows ==="
for f in "$S/packaging/workplan.md" "$S/a2a-binding/workplan.md" "$S/otel-semconv/workplan.md" \
         "$S/persona-cards/workplan.md" "$S/repo-hooks/workplan.md"; do
  print -r -- "--- $(basename $(dirname $f)) ---"
  grep -nE '^\|' "$f" | tail -12 | sed 's/^/    /'
done
