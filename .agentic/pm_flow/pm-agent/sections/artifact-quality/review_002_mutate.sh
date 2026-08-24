#!/bin/zsh -f
set -uo pipefail

WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/artifact-quality
TMP=/var/folders/9x/9xzxgmhn75q66kr2x3n691hw0000gn/T//aq-review.7X98GD

print -r -- "=== stale/echo/length counts, live tree, before vs after ==="
for d in stale echo length; do
  print -r -- "$d: before $(grep -c "$d:" $TMP/live.before.out)  after $(grep -c "$d:" $TMP/live.after.out)"
done
print -r -- ""

print -r -- "=== negative check: new test suite against OLD quality.py ==="
MUT="$(mktemp -d "${TMPDIR:-/tmp}/aq-mutate.XXXXXX")"
mkdir -p "$MUT/tests"
cp -R "$WT/src" "$MUT/src"
cp -R "$WT/template" "$MUT/template"
cp "$WT/tests/artifact_quality_test.sh" "$MUT/tests/artifact_quality_test.sh"
git -C "$WT" show HEAD:src/pm_flow/quality.py > "$MUT/src/pm_flow/quality.py"
zsh "$MUT/tests/artifact_quality_test.sh"
print -r -- "old-quality.py exit=$?"
print -r -- ""

print -r -- "=== negative check: new test suite against NEW quality.py with depth-2 terminator restored ==="
MUT2="$(mktemp -d "${TMPDIR:-/tmp}/aq-mutate2.XXXXXX")"
mkdir -p "$MUT2/tests"
cp -R "$WT/src" "$MUT2/src"
cp -R "$WT/template" "$MUT2/template"
cp "$WT/tests/artifact_quality_test.sh" "$MUT2/tests/artifact_quality_test.sh"
sed -i.bak 's|end = re.search(rf"(?m)^#{{1,{depth}}}\\s+", tail)|end = re.search(r"(?m)^#{1,2}\\s+", tail)|' "$MUT2/src/pm_flow/quality.py"
grep -n 'end = re.search' "$MUT2/src/pm_flow/quality.py"
zsh "$MUT2/tests/artifact_quality_test.sh"
print -r -- "depth-2-terminator exit=$?"
rm -rf -- "$MUT" "$MUT2"
