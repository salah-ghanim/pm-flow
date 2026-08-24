#!/bin/zsh -f
set -euo pipefail
S=/Users/salah/code/personal/pm-flow/.agentic/pm_flow/pm-agent/sections
for k in a2a-binding otel-semconv persona-cards repo-hooks packaging; do
  print -- "=== $k coverage table rows ==="
  grep -n -E '^\|' $S/$k/workplan.md | head -30
done
