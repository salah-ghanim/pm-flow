#!/bin/zsh
# Cycle 002 review: the engine regression runner, in the developer's worktree.
# An EXIT trap installed at driver source scope is exactly the change that can
# silently alter dispatch output or an exit status these five suites assert on.
W=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/outcome-record
zsh "$W/template/.agentic/pm_flow/tests/run.zsh"
print -r -- "ENGINE_EXIT=$?"
