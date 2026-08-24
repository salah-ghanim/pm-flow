#!/bin/zsh -f
set -u
WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/artifact-quality
MAIN=/Users/salah/code/personal/pm-flow
P=/tmp/pm-flow-aq-crossrepo2
rm -rf -- "$P"; mkdir -p "$P/other"
git -C "$P/other" init -q
cd "$MAIN"

print "=== real repo_root (pm-flow main checkout), --out into a different tracked repo"
PYTHONPATH="$WT/src" python3 -m pm_flow.quality rank --project pm-agent \
  --out "$P/other/quality" > "$P/out.txt" 2> "$P/err.txt"
print "EXIT=$?"
print "STDERR:"; cat "$P/err.txt"
print "WROTE:"; find "$P/other" -name 'latest.*' -print
print "check-ignore rc from pm-flow repo_root for that path:"
git -C "$MAIN" check-ignore -q "$P/other/quality"
print "rc=$?"
print "check-ignore stderr:"
git -C "$MAIN" check-ignore "$P/other/quality"
print "rc2=$?"

print ""
print "=== default destination is always inside the flow repo, so the ignore check does apply there"
git -C "$MAIN" check-ignore -v .agentic/pm_flow/pm-agent/quality
print "rc=$?"
