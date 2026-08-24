#!/bin/zsh -f
set -euo pipefail
unset PM_FLOW_PROJECT PM_FLOW_ENGINE_ROOT PM_FLOW_REPO_ROOT PM_FLOW_SECTION PM_FLOW_CYCLE PYTHONPATH
REPO=/Users/salah/code/personal/pm-flow
cd "$REPO"
PYTHONPATH="$REPO/src" python3 -m pm_flow.quality rank >/tmp/aq_rank.txt 2>/tmp/aq_rank.err || {
  print -r -- "rank failed"; cat /tmp/aq_rank.err; exit 1
}
print -r -- "scored files: $(wc -l </tmp/aq_rank.txt | tr -d ' ')"
print -r -- "boundaries findings: $(grep -c 'boundaries:' /tmp/aq_rank.txt || true)"
print -r -- "shape findings: $(grep -c 'shape:' /tmp/aq_rank.txt || true)"
print -r -- "--- shape lines ---"
grep 'shape:' /tmp/aq_rank.txt | cut -c1-220
print -r -- "--- worst 5 ---"
head -5 /tmp/aq_rank.txt | cut -c1-300
