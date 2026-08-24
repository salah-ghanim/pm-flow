#!/bin/zsh -f
set -euo pipefail
REPO=/Users/salah/code/personal/pm-flow
for name in ${(k)parameters}; do
  case $name in PM_FLOW_*) unset $name;; esac
done
export PYTHONPATH="$REPO/src"
OUT=$(python3 -m pm_flow.quality rank)
lines=("${(@f)OUT}")
print -- "scored files: ${#lines}"
for dim in boundaries shape length echo stale; do
  hits=("${(@M)lines:#*${dim}:*}")
  print -- "$dim findings: ${#hits}"
done
clean=("${(@M)lines:#*findings: none*}")
print -- "clean files: ${#clean}"
