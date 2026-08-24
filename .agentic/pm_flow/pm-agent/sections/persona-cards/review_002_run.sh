set -u
WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/persona-cards
SEC=/Users/salah/code/personal/pm-flow/.agentic/pm_flow/pm-agent/sections/persona-packs/cycles/011
cd "$WT"
echo "=== repo toplevel seen by the harness ==="
git rev-parse --show-toplevel
echo "=== persona_cards_test.sh ==="
zsh "$WT/tests/persona_cards_test.sh" > /tmp/pmreview-cards.log 2>&1
echo "cards_exit=$?"
tail -n 20 /tmp/pmreview-cards.log
echo "=== persona-packs acceptance.sh ==="
zsh "$SEC/acceptance.sh" > /tmp/pmreview-acc.log 2>&1
echo "acceptance_exit=$?"
grep -E "tick1_exit|tick2_exit|assertions_exit|all one-store" /tmp/pmreview-acc.log
echo "=== persona-packs regressions.sh ==="
zsh "$SEC/regressions.sh" > /tmp/pmreview-reg.log 2>&1
echo "regressions_exit=$?"
grep -E "^RESULT|cycle_0[0-9]+_exit" /tmp/pmreview-reg.log
