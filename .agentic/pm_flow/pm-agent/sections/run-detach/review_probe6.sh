#!/bin/zsh -f
W=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/run-detach
start=$SECONDS
zsh "$W/tests/run_detach_test.sh"
code=$?
print -r -- "RUN_DETACH_EXIT=$code"
print -r -- "ELAPSED_SECONDS=$(( SECONDS - start ))"
