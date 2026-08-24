#!/bin/zsh
# Review 002: agent-bindings A5 reads `pm-flow cost`, which store-ledger rewrites.
set -u
exec /Users/salah/code/personal/pm-flow/.venv/bin/pm-flow --project pm-agent \
  section-dependencies agent-bindings \
  --file /Users/salah/code/personal/pm-flow/.agentic/pm_flow/pm-agent/project_state/portfolio/002/agent-bindings-dependencies.md
