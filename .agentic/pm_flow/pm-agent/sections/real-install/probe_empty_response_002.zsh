#!/bin/zsh
# PM review: verify the developer's read-only finding about cost.py's dedupe key.
set -uo pipefail
WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/real-install
TMP="$(mktemp -d "${TMPDIR:-/tmp}/pm-review-cost.XXXXXX")"
WS="$TMP/throwaway"
mkdir -p "$WS/runs"
printf '2026-01-01T00:00:00Z\tsec\tpm\tfirst\t1.000000\t\n' >  "$WS/runs/cost_ledger.tsv"
printf '2026-01-01T00:01:00Z\tsec\tpm\tsecond\t2.000000\t\n' >> "$WS/runs/cost_ledger.tsv"
print "=== ledger (2 rows, empty response field) ==="
cat -A "$WS/runs/cost_ledger.tsv"
print "=== cost.py import (unmodified, read-only use) ==="
python3 "$WT/template/.agentic/pm_flow/cost.py" import "$WS"
print "=== cost.py total ==="
python3 "$WT/template/.agentic/pm_flow/cost.py" total "$WS"
print "=== the dedupe key ==="
sed -n '170,200p' "$WT/template/.agentic/pm_flow/cost.py"
rm -rf "$TMP"
