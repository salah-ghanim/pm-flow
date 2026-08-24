#!/bin/zsh -f

set -euo pipefail

ROOT="${0:A:h:h}"
CARD="$ROOT/template/.agentic/pm_flow/cards/reviewer.card.json"
SCHEMA="$ROOT/template/.agentic/pm_flow/cards/a2a-agent-skill.schema.json"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/persona-cards-test.XXXXXX")"
trap 'rm -rf -- "$WORK_DIR"' EXIT HUP INT TERM
EXPORTED_SKILLS="$WORK_DIR/exported-skills.json"

PYTHONPATH="$ROOT/src" python3 - "$CARD" "$EXPORTED_SKILLS" <<'PY'
import copy
import json
import sys
from pathlib import Path

from pm_flow import persona_card


card_path = Path(sys.argv[1])
skills_path = Path(sys.argv[2])
expected = json.loads(card_path.read_text())
parsed = persona_card.parse(card_path.read_text())


def assert_card_fields(actual, wanted, phase):
    assert set(actual) == set(wanted), f"{phase}: top-level field set changed"
    for field in ("name", "author", "purpose", "version", "provenance"):
        assert actual[field] == wanted[field], f"{phase}: field {field} changed"
        print(f"PASS: {phase} field {field}")
    assert len(actual["skills"]) == len(wanted["skills"]), f"{phase}: skill count changed"
    for index, wanted_skill in enumerate(wanted["skills"]):
        actual_skill = actual["skills"][index]
        assert set(actual_skill) == set(wanted_skill), f"{phase}: skill {index} fields changed"
        for field, value in wanted_skill.items():
            assert actual_skill[field] == value, f"{phase}: skill {index}.{field} changed"
            print(f"PASS: {phase} skill[{index}].{field}")


assert_card_fields(parsed, expected, "parse")
read_back = persona_card.parse(persona_card.export(parsed))
assert_card_fields(read_back, expected, "round-trip")
assert [skill["id"] for skill in read_back["skills"]] == [
    skill["id"] for skill in expected["skills"]
]
print("PASS: round-trip preserves skill ordering")

claim_values = [read_back["author"], *read_back["provenance"].values()]
assert all(value.startswith(persona_card.CLAIM_PREFIX) for value in claim_values)
print("PASS: author and provenance retain their unverified claim labels")

for field in ("model", "vendor", "transport", "url", "endpoint"):
    candidate = copy.deepcopy(expected)
    if field == "endpoint":
        candidate["skills"][0]["endpoint"] = "local-only"
        location = "nested skill"
    else:
        candidate[field] = "local-only"
        location = "top level"
    wanted = f'card field "{field}" is not allowed on a persona'
    try:
        persona_card.validate(candidate)
    except persona_card.PersonaCardError as exc:
        assert str(exc) == wanted, (field, str(exc), wanted)
        print(f"PASS: forbidden {field} ({location}): {exc}")
    else:
        raise AssertionError(f"forbidden field {field} was accepted")

skills_path.write_text(json.dumps(read_back["skills"], ensure_ascii=False))
PY

python3 - "$SCHEMA" "$EXPORTED_SKILLS" <<'PY'
import json
import sys
from pathlib import Path


schema = json.loads(Path(sys.argv[1]).read_text())
skills = json.loads(Path(sys.argv[2]).read_text())
header = schema.get("x-a2a-schema-provenance", {})
assert header.get("specVersion") == "0.2.5"
assert header.get("sourceUrl")
assert header.get("retrievedOn")
assert "Transcribed" in header.get("acquisition", "")


