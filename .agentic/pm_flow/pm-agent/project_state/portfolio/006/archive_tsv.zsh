#!/bin/zsh
# Portfolio review 006: archive the imported cost ledger under a dated name.
# Authorized after the A1 parity probe ran (imported=0, idempotent).
set -e
RUNS=/Users/salah/code/personal/pm-flow/.agentic/pm_flow/pm-agent/runs
mv "$RUNS/cost_ledger.tsv" "$RUNS/cost_ledger.tsv.imported-20260824"
ls "$RUNS" | grep cost_ledger
