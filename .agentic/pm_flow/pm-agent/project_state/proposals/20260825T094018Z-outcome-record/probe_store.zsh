#!/bin/zsh
DB=/Users/salah/code/personal/pm-flow/.agentic/pm_flow/pm-agent/runs/pm_flow.db
echo "outcomes by metric:"
sqlite3 "$DB" "SELECT metric, COUNT(*) FROM outcomes GROUP BY metric"
echo "runs by status:"
sqlite3 "$DB" "SELECT status, COUNT(*) FROM runs GROUP BY status"
echo "runs with NULL ended_at:"
sqlite3 "$DB" "SELECT COUNT(*) FROM runs WHERE ended_at IS NULL"
echo "total runs:"
sqlite3 "$DB" "SELECT COUNT(*) FROM runs"
echo "outcomes table schema:"
sqlite3 "$DB" "SELECT sql FROM sqlite_master WHERE name='outcomes'"
