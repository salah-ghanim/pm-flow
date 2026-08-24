#!/bin/zsh -f
W=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/run-detach
zsh "$W/tests/packaged_layout_test.sh"
print "PACKAGED_EXIT=$?"
