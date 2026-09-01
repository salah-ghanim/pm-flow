#!/usr/bin/env zsh
# Cycle 003 review: real rejection messages from the three consumers, the store
# actually seen by topology.py, and the oneOf/$ref swallow case.
# The dispatching driver exports PM_FLOW_* into this process; the suite unsets
# them at its top, so a hand probe must do the same or it reads the host flow.
set -u
for name in ${(k)parameters[(I)PM_FLOW_*]}; do
  unset "$name"
done
WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/boundary-schema
OUT=/Users/salah/code/personal/pm-flow/.agentic/pm_flow/pm-agent/sections/boundary-schema/review_003
mkdir -p "$OUT"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/bs-msgs-003.XXXXXX")"
FLOW="$WORK/.agentic/pm_flow"
mkdir -p "$WORK/.agentic"
cp -R "$WT/template/.agentic/pm_flow" "$FLOW"
PROJECT_KEY=probe-project
mkdir -p "$FLOW/$PROJECT_KEY/runs"
print -r -- "$PROJECT_KEY" > "$FLOW/.project-key"
print -r -- '{"domain":"generic"}' > "$FLOW/$PROJECT_KEY/project.json"

python3 - "$FLOW/$PROJECT_KEY/runs/pm_flow.db" <<'PY'
import json, sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("CREATE TABLE clis (key TEXT PRIMARY KEY, capabilities TEXT NOT NULL)")
for k, m in (("claude", ["claude-fable-5"]), ("codex", ["gpt-5.6-sol"]), ("copilot", [])):
    c.execute("INSERT INTO clis (key, capabilities) VALUES (?, ?)", (k, json.dumps({"models": m})))
c.commit(); c.close()
PY

print -r -- "--- registry topology.py actually sees on this flow"
python3 - "$FLOW" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import topology
flow = Path(sys.argv[1])
print("store_path:", topology.store_path(flow))
print("stored_models:", topology.stored_models(flow))
print("config_enums:", topology.config_enums(flow))
PY

cp "$WT/tests/fixtures/boundary_schema/config_unknown_cli.json" "$FLOW/config.json"
python3 - "$FLOW/config.json" "$FLOW/topologies/probe-unknown.json" <<'PY'
import json, sys
from pathlib import Path
config = json.loads(Path(sys.argv[1]).read_text())
Path(sys.argv[2]).write_text(json.dumps({
    "version": 1, "key": "probe-unknown", "name": "probe",
    "description": "probe", "roles": {"developer": config["roles"]["developer"]},
}, indent=2) + "\n")
PY

print -r -- "--- pm_flow.sh config on the unknown cli"
zsh "$FLOW/pm_flow.sh" config
print -r -- "pm_flow exit=$?"
print -r -- "--- topology.py validate on the unknown cli"
python3 "$FLOW/topology.py" validate probe-unknown --flow "$FLOW"
print -r -- "topology exit=$?"

print -r -- "--- acp accepted with the same store present"
cp "$WT/tests/fixtures/boundary_schema/config_valid.json" "$FLOW/config.json"
python3 - "$FLOW/config.json" "$FLOW/topologies/probe-acp.json" <<'PY'
import json, sys
from pathlib import Path
config = json.loads(Path(sys.argv[1]).read_text())
Path(sys.argv[2]).write_text(json.dumps({
    "version": 1, "key": "probe-acp", "name": "probe",
    "description": "probe", "roles": {"developer": config["roles"]["developer"]},
}, indent=2) + "\n")
PY
python3 "$FLOW/topology.py" validate probe-acp --flow "$FLOW"
print -r -- "topology acp exit=$?"

print -r -- "--- oneOf swallow: break arm 0 only, validate the whole document"
python3 - "$FLOW" "$WT/tests/fixtures/boundary_schema/config_valid.json" <<'PY'
import json, sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import export
schema = json.loads((Path(sys.argv[1]) / "schemas" / "config.schema.json").read_text())
schema["properties"]["roles"]["additionalProperties"]["oneOf"][0] = {"$ref": "#/$defs/nosuch"}
payload = json.loads(Path(sys.argv[2]).read_text())
payload["roles"] = {"consultant": payload["roles"]["consultant"]}
try:
    export.validate_schema(payload, schema, "config")
    print("ACCEPTED a document whose oneOf arm 0 holds an unresolvable pointer")
except ValueError as error:
    print("rejected:", error)
PY
print -r -- "work=$WORK"