def walk(instance, rule, path="$"):
    expected_type = rule.get("type")
    type_table = {
        "object": dict,
        "array": list,
        "string": str,
        "number": (int, float),
        "integer": int,
        "boolean": bool,
        "null": type(None),
    }
    if expected_type is not None:
        python_type = type_table[expected_type]
        if not isinstance(instance, python_type) or (
            expected_type in ("number", "integer") and isinstance(instance, bool)
        ):
            raise AssertionError(f"{path}: expected {expected_type}")
    if "enum" in rule and instance not in rule["enum"]:
        raise AssertionError(f"{path}: value is not in enum")
    if isinstance(instance, dict):
        required = rule.get("required", [])
        for name in required:
            if name not in instance:
                raise AssertionError(f"{path}: missing required property {name}")
        properties = rule.get("properties", {})
        for name, value in instance.items():
            if name in properties:
                walk(value, properties[name], f"{path}.{name}")
            elif rule.get("additionalProperties") is False:
                raise AssertionError(f"{path}: additional property {name}")
            elif isinstance(rule.get("additionalProperties"), dict):
                walk(value, rule["additionalProperties"], f"{path}.{name}")
    if isinstance(instance, list) and "items" in rule:
        for index, value in enumerate(instance):
            walk(value, rule["items"], f"{path}[{index}]")
    if isinstance(instance, str) and "minLength" in rule:
        if len(instance) < rule["minLength"]:
            raise AssertionError(f"{path}: shorter than minLength")
    if isinstance(instance, list) and "minItems" in rule:
        if len(instance) < rule["minItems"]:
            raise AssertionError(f"{path}: shorter than minItems")


validator_ran = False
try:
    import jsonschema
except ImportError:
    for index, skill in enumerate(skills):
        walk(skill, schema, f"skills[{index}]")
    validator_ran = True
    print("validator=stdlib-schema-walker")
else:
    for skill in skills:
        jsonschema.validate(instance=skill, schema=schema)
    validator_ran = True
    print("validator=jsonschema")

assert validator_ran, "no independent schema validator ran"
print(f"PASS: {len(skills)} exported skills validate against pinned A2A AgentSkill schema")
PY

print 'PASS: persona card schema, refusal, round-trip, and independent validation'

CATALOG="$ROOT/template/.agentic/pm_flow/catalog.py"
STORE="$WORK_DIR/catalog.db"
CARDED_PACK="$WORK_DIR/carded-pack"
UNCARDED_PACK="$WORK_DIR/uncarded-pack"
mkdir -p "$CARDED_PACK/personas" "$CARDED_PACK/cards" "$UNCARDED_PACK/personas"
/bin/cp "$CARD" "$CARDED_PACK/cards/reviewer.json"

cat > "$CARDED_PACK/persona-pack.json" <<'JSON'
{
  "name": "carded-pack",
  "author": "Pack Publisher",
  "license": "CC-BY-4.0",
  "version": "7.0.0",
  "tags": ["fixture"],
  "personas": [{
    "key": "carded-reviewer",
    "file": "personas/reviewer.md",
    "card": "cards/reviewer.json",
    "layer": "base",
    "title": "Carded reviewer",
    "summary": "A persona with stored identity."
  }]
}
JSON
cat > "$CARDED_PACK/personas/reviewer.md" <<'MD'
Review the stated contract and cite the evidence for every conclusion.
MD

cat > "$UNCARDED_PACK/persona-pack.json" <<'JSON'
{
  "name": "uncarded-pack",
  "author": "Original Pack Author",
  "license": "CC0-1.0",
  "version": "9.9.9",
  "tags": [],
  "personas": [{
    "key": "plain-persona",
    "file": "personas/plain.md",
    "layer": "style",
    "title": "Plain persona",
    "summary": "The compatibility fixture."
  }]
}
JSON
cat > "$UNCARDED_PACK/personas/plain.md" <<'MD'
Plain uncarded prompt.
MD

run_catalog () {
  env -u PM_FLOW_ENGINE_ROOT -u PM_FLOW_FLOW_DIR -u PM_FLOW_PROJECT \
    -u PM_FLOW_PROJECT_DIR -u PM_FLOW_REPO_ROOT -u PM_FLOW_ROOT \
    -u PM_FLOW_RUNS_DIR -u PM_FLOW_SECTIONS_DIR -u PM_FLOW_STATE_DIR \
    -u PM_FLOW_STORE \
    python3 "$CATALOG" --db "$STORE" "$@"
}

