set -u
WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/persona-cards
CAT="$WT/template/.agentic/pm_flow/catalog.py"
CARD="$WT/template/.agentic/pm_flow/cards/reviewer.card.json"
W=$(mktemp -d /tmp/pmreview-probe.XXXXXX)
DB="$W/probe.db"
P="$W/pack"; mkdir -p "$P/personas" "$P/cards"
/bin/cp "$CARD" "$P/cards/reviewer.json"
cat > "$P/persona-pack.json" <<'JSON'
{"name":"probe-pack","author":"Pack Publisher","license":"CC-BY-4.0","version":"7.0.0","tags":["fixture"],
 "personas":[{"key":"probe-reviewer","file":"personas/reviewer.md","card":"cards/reviewer.json","layer":"base",
 "title":"Probe reviewer","summary":"Identity probe."}]}
JSON
printf 'Review the contract and cite evidence.\n' > "$P/personas/reviewer.md"

B="$W/bad"; mkdir -p "$B/personas" "$B/cards"
python3 - "$CARD" "$B" <<'PY'
import json, sys
from pathlib import Path
card = json.loads(Path(sys.argv[1]).read_text())
root = Path(sys.argv[2])
card["skills"][0]["endpoint"] = "https://example.invalid"
(root / "cards" / "bad.json").write_text(json.dumps(card, indent=2) + "\n")
(root / "personas" / "bad.md").write_text("Must never survive.\n")
(root / "persona-pack.json").write_text(json.dumps({
    "name": "bad-pack", "author": "Pack Publisher", "license": "CC0-1.0",
    "version": "1.0.0", "tags": [],
    "personas": [{"key": "bad-reviewer", "file": "personas/bad.md",
                  "card": "cards/bad.json", "layer": "task"}]}, indent=2) + "\n")
PY

run () { env -u PM_FLOW_ENGINE_ROOT -u PM_FLOW_FLOW_DIR -u PM_FLOW_PROJECT \
  -u PM_FLOW_PROJECT_DIR -u PM_FLOW_REPO_ROOT -u PM_FLOW_ROOT -u PM_FLOW_RUNS_DIR \
  -u PM_FLOW_SECTIONS_DIR -u PM_FLOW_STATE_DIR -u PM_FLOW_STORE \
  python3 "$CAT" --db "$DB" "$@"; }

echo "=== install carded pack ==="
run persona add "$P"; echo "add_exit=$?"
echo "=== persona show probe-reviewer (raw user-visible output) ==="
run persona show probe-reviewer; echo "show_exit=$?"
echo "=== rows before refused install ==="
python3 - "$DB" "$W/before.json" <<'PY'
import json, sqlite3, sys
c = sqlite3.connect(sys.argv[1]); c.row_factory = sqlite3.Row
snap = {t: [dict(r) for r in c.execute(f'SELECT * FROM "{t}" ORDER BY rowid')]
        for t in ("personas", "persona_packs", "seat_personas")}
json.dump(snap, open(sys.argv[2], "w"), indent=1, default=str, sort_keys=True)
print("personas", len(snap["personas"]), "packs", len(snap["persona_packs"]))
PY
echo "=== refused install (raw user-visible output, nested endpoint) ==="
run persona add "$B"; echo "bad_add_exit=$?"
echo "=== rows after refused install ==="
python3 - "$DB" "$W/after.json" <<'PY'
import json, sqlite3, sys
c = sqlite3.connect(sys.argv[1]); c.row_factory = sqlite3.Row
snap = {t: [dict(r) for r in c.execute(f'SELECT * FROM "{t}" ORDER BY rowid')]
        for t in ("personas", "persona_packs", "seat_personas")}
json.dump(snap, open(sys.argv[2], "w"), indent=1, default=str, sort_keys=True)
print("personas", len(snap["personas"]), "packs", len(snap["persona_packs"]))
PY
echo "=== byte-for-byte row-set comparison ==="
cmp "$W/before.json" "$W/after.json" && echo "ROWS IDENTICAL"
echo "=== attempts / spans after all of the above ==="
python3 - "$DB" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
for t in ("attempts", "spans"):
    print(t, c.execute(f'SELECT COUNT(*) FROM "{t}"').fetchone()[0])
PY
echo "=== stored metadata for the carded row ==="
python3 - "$DB" <<'PY'
import json, sqlite3, sys
c = sqlite3.connect(sys.argv[1]); c.row_factory = sqlite3.Row
r = c.execute("SELECT * FROM personas WHERE key='probe-reviewer'").fetchone()
print("row author :", r["author"])
print("row version:", r["version"])
print("metadata keys:", sorted(json.loads(r["metadata"])))
p = c.execute("SELECT * FROM persona_packs WHERE name='probe-pack'").fetchone()
print("pack author:", p["author"], "| pack license:", p["license"])
PY
rm -rf "$W"
