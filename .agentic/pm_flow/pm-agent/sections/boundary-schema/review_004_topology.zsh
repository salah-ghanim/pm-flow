#!/bin/zsh
# PM review, cycle 004, A5: is topology_compare_test.sh's failure the
# documented main baseline, or the developer's?
set -u
WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/boundary-schema
LIVE=/Users/salah/code/personal/pm-flow
OUT=/tmp/pm-review-004/topo
rm -rf "$OUT"
mkdir -p "$OUT/main"

for name in ${(k)parameters[(I)PM_FLOW_*]}; do
  unset "$name"
done

print "=== pristine copy of main ==="
git -C "$LIVE" archive main | tar -x -C "$OUT/main"
git -C "$LIVE" rev-parse main

print
print "=== main: zsh tests/topology_compare_test.sh ==="
cd "$OUT/main" && zsh tests/topology_compare_test.sh > "$OUT/main.out" 2> "$OUT/main.err"
print "main-exit=$?"
print "--- stdout ---"
cat "$OUT/main.out"
print "--- stderr ---"
cat "$OUT/main.err"

print
print "=== developer checkout: zsh tests/topology_compare_test.sh ==="
cd "$WT" && zsh tests/topology_compare_test.sh > "$OUT/wt.out" 2> "$OUT/wt.err"
print "wt-exit=$?"
print "--- stdout ---"
cat "$OUT/wt.out"
print "--- stderr ---"
cat "$OUT/wt.err"

print
print "=== diff of the two runs ==="
diff "$OUT/main.out" "$OUT/wt.out" && print "(stdout identical)"
diff "$OUT/main.err" "$OUT/wt.err" && print "(stderr identical)"
