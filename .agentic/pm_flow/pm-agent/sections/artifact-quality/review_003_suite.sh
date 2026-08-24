#!/bin/zsh
set -u
WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/artifact-quality
zsh "$WT/tests/artifact_quality_test.sh"
print "SUITE_EXIT=$?"
