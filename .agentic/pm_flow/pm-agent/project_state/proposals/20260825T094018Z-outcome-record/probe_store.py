import sqlite3

db = sqlite3.connect("/Users/salah/code/personal/pm-flow/.agentic/pm_flow/pm-agent/runs/pm_flow.db")
cur = db.cursor()
print("outcomes by metric:")
for row in cur.execute("SELECT metric, COUNT(*) FROM outcomes GROUP BY metric"):
    print(" ", row)
print("runs by status:")
for row in cur.execute("SELECT status, COUNT(*) FROM runs GROUP BY status"):
    print(" ", row)
print("runs with NULL ended_at:", cur.execute("SELECT COUNT(*) FROM runs WHERE ended_at IS NULL").fetchone()[0])
print("total runs:", cur.execute("SELECT COUNT(*) FROM runs").fetchone()[0])