snapshot_rows () {
  python3 - "$STORE" "$1" <<'PY'
import json
import sqlite3
import sys


connection = sqlite3.connect(sys.argv[1])
connection.row_factory = sqlite3.Row
snapshot = {
    table: [dict(row) for row in connection.execute(
        f'SELECT * FROM "{table}" ORDER BY rowid'
    )]
    for table in ("personas", "persona_packs", "seat_personas")
}
with open(sys.argv[2], "w") as output:
    json.dump(snapshot, output, indent=2, sort_keys=True, default=str)
PY
}

dispatch_counts () {
  python3 - "$STORE" <<'PY'
import sqlite3
import sys


connection = sqlite3.connect(sys.argv[1])
print(" ".join(str(connection.execute(
    f'SELECT COUNT(*) FROM "{table}"'
).fetchone()[0]) for table in ("attempts", "spans")))
PY
}

run_catalog persona add "$CARDED_PACK"
python3 - "$STORE" "$CARD" <<'PY'
import json
import sqlite3
import sys


connection = sqlite3.connect(sys.argv[1])
connection.row_factory = sqlite3.Row
row = connection.execute(
    "SELECT * FROM personas WHERE key = 'carded-reviewer' ORDER BY id DESC LIMIT 1"
).fetchone()
card = json.loads(open(sys.argv[2]).read())
metadata = json.loads(row["metadata"])
assert metadata["card"] == card, "stored card differs from validated card"
assert row["author"] == card["author"]
assert row["version"] == card["version"]
pack = connection.execute(
    "SELECT * FROM persona_packs WHERE name = 'carded-pack'"
).fetchone()
assert pack["author"] == "Pack Publisher"
assert pack["license"] == "CC-BY-4.0"
print("PASS: card installs verbatim while pack provenance remains on its row")
PY

counts_before="$(dispatch_counts)"
show_output="$(run_catalog persona show carded-reviewer)"
counts_after="$(dispatch_counts)"
[[ "$counts_after" == "$counts_before" ]] || {
  print -u2 "persona show dispatched: before=$counts_before after=$counts_after"
  exit 1
}
[[ "$show_output" == *"author: unverified claim: pm-flow contributors"* ]]
[[ "$show_output" == *"purpose: Review a bounded implementation against its stated contract and evidence."* ]]
[[ "$show_output" == *"version: 1.0.0"* ]]
[[ "$show_output" == *'"name": "Contract review"'* ]]
[[ "$show_output" == *'"name": "Failure analysis"'* ]]
print "PASS: persona show reads every card field with the claim label intact"
print "PASS: persona show leaves attempts and spans unchanged ($counts_before)"

set +e
unknown_output="$(run_catalog persona show not-installed 2>&1)"
unknown_status=$?
set -e
[[ $unknown_status -ne 0 ]]
[[ "$unknown_output" == "persona show: no installed persona 'not-installed'; \`persona list\` shows what is installed" ]]
print 'PASS: persona show points an unknown key at persona list'

run_catalog persona add "$UNCARDED_PACK"
list_output="$(run_catalog persona list)"
[[ "$list_output" == *"plain-persona"* ]]
[[ "$list_output" == *"uncarded-pack"* ]]
[[ "$list_output" == *"9.9.9"* ]]
[[ "$list_output" == *"Plain uncarded prompt."* ]]
uncarded_show="$(run_catalog persona show plain-persona)"
[[ "$uncarded_show" == *"author: Original Pack Author"* ]]
[[ "$uncarded_show" == *"version: 9.9.9"* ]]
[[ "$uncarded_show" == *"card: this persona has no card"* ]]
print 'PASS: an uncarded persona installs, lists, and shows without a card'

