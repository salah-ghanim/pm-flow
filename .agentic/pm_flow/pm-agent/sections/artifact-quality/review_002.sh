#!/bin/zsh -f
set -euo pipefail

WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/artifact-quality
MAIN=/Users/salah/code/personal/pm-flow
TMP="$(mktemp -d "${TMPDIR:-/tmp}/aq-review.XXXXXX")"

for name in ${(k)parameters[(I)PM_FLOW_*]}; do unset "$name"; done
unset PYTHONPATH

cp -R "$WT/src" "$TMP/src"
cp -R "$WT/template" "$TMP/template"
git -C "$WT" show HEAD:src/pm_flow/quality.py > "$TMP/src/pm_flow/quality.py"
git -C "$WT" show HEAD:template/.agentic/pm_flow/artifact_quality.md \
  > "$TMP/template/.agentic/pm_flow/artifact_quality.md"

report() {
  local tag="$1" root="$2"
  cd -P -- "$root"
  PYTHONPATH="$TMP/src" python3 -m pm_flow.quality rank --project pm-agent > "$TMP/$tag.before.out"
  PYTHONPATH="$WT/src"  python3 -m pm_flow.quality rank --project pm-agent > "$TMP/$tag.after.out"
  print -r -- "===== $tag artifacts (cwd $root) ====="
  print -r -- "scored files: $(wc -l < "$TMP/$tag.before.out" | tr -d ' ') before, $(wc -l < "$TMP/$tag.after.out" | tr -d ' ') after"
  print -r -- "shape:      before $(grep -c 'shape:' "$TMP/$tag.before.out")  after $(grep -c 'shape:' "$TMP/$tag.after.out")"
  print -r -- "boundaries: before $(grep -c 'boundaries:' "$TMP/$tag.before.out")  after $(grep -c 'boundaries:' "$TMP/$tag.after.out")"
  print -r -- "--- surviving shape lines (after) ---"
  grep 'shape:' "$TMP/$tag.after.out" || true
  print -r -- "--- artifact-quality own brief (after) ---"
  grep 'sections/artifact-quality/brief.md' "$TMP/$tag.after.out" || true
  print -r -- ""
}

print -r -- "TMP=$TMP"
report worktree "$WT"
report live "$MAIN"
