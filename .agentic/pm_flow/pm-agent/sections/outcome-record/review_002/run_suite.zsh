#!/bin/zsh
# Cycle 002 review: run the section suite in the developer's worktree and
# report its exit status explicitly, since A3/A4 both hinge on exit 0.
W=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/outcome-record
zsh "$W/tests/outcome_record_test.sh"
print -r -- "SUITE_EXIT=$?"
