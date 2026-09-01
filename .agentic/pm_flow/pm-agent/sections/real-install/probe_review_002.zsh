#!/bin/zsh
# PM review probe: run the assigned validation commands against the developer worktree.
WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/real-install
OUT=/Users/salah/code/personal/pm-flow/.agentic/pm_flow/pm-agent/sections/real-install/review_002
mkdir -p "$OUT"

print "=== real_install_test.sh ==="
zsh "$WT/tests/real_install_test.sh" > "$OUT/real_install.out" 2>&1
print "EXIT=$?"
tail -n 40 "$OUT/real_install.out"

print "=== packaged_layout_test.sh ==="
zsh "$WT/tests/packaged_layout_test.sh" > "$OUT/packaged_layout.out" 2>&1
print "EXIT=$?"
grep -c '^PASS: ' "$OUT/packaged_layout.out"
grep '^PASS: ' "$OUT/packaged_layout.out"
