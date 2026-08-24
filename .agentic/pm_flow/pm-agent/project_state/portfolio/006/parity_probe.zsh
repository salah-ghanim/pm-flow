#!/bin/zsh
# Portfolio review 006: store-ledger A1 parity probe on the live project.
# Bounded: total before, TSV arithmetic, import, total after, imported=N.
set -e
COST=/Users/salah/code/personal/pm-flow/template/.agentic/pm_flow/cost.py
DIR=/Users/salah/code/personal/pm-flow/.agentic/pm_flow/pm-agent
TSV=$DIR/runs/cost_ledger.tsv
echo "--- store total before import"
python3 "$COST" total "$DIR"
echo "--- TSV row count and cost-column sum"
awk -F'\t' 'NR>1 {n++; s+=$0+0} END {print n" rows"}' "$TSV"
head -1 "$TSV"
echo "--- import"
python3 "$COST" import "$DIR"
echo "--- store total after import"
python3 "$COST" total "$DIR"
echo "--- second import must be a no-op"
python3 "$COST" import "$DIR"
