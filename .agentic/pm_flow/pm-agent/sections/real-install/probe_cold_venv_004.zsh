#!/bin/zsh
# PM review probe, cycle 004: status_phase digests the whole repo including
# .venv. Does a cold (uncompiled) venv put bytecode writes over the budget?
set -uo pipefail
ROOT=/var/folders/9x/9xzxgmhn75q66kr2x3n691hw0000gn/T/pm-review-004.ZaBVuv
WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/real-install

rm -f "$ROOT/fixture/stray-write.txt"
print -r -- "pycache_dirs_before=$(find "$ROOT/fixture/.venv" -type d -name __pycache__ | grep -c .)"
find "$ROOT/fixture/.venv" -type d -name __pycache__ -exec rm -rf {} +
print -r -- "pycache_dirs_after_purge=$(find "$ROOT/fixture/.venv" -type d -name __pycache__ | grep -c .)"

"$ROOT/runbook.zsh" status \
  --repo "$ROOT/fixture" \
  --project-key beta \
  --install-sh "$WT/install.sh" \
  --out "$ROOT/out" > "$ROOT/status-cold.log" 2>&1
print -r -- "cold_status_exit=$?"
grep -c 'status_wrote=' "$ROOT/status-cold.log"
grep -n 'status_in_place=ok\|ERROR' "$ROOT/status-cold.log"
grep -m 5 -n 'status_wrote=' "$ROOT/status-cold.log"
