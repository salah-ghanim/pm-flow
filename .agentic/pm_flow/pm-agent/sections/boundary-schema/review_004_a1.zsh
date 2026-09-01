#!/bin/zsh
# PM review, cycle 004, A1: live export from the developer's checkout.
set -u
WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/boundary-schema
LIVE=/Users/salah/code/personal/pm-flow
ENGINE="$WT/template/.agentic/pm_flow/pm_flow.sh"
OUT=/tmp/pm-review-004
rm -rf "$OUT"
mkdir -p "$OUT"

print "=== inherited pm-flow env ==="
env | grep '^PM_FLOW' | sort

# Point every root at the developer's checkout for the engine, the live repo
# for the data, exactly as an installed run would after this change lands.
export PM_FLOW_ENGINE_ROOT="$WT/template/.agentic/pm_flow"
export PM_FLOW_FLOW_DIR="$LIVE/.agentic/pm_flow"
export PM_FLOW_REPO_ROOT="$LIVE"

cd "$LIVE" || exit 1
git status --porcelain > "$OUT/git-before.txt"

zsh "$ENGINE" export --json > "$OUT/run1.json" 2> "$OUT/run1.err"
rc1=$?
print "exit1=$rc1"
if (( rc1 != 0 )); then
  print "stderr:"
  cat "$OUT/run1.err"
  exit 1
fi

zsh "$ENGINE" export --json > "$OUT/run2.json" 2> "$OUT/run2.err"
print "exit2=$?"

git status --porcelain > "$OUT/git-after.txt"
if cmp -s "$OUT/git-before.txt" "$OUT/git-after.txt"; then
  print "git-status-identical=YES"
else
  print "git-status-identical=NO"
  diff "$OUT/git-before.txt" "$OUT/git-after.txt"
fi

if cmp -s "$OUT/run1.json" "$OUT/run2.json"; then
  print "stable=YES"
else
  print "stable=NO"
fi

python3 -m json.tool "$OUT/run1.json" > /dev/null
print "json-tool-exit=$?"

print "=== section keys: export vs directory listing ==="
python3 - "$OUT/run1.json" "$LIVE/.agentic/pm_flow/pm-agent/sections" <<'PY'
import json, sys
from pathlib import Path
doc = json.loads(Path(sys.argv[1]).read_text())
keys = sorted(s["key"] for s in doc["sections"])
dirs = sorted(p.name for p in Path(sys.argv[2]).iterdir() if p.is_dir())
print("project      =", doc["project"])
print("export count =", len(keys))
print("dir count    =", len(dirs))
print("identical    =", keys == dirs)
print("export keys  =", ", ".join(keys))
if keys != dirs:
    print("only in export:", sorted(set(keys) - set(dirs)))
    print("only in dirs  :", sorted(set(dirs) - set(keys)))
PY
