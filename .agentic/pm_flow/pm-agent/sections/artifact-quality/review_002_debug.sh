#!/bin/zsh -f
set -uo pipefail

WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/artifact-quality
for name in ${(k)parameters[(I)PM_FLOW_*]}; do unset "$name"; done
unset PYTHONPATH

cd -P -- "$WT"
print -r -- "pwd=$PWD"
PYTHONPATH="$WT/src" python3 -c 'from pm_flow.paths import Paths; p=Paths(); print("repo_root",p.repo_root); print("project_key",p.project_key); print("flow_dir",p.flow_dir); print("state_dir",p.state_dir); print("sections_dir",p.sections_dir, p.sections_dir.is_dir())'
print -r -- "exit=$?"
PYTHONPATH="$WT/src" python3 -m pm_flow.quality rank
print -r -- "rank exit=$?"
