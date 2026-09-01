#!/bin/zsh
# PM review, cycle 004: does export write ANYTHING, including files git ignores?
# Full recursive checksum of a copied flow directory, before and after.
set -u
WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/boundary-schema
LIVE=/Users/salah/code/personal/pm-flow
OUT=/tmp/pm-review-004/nowrite
rm -rf "$OUT"
mkdir -p "$OUT/work/.agentic"

for name in ${(k)parameters[(I)PM_FLOW_*]}; do
  unset "$name"
done

cp -R "$LIVE/.agentic/pm_flow" "$OUT/work/.agentic/pm_flow"
cp -R "$WT/template/.agentic/pm_flow/." "$OUT/engine"

snapshot() {
  find "$OUT/work" -type f -exec shasum {} \; | sed "s|$OUT/work||" | sort
}

snapshot > "$OUT/before.txt"
print "files tracked in the snapshot: $(wc -l < $OUT/before.txt)"

export PM_FLOW_ENGINE_ROOT="$OUT/engine"
export PM_FLOW_FLOW_DIR="$OUT/work/.agentic/pm_flow"
export PM_FLOW_REPO_ROOT="$OUT/work"
cd "$OUT/work" || exit 1
zsh "$OUT/engine/pm_flow.sh" export --json > "$OUT/payload.json" 2> "$OUT/payload.err"
print "exit=$?  payload bytes=$(wc -c < $OUT/payload.json)"
cat "$OUT/payload.err"

snapshot > "$OUT/after.txt"
if diff -q "$OUT/before.txt" "$OUT/after.txt" > /dev/null; then
  print "flow-directory-unchanged=YES (content and file set identical)"
else
  print "flow-directory-unchanged=NO"
  diff "$OUT/before.txt" "$OUT/after.txt" | head -20
fi
