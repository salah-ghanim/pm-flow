set -u
WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/persona-cards
cd "$WT"
zsh "$WT/tests/pm_flow_test.sh" > /tmp/pmreview-suite.log 2>&1
echo "suite_exit=$?"
tail -n 15 /tmp/pmreview-suite.log
