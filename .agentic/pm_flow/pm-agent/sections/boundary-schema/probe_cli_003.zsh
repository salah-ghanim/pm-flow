#!/usr/bin/env zsh
# Read-only probe: does an `acp` binding pass each of the three config.json
# consumers today, and where does topology.py's cli registry come from?
set -u

REPO=/Users/salah/code/personal/pm-flow
ENGINE=$REPO/template/.agentic/pm_flow
WORK=$(mktemp -d /tmp/boundary-cli-probe.XXXXXX)
print "probe_dir=$WORK"

python3 - "$ENGINE" "$WORK" <<'PY'
import json, sys, sqlite3
from pathlib import Path

engine, work = Path(sys.argv[1]), Path(sys.argv[2])
sys.path.insert(0, str(engine))
import topology

print("--- 1. schema enum (the definition) ---")
schema = json.loads((engine / "schemas" / "config.schema.json").read_text())
arms = schema["properties"]["roles"]["additionalProperties"]["oneOf"]
print("single-binding arm cli enum:", arms[0]["properties"]["cli"]["enum"])
print("panel arm cli enum:        ", arms[1]["items"]["properties"]["cli"]["enum"])
print("enums written twice in the schema file:",
      arms[0]["properties"]["cli"]["enum"] == arms[1]["items"]["properties"]["cli"]["enum"])

print("\n--- 2. topology.py FALLBACK_MODELS ---")
print("registered clis:", sorted(topology.FALLBACK_MODELS))
print("acp registered: ", "acp" in topology.FALLBACK_MODELS)

print("\n--- 3. validate_binding with an acp seat, fallback registry ---")
flow = work / "flow"
(flow / "roles").mkdir(parents=True)
(flow / "roles" / "developer.md").write_text("persona\n")
seat = {"cli": "acp", "model": "", "difficulty": "high"}
try:
    topology.validate_binding(
        "probe", "developer", seat, flow, "software",
        {"developer": "Developer"}, topology.FALLBACK_MODELS, True, engine)
    print("acp accepted")
except topology.TopologyError as error:
    print("acp REJECTED:", error)

print("\n--- 4. where the registry actually comes from at runtime ---")
live = Path("/Users/salah/code/personal/pm-flow/.agentic/pm_flow")
store = live / "pm-agent" / "runs" / "pm_flow.db"
print("live store present:", store.is_file(), store)
if store.is_file():
    connection = sqlite3.connect(f"{store.resolve().as_uri()}?mode=ro", uri=True)
    rows = connection.execute("SELECT key FROM clis").fetchall()
    connection.close()
    print("store clis table:", sorted(row[0] for row in rows))
    print("model_registry(flow) for the live flow:", sorted(topology.model_registry(live)))
    print("-> an acp seat validated against the STORE registry would be rejected:",
          "acp" not in topology.model_registry(live))
PY

print "\n--- 5. cmd_config's inline guard (pm_flow.sh:538-540) ---"
python3 - "$ENGINE" <<'PY'
from pathlib import Path
import sys
text = (Path(sys.argv[1]) / "pm_flow.sh").read_text().splitlines()
for number in (538, 539, 540, 541, 542, 543):
    print(f"{number}: {text[number - 1]}")
PY

print "\n--- 6. agent_exec.sh's guard (agent_exec.sh:198-203) ---"
python3 - "$ENGINE" <<'PY'
from pathlib import Path
import sys
text = (Path(sys.argv[1]) / "agent_exec.sh").read_text().splitlines()
for number in (198, 199, 200, 201, 202, 203):
    print(f"{number}: {text[number - 1]}")
PY

print "\n--- 7. is schemas/ reachable from an installed engine? ---"
grep -n "template/.agentic/pm_flow" "$REPO/pyproject.toml"
grep -c "^  schemas$" "$REPO/install.sh"
grep -c "^  export.py$" "$REPO/install.sh"

rm -rf "$WORK"
