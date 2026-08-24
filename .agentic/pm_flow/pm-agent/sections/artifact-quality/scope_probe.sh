#!/bin/zsh -f
set -euo pipefail
REPO=/Users/salah/code/personal/pm-flow
for name in ${(k)parameters}; do
  case $name in PM_FLOW_*) unset $name;; esac
done
export PYTHONPATH="$REPO/src"
print -- "=== rank against live pm-agent ==="
python3 -m pm_flow.quality rank || true
