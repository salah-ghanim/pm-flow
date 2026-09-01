#!/bin/zsh -f
set -uo pipefail
SRC=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/outcome-record
zsh "$SRC/tests/outcome_record_test.sh" >/dev/null 2>&1
print "outcome_record_test.sh EXIT=$?"
zsh "$SRC/template/.agentic/pm_flow/tests/run.zsh" >/dev/null 2>&1
print "template/tests/run.zsh EXIT=$?"
grep -n 'treating as' "$SRC/template/.agentic/pm_flow/driver.zsh"
