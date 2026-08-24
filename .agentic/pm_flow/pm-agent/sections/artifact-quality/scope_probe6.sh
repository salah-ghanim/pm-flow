#!/bin/zsh -f
set -euo pipefail
print -r -- "=== shape findings, classified ==="
grep -o '[^ ]*\.md | .*' /tmp/aq_rank.txt >/dev/null 2>&1 || true
grep 'shape:' /tmp/aq_rank.txt | while read -r line; do
  file="${line%% |*}"
  seg="${line#*shape: }"
  seg="${seg%% | *}"
  print -r -- "$file :: ${seg:0:120}"
done
