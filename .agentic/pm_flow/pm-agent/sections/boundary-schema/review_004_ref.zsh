#!/bin/zsh
# PM review, cycle 004: does an unresolvable $ref inside a oneOf arm still get
# swallowed when another arm matches? (the cycle-003 blind spot)
set -u
WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/boundary-schema
python3 - "$WT/template/.agentic/pm_flow" <<'PY'
import importlib.util, json, sys
from pathlib import Path

engine = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("export_mod", engine / "export.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

schema = {
    "oneOf": [
        {"type": "string"},                              # this arm matches
        {"$ref": "#/$defs/typo-that-does-not-exist"},    # this one is a typo
    ],
    "$defs": {"real": {"type": "integer"}},
}
try:
    mod.validate_schema("a string", schema, "$", None, engine / "schemas")
    print("RESULT: swallowed - the typo did not surface (blind spot present)")
except mod.SchemaReferenceError as error:
    print("RESULT: escaped as SchemaReferenceError -", error)
except ValueError as error:
    print("RESULT: escaped as ValueError -", error)

schema2 = {
    "oneOf": [
        {"type": "string"},
        {"$ref": "no_such_file.schema.json#"},
    ],
}
try:
    mod.validate_schema("a string", schema2, "$", None, engine / "schemas")
    print("RESULT(file): swallowed - the missing file did not surface")
except mod.SchemaReferenceError as error:
    print("RESULT(file): escaped -", str(error).split(":")[0])

# and the happy path still resolves an external $ref
handoff = json.loads((engine / "schemas" / "handoff.schema.json").read_text())
print("external $ref still resolves:", end=" ")
mod.validate_schema(
    {"outcome": "a", "decisions": "b", "interfaces": "c", "risks": "d",
     "unproven": "e", "next_action": "f", "word_count": 1, "byte_count": 1},
    {"$ref": "handoff.schema.json#"}, "$", None, engine / "schemas")
print("yes")
PY
