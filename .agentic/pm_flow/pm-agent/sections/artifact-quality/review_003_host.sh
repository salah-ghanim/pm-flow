#!/bin/zsh -f
set -u
WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/artifact-quality
MAIN=/Users/salah/code/personal/pm-flow
OUT=/tmp/pm-flow-aq-review-003
rm -rf -- "$OUT"; mkdir -p "$OUT"
cd "$MAIN"

print "=== git rev-parse --show-toplevel (cwd=$MAIN)"
git rev-parse --show-toplevel
print "=== .git kind in main checkout"
if [[ -d "$MAIN/.git" ]]; then print "directory (not a linked worktree)"; else print "FILE"; fi

print "=== snapshots present before run"
ls "$MAIN/.agentic/pm_flow/pm-agent/quality"

git status --porcelain > "$OUT/status_before.txt"
print "=== STATUS_BEFORE"
cat "$OUT/status_before.txt"

sleep 1
PYTHONPATH="$WT/src" python3 -m pm_flow.quality rank --project pm-agent \
  > "$OUT/rank.out" 2> "$OUT/rank.err"
print "RANK_EXIT=$?"
print "=== RANK_STDERR"
cat "$OUT/rank.err"

git status --porcelain > "$OUT/status_after.txt"
print "=== STATUS_AFTER"
cat "$OUT/status_after.txt"

print "=== A2: status before vs after"
if cmp -s "$OUT/status_before.txt" "$OUT/status_after.txt"; then
  print "IDENTICAL"
else
  print "DIFFERS"; diff "$OUT/status_before.txt" "$OUT/status_after.txt"
fi

print "=== A2: find sections for quality*/*.score"
find "$MAIN/.agentic/pm_flow/pm-agent/sections" \( -name 'quality*' -o -name '*.score' \) -print
print "(end of find)"

print "=== A3: record directory listing"
ls -1 "$MAIN/.agentic/pm_flow/pm-agent/quality"

print "=== A3: git check-ignore -v latest.json"
git check-ignore -v .agentic/pm_flow/pm-agent/quality/latest.json

print "=== A3: latest.md byte-identical to stdout?"
if cmp -s "$OUT/rank.out" "$MAIN/.agentic/pm_flow/pm-agent/quality/latest.md"; then
  print "IDENTICAL"
else
  print "DIFFERS"
fi

print "=== A3: latest.json ordered files+findings vs stdout"
python3 "$MAIN/.agentic/pm_flow/pm-agent/sections/artifact-quality/review_003_cmp.py" \
  "$MAIN/.agentic/pm_flow/pm-agent/quality/latest.json" "$OUT/rank.out"

print "=== composite / total scan over stdout, latest.md, latest.json"
grep -Eci 'composite|quality:[[:space:]]*[0-9]|score[=:][[:space:]]*[0-9]' \
  "$OUT/rank.out" "$MAIN/.agentic/pm_flow/pm-agent/quality/latest.md" \
  "$MAIN/.agentic/pm_flow/pm-agent/quality/latest.json"

print "=== live dimension counts"
for dim in shape echo stale length boundaries; do
  print "$dim $(grep -c "$dim:" "$OUT/rank.out")"
done
print "FILES $(wc -l < "$OUT/rank.out" | tr -d ' ')"
