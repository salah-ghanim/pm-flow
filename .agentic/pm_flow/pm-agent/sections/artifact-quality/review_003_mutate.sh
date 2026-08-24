#!/bin/zsh -f
set -u
WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/artifact-quality
MAIN=/Users/salah/code/personal/pm-flow
SCRATCH=/tmp/pm-flow-aq-mut-003
rm -rf -- "$SCRATCH"; mkdir -p "$SCRATCH"
cp -R "$WT/src" "$SCRATCH/src"
cp -R "$WT/tests" "$SCRATCH/tests"
cp -R "$WT/template" "$SCRATCH/template"

print "=== A) baseline differential: committed main-checkout quality.py vs worktree quality.py on live pm-agent data"
cd "$MAIN"
PYTHONPATH="$MAIN/src" python3 -m pm_flow.quality rank --project pm-agent \
  > "$SCRATCH/old.out" 2> "$SCRATCH/old.err"
print "OLD_EXIT=$?"
cat "$SCRATCH/old.err"
PYTHONPATH="$WT/src" python3 -m pm_flow.quality rank --project pm-agent \
  > "$SCRATCH/new.out" 2> "$SCRATCH/new.err"
print "NEW_EXIT=$?"
cat "$SCRATCH/new.err"
print "old lines: $(wc -l < "$SCRATCH/old.out" | tr -d ' ')  new lines: $(wc -l < "$SCRATCH/new.out" | tr -d ' ')"
if cmp -s "$SCRATCH/old.out" "$SCRATCH/new.out"; then
  print "STDOUT IDENTICAL to pre-change implementation"
else
  print "STDOUT DIFFERS:"; diff "$SCRATCH/old.out" "$SCRATCH/new.out" | head -40
fi
print "old length findings: $(grep -c 'length:' "$SCRATCH/old.out")"
print "=== files carrying a length finding, worktree run"
grep 'length:' "$SCRATCH/new.out" | sed 's/ | .*//' | sort

print ""
print "=== B) mutation: depth terminator reverted to ^#{1,2} in a scratch copy"
python3 - "$SCRATCH/src/pm_flow/quality.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = 'end = re.search(rf"(?m)^#{{1,{depth}}}\\s+", tail)'
new = 'end = re.search(r"(?m)^#{1,2}\\s+", tail)'
assert old in s, "terminator line not found"
open(p, "w", encoding="utf-8").write(s.replace(old, new))
print("mutated:", old, "->", new)
PY
grep -n 'end = re.search' "$SCRATCH/src/pm_flow/quality.py"
zsh "$SCRATCH/tests/artifact_quality_test.sh" > "$SCRATCH/mut.out" 2> "$SCRATCH/mut.err"
print "MUTATION_EXIT=$?"
print "--- mutation stdout tail"
tail -5 "$SCRATCH/mut.out"
print "--- mutation stderr"
cat "$SCRATCH/mut.err"

print ""
print "=== C) control: same scratch copy, unmutated"
cp "$WT/src/pm_flow/quality.py" "$SCRATCH/src/pm_flow/quality.py"
zsh "$SCRATCH/tests/artifact_quality_test.sh" > "$SCRATCH/ctl.out" 2> "$SCRATCH/ctl.err"
print "CONTROL_EXIT=$?"
tail -3 "$SCRATCH/ctl.out"
cat "$SCRATCH/ctl.err"
