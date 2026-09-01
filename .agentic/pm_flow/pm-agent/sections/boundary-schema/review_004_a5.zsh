#!/bin/zsh
# PM review, cycle 004, A5: the four suites, in the developer's checkout.
set -u
WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/boundary-schema
OUT=/tmp/pm-review-004/a5
rm -rf "$OUT"
mkdir -p "$OUT"

for name in ${(k)parameters[(I)PM_FLOW_*]}; do
  unset "$name"
done
cd "$WT" || exit 1

run_suite() {
  local label="$1"
  shift
  print "########## $label ##########"
  "$@" > "$OUT/$label.out" 2> "$OUT/$label.err"
  local rc=$?
  print "exit=$rc"
  print "stdout:"
  cat "$OUT/$label.out"
  print "stderr:"
  cat "$OUT/$label.err"
  print
}

run_suite boundary zsh tests/boundary_schema_test.sh
run_suite verdict_parser zsh template/.agentic/pm_flow/tests/verdict_parser.zsh
run_suite agent_bindings zsh tests/agent_bindings_test.sh
run_suite pm_flow zsh tests/pm_flow_test.sh
