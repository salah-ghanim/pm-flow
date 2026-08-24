#!/bin/zsh -f
# Negative check for A1: copy the worktree, strip the os.setsid() shim from
# run_detach.zsh so the supervisor is merely backgrounded, and re-run the suite.
# If A1 is real, the suite must fail on supervisor survival.
set -e
W=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/run-detach
S=/tmp/pm-flow-negcheck.$$
mkdir -p "$S"
/usr/bin/rsync -a --exclude '.git' "$W/" "$S/"
/usr/bin/sed -i '' '/os.setsid(); os.execvp/d' "$S/template/.agentic/pm_flow/run_detach.zsh"
print -r -- "--- spawn block after mutation ---"
/usr/bin/grep -n -A 4 '__loop "\$RUNS_DIR"' "$S/template/.agentic/pm_flow/run_detach.zsh"
print -r -- "--- running mutated suite ---"
set +e
zsh "$S/tests/run_detach_test.sh"
print "MUTATED_EXIT=$?"
rm -rf -- "$S"
