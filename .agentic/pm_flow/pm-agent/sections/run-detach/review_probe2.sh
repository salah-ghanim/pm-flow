#!/bin/zsh -f
W=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/run-detach
zsh "$W/tests/pm_flow_test.sh"
print "PM_FLOW_EXIT=$?"
