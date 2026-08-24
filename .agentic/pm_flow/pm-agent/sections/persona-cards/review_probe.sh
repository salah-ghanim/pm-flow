#!/bin/zsh -f
W=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/persona-cards
print "===== fetch.sh probe (independent check of the A2A 0.2.5 AgentSkill fields) ====="
zsh "$W/template/.agentic/pm_flow/fetch.sh" --url "https://a2a-protocol.org/v0.2.5/specification/" \
  --ask "List every field of the AgentSkill object and which are required" 2>&1 | head -n 40
print "EXIT=${pipestatus[1]}"