ISOLATED_FLOW="$WORK_DIR/isolated/engine"
ISOLATED_STORE="$WORK_DIR/isolated/catalog.db"
mkdir -p "$ISOLATED_FLOW"
/bin/cp "$CATALOG" "$ROOT/template/.agentic/pm_flow/store.py" "$ISOLATED_FLOW/"
set +e
missing_module="$(env -u PM_FLOW_ENGINE_ROOT -u PM_FLOW_FLOW_DIR \
  -u PM_FLOW_PROJECT -u PM_FLOW_PROJECT_DIR -u PM_FLOW_REPO_ROOT \
  -u PM_FLOW_ROOT -u PM_FLOW_RUNS_DIR -u PM_FLOW_SECTIONS_DIR \
  -u PM_FLOW_STATE_DIR -u PM_FLOW_STORE \
  python3 -S "$ISOLATED_FLOW/catalog.py" --db "$ISOLATED_STORE" \
  persona add "$CARDED_PACK" 2>&1)"
missing_module_status=$?
set -e
[[ $missing_module_status -ne 0 ]]
[[ "$missing_module" == "persona add: cannot find pm_flow.persona_card to validate persona card" ]]
env -u PM_FLOW_ENGINE_ROOT -u PM_FLOW_FLOW_DIR -u PM_FLOW_PROJECT \
  -u PM_FLOW_PROJECT_DIR -u PM_FLOW_REPO_ROOT -u PM_FLOW_ROOT \
  -u PM_FLOW_RUNS_DIR -u PM_FLOW_SECTIONS_DIR -u PM_FLOW_STATE_DIR \
  -u PM_FLOW_STORE \
  python3 -S "$ISOLATED_FLOW/catalog.py" --db "$ISOLATED_STORE" \
  persona add "$UNCARDED_PACK" >/dev/null
print 'PASS: missing card module fails closed while an uncarded pack remains installable'

for field in model vendor transport url endpoint; do
  BAD_PACK="$WORK_DIR/forbidden-$field"
  mkdir -p "$BAD_PACK/personas" "$BAD_PACK/cards"
  python3 - "$CARD" "$BAD_PACK" "$field" <<'PY'
import copy
import json
import sys
from pathlib import Path


card_source, root_text, field = sys.argv[1:]
root = Path(root_text)
card = copy.deepcopy(json.loads(Path(card_source).read_text()))
if field == "endpoint":
    card["skills"][0][field] = "local-only"
else:
    card[field] = "local-only"
(root / "cards" / "invalid.json").write_text(json.dumps(card, indent=2) + "\n")
(root / "personas" / "invalid.md").write_text("This row must never survive.\n")
manifest = {
    "name": f"forbidden-{field}",
    "author": "Pack Publisher",
    "license": "CC0-1.0",
    "version": "1.0.0",
    "tags": [],
    "personas": [{
        "key": f"forbidden-{field}",
        "file": "personas/invalid.md",
        "card": "cards/invalid.json",
        "layer": "task",
    }],
}
(root / "persona-pack.json").write_text(json.dumps(manifest, indent=2) + "\n")
PY
  before="$WORK_DIR/$field-before.json"
  after="$WORK_DIR/$field-after.json"
  snapshot_rows "$before"
  set +e
  refusal="$(run_catalog persona add "$BAD_PACK" 2>&1)"
  refusal_status=$?
  set -e
  snapshot_rows "$after"
  if ! cmp -s "$before" "$after"; then
    print -u2 "refused $field install left surviving or changed rows"
    diff -u "$before" "$after" || true
    exit 1
  fi
  [[ $refusal_status -ne 0 ]] || {
    print -u2 "forbidden $field install succeeded despite unchanged snapshot"
    exit 1
  }
  first_line="${refusal%%$'\n'*}"
  actual="${first_line#persona add: }"
  wanted="card field \"$field\" is not allowed on a persona"
  [[ "$actual" == "$wanted" ]] || {
    print -u2 "forbidden $field message mismatch: '$actual' != '$wanted'"
    exit 1
  }
  location="$field"
  [[ "$field" == endpoint ]] && location="skills[0].endpoint"
  [[ "$refusal" == *$'\ncard field path: '"$location"* ]] || {
    print -u2 "forbidden $field refusal omitted its field path: $refusal"
    exit 1
  }
  [[ "$refusal" == *$'\ncard file: cards/invalid.json' ]]
  print "PASS: install refuses $field at $location exactly and preserves all rows"
done

print 'PASS: persona card install and display integration'
