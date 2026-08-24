#!/bin/zsh -f

set -euo pipefail

for name in ${(k)parameters[(I)PM_FLOW_*]}; do
  unset "$name"
done

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

all_skills = []
for packaged_path in sorted(card_path.parent.glob("*.card.json")):
    packaged = persona_card.parse(packaged_path.read_text())
    all_skills.extend(packaged["skills"])
skills_path.write_text(json.dumps(all_skills, ensure_ascii=False))
print(f"PASS: {len(all_skills)} skills load from every packaged card")
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
  run_catalog_db "$STORE" "$@"
}

run_catalog_db () {
  local database="$1"
  shift
  env -u PM_FLOW_ENGINE_ROOT -u PM_FLOW_FLOW_DIR -u PM_FLOW_PROJECT \
    -u PM_FLOW_PROJECT_DIR -u PM_FLOW_REPO_ROOT -u PM_FLOW_ROOT \
    -u PM_FLOW_RUNS_DIR -u PM_FLOW_SECTIONS_DIR -u PM_FLOW_STATE_DIR \
    -u PM_FLOW_STORE PYTHONPATH="$ROOT/src" \
    python3 "$CATALOG" --db "$database" "$@"
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
  python3 - "${1:-$STORE}" <<'PY'
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

show_output="$(run_catalog persona show carded-reviewer)"
[[ "$show_output" == *"author: unverified claim: pm-flow contributors"* ]]
[[ "$show_output" == *"purpose: Review a bounded implementation against its stated contract and evidence."* ]]
[[ "$show_output" == *"version: 1.0.0"* ]]
[[ "$show_output" == *'"name": "Contract review"'* ]]
[[ "$show_output" == *'"name": "Failure analysis"'* ]]
[[ "$show_output" == authorship\ notice:*"nothing here verifies it"* ]]
print "PASS: persona show reads every card field with the claim label intact"

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

ALICE_PACK="$WORK_DIR/alice-pack"
BOB_PACK="$WORK_DIR/bob-pack"
python3 - "$CARD" "$ALICE_PACK" "$BOB_PACK" <<'PY'
import copy
import json
import sys
from pathlib import Path


card_source = Path(sys.argv[1])
source = json.loads(card_source.read_text())
fixtures = (
    (Path(sys.argv[2]), "alice-pack", "Alice Example", "1.4.0",
     "Alice-specific review purpose.", "Alice reviewer wording."),
    (Path(sys.argv[3]), "bob-pack", "Bob Example", "2.7.0",
     "Bob-specific review purpose.", "Bob reviewer wording."),
)
for root, pack_name, author, version, purpose, wording in fixtures:
    (root / "personas").mkdir(parents=True)
    (root / "cards").mkdir()
    card = copy.deepcopy(source)
    card.update({
        "name": f"{author} reviewer",
        "author": f"unverified claim: {author}",
        "purpose": purpose,
        "version": version,
        "provenance": {
            "publisher": f"unverified claim: {pack_name}",
            "source": f"unverified claim: {author.lower().replace(' ', '-')}",
        },
    })
    manifest = {
        "name": pack_name,
        "author": f"{author} Publisher",
        "license": "CC-BY-4.0",
        "version": f"pack-{version}",
        "tags": ["identity", author.split()[0].lower()],
        "personas": [{
            "key": "reviewer",
            "file": "personas/reviewer.md",
            "card": "cards/reviewer.card.json",
            "layer": "base",
            "title": f"{author} reviewer",
            "summary": purpose,
            "tags": ["same-key"],
        }],
    }
    (root / "persona-pack.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (root / "cards" / "reviewer.card.json").write_text(
        json.dumps(card, indent=2) + "\n"
    )
    (root / "personas" / "reviewer.md").write_text(wording)
PY

run_catalog persona add "$ALICE_PACK"
run_catalog persona add "$BOB_PACK"
identity_list="$(run_catalog persona list)"
reviewer_list_rows="$(printf '%s\n' "$identity_list" | grep -c '^reviewer ' || true)"
plain_list_rows="$(printf '%s\n' "$identity_list" | grep -c '^plain-persona ' || true)"
[[ "$reviewer_list_rows" == 2 ]] || {
  print -u2 "persona list identity rows: expected 2 reviewer rows, got $reviewer_list_rows"
  exit 1
}
[[ "$plain_list_rows" == 1 ]] || {
  print -u2 "persona list uncarded identity rows: expected 1, got $plain_list_rows"
  exit 1
}
[[ "$identity_list" == *"unverified claim: Alice Example"* ]]
[[ "$identity_list" == *"unverified claim: Bob Example"* ]]
[[ "$identity_list" == "KEY"*"AUTHOR (CLAIMED)"* ]]
print 'PASS: persona list keeps two card-author identities and one uncarded identity'

set +e
ambiguous_show="$(run_catalog persona show reviewer 2>&1)"
ambiguous_show_status=$?
set -e
if [[ "$ambiguous_show" == *"Alice-specific review purpose."* || \
      "$ambiguous_show" == *"Bob-specific review purpose."* ]]; then
  print -u2 "ambiguous persona show returned the wrong card: $ambiguous_show"
  exit 1
fi
[[ $ambiguous_show_status -ne 0 ]]
[[ "$ambiguous_show" == *"unverified claim: Alice Example"* ]]
[[ "$ambiguous_show" == *"unverified claim: Bob Example"* ]]
[[ "$ambiguous_show" == *"--author"* ]]

alice_show="$(run_catalog persona show reviewer --author 'Alice Example')"
bob_show="$(run_catalog persona show reviewer --author 'unverified claim: Bob Example')"
[[ "$alice_show" == *"author: unverified claim: Alice Example"* ]]
[[ "$alice_show" == *"purpose: Alice-specific review purpose."* ]]
[[ "$alice_show" != *"Bob-specific review purpose."* ]]
[[ "$bob_show" == *"author: unverified claim: Bob Example"* ]]
[[ "$bob_show" == *"purpose: Bob-specific review purpose."* ]]
[[ "$bob_show" != *"Alice-specific review purpose."* ]]
print 'PASS: persona show refuses an ambiguous key and selects either claimed author'

EXPORT_DIR="$WORK_DIR/exported-alice"
ROUNDTRIP_STORE="$WORK_DIR/roundtrip.db"
set +e
ambiguous_export="$(run_catalog persona export reviewer \
  --out "$WORK_DIR/ambiguous-export" 2>&1)"
ambiguous_export_status=$?
set -e
[[ $ambiguous_export_status -ne 0 ]]
[[ "$ambiguous_export" == *"unverified claim: Alice Example"* ]]
[[ "$ambiguous_export" == *"unverified claim: Bob Example"* ]]
[[ "$ambiguous_export" == *"--author"* ]]
[[ ! -e "$WORK_DIR/ambiguous-export" ]]
print 'PASS: persona export refuses an ambiguous key before writing files'

run_catalog persona export reviewer --author 'Alice Example' --out "$EXPORT_DIR"
run_catalog_db "$ROUNDTRIP_STORE" persona add "$EXPORT_DIR"
python3 - "$STORE" "$ROUNDTRIP_STORE" <<'PY'
import json
import sqlite3
import sys


def row(database):
    connection = sqlite3.connect(database)
    connection.row_factory = sqlite3.Row
    return connection.execute(
        "SELECT * FROM personas WHERE key = 'reviewer' "
        "AND json_extract(metadata, '$.card.author') = ?",
        ("unverified claim: Alice Example",),
    ).fetchone()


source = row(sys.argv[1])
installed = row(sys.argv[2])
assert source is not None and installed is not None
left = json.loads(source["metadata"])["card"]
right = json.loads(installed["metadata"])["card"]
assert set(left) == set(right), "round-trip top-level card fields changed"
for field in sorted(set(left) - {"skills"}):
    assert left[field] == right[field], f"round-trip field {field} changed"
assert len(left["skills"]) == len(right["skills"])
for index, left_skill in enumerate(left["skills"]):
    right_skill = right["skills"][index]
    assert set(left_skill) == set(right_skill), (
        f"round-trip skill {index} field set changed"
    )
    for field in left_skill:
        assert left_skill[field] == right_skill[field], (
            f"round-trip skill {index}.{field} changed"
        )
assert [item["id"] for item in left["skills"]] == [
    item["id"] for item in right["skills"]
]
assert source["content_hash"] == installed["content_hash"]
print("PASS: exported card reinstalls field by field with skill order and hash intact")
PY

UNCARDED_EXPORT="$WORK_DIR/exported-plain"
run_catalog persona export plain-persona --out "$UNCARDED_EXPORT"
python3 - "$UNCARDED_EXPORT/persona-pack.json" <<'PY'
import json
import sys


manifest = json.load(open(sys.argv[1]))
assert "tags" in manifest and isinstance(manifest["tags"], list)
entry = manifest["personas"][0]
assert "card" not in entry
assert set(entry) <= {"key", "file", "layer", "title", "summary", "tags", "card"}
print("PASS: uncarded export has manifest tags and no card entry")
PY

INVALID_EXPORT_STORE="$WORK_DIR/invalid-export.db"
/bin/cp "$ROUNDTRIP_STORE" "$INVALID_EXPORT_STORE"
python3 - "$INVALID_EXPORT_STORE" <<'PY'
import json
import sqlite3
import sys


connection = sqlite3.connect(sys.argv[1])
row = connection.execute(
    "SELECT id, metadata FROM personas WHERE key = 'reviewer'"
).fetchone()
metadata = json.loads(row[1])
metadata["card"].pop("purpose")
connection.execute(
    "UPDATE personas SET metadata = ? WHERE id = ?",
    (json.dumps(metadata, sort_keys=True), row[0]),
)
connection.commit()
PY
set +e
invalid_export="$(run_catalog_db "$INVALID_EXPORT_STORE" persona export reviewer \
  --out "$WORK_DIR/invalid-card-export" 2>&1)"
invalid_export_status=$?
set -e
[[ $invalid_export_status -ne 0 ]]
[[ "$invalid_export" == 'persona export: persona card is missing required field "purpose"' ]] || {
  print -u2 "invalid stored-card export diagnostic mismatch: $invalid_export"
  exit 1
}
[[ "$invalid_export" != *"Traceback"* ]]
print 'PASS: persona export frames PersonaCardError without a traceback'

PACKAGED_FLOW="$WORK_DIR/packaged-flow"
PACKAGED_PROJECT="packaged-personas"
PACKAGED_STORE="$WORK_DIR/packaged.db"
PACKAGED_ENGINE="$ROOT/template/.agentic/pm_flow"
mkdir -p "$PACKAGED_FLOW/$PACKAGED_PROJECT/roles"
/bin/cp "$PACKAGED_ENGINE/config.json" "$PACKAGED_FLOW/config.json"
print 'Use the project-specific house style.' \
  > "$PACKAGED_FLOW/$PACKAGED_PROJECT/roles/pm.md"

run_catalog_db "$PACKAGED_STORE" sync --flow "$PACKAGED_FLOW" \
  --engine "$PACKAGED_ENGINE" --project "$PACKAGED_PROJECT" \
  --domain distressed-tech --topology default >/dev/null
packaged_counts_before="$(dispatch_counts "$PACKAGED_STORE")"
packaged_pm_show="$(run_catalog_db "$PACKAGED_STORE" persona show pm)"
packaged_developer_show="$(run_catalog_db "$PACKAGED_STORE" persona show developer)"
packaged_counts_after="$(dispatch_counts "$PACKAGED_STORE")"
[[ "$packaged_counts_after" == "$packaged_counts_before" ]]
[[ "$packaged_pm_show" == *"purpose: Own one section end to end"* ]]
[[ "$packaged_pm_show" == *'"name": "Cycle review"'* ]]
[[ "$packaged_pm_show" == *"version: 1.0.0"* ]]
[[ "$packaged_developer_show" == *"purpose: Implement one bounded workplan task"* ]]
[[ "$packaged_developer_show" == *'"name": "Bounded implementation"'* ]]
[[ "$packaged_developer_show" == *"author: unverified claim: pm-flow contributors"* ]]
print "PASS: shipped pm and developer cards display from a synced store without dispatch ($packaged_counts_before -> $packaged_counts_after)"

PACKAGED_SNAPSHOT="$WORK_DIR/packaged-before.json"
python3 - "$PACKAGED_STORE" "$PACKAGED_SNAPSHOT" <<'PY'
import json
import sqlite3
import sys


roles = {
    "10x_developer", "consultant", "cpo", "developer",
    "maintenance_engineer", "pm",
}
connection = sqlite3.connect(sys.argv[1])
connection.row_factory = sqlite3.Row
base_rows = connection.execute(
    "SELECT id, key, author, version, content_hash, metadata FROM personas "
    "WHERE layer = 'base' ORDER BY key"
).fetchall()
assert {row["key"] for row in base_rows} == roles
cards = {}
for row in base_rows:
    card = json.loads(row["metadata"])["card"]
    assert row["author"] == card["author"] == (
        "unverified claim: pm-flow contributors"
    )
    assert row["version"] == card["version"] == "1.0.0"
    cards[row["key"]] = card
assert len({card["purpose"] for card in cards.values()}) == len(roles)
assert all(card["name"] != "reviewer" for card in cards.values())
layer_rows = connection.execute(
    "SELECT key, metadata FROM personas WHERE layer IN ('domain', 'style')"
).fetchall()
assert layer_rows
assert all("card" not in json.loads(row["metadata"]) for row in layer_rows)
snapshot = {
    row["key"]: {
        "id": row["id"],
        "content_hash": row["content_hash"],
        "card": cards[row["key"]],
    }
    for row in base_rows
}
with open(sys.argv[2], "w") as output:
    json.dump(snapshot, output, indent=2, sort_keys=True)
print("PASS: six distinct shipped cards attach only to base rows; reviewer card is inert")
PY

packaged_list="$(run_catalog_db "$PACKAGED_STORE" persona list)"
for role in 10x_developer consultant cpo developer maintenance_engineer pm; do
  [[ "$(printf '%s\n' "$packaged_list" | grep -c "^$role " || true)" == 1 ]]
done
[[ "$packaged_list" == "KEY"*"AUTHOR (CLAIMED)"* ]]
print 'PASS: persona list shows every shipped role exactly once under AUTHOR (CLAIMED)'

run_catalog_db "$PACKAGED_STORE" sync --flow "$PACKAGED_FLOW" \
  --engine "$PACKAGED_ENGINE" --project "$PACKAGED_PROJECT" \
  --domain distressed-tech --topology default >/dev/null
python3 - "$PACKAGED_STORE" "$PACKAGED_SNAPSHOT" <<'PY'
import json
import sqlite3
import sys


connection = sqlite3.connect(sys.argv[1])
connection.row_factory = sqlite3.Row
before = json.load(open(sys.argv[2]))
after = {}
for row in connection.execute(
    "SELECT id, key, content_hash, metadata FROM personas WHERE layer = 'base'"
):
    after[row["key"]] = {
        "id": row["id"],
        "content_hash": row["content_hash"],
        "card": json.loads(row["metadata"])["card"],
    }
assert after == before
print("PASS: a second packaged sync preserves row ids, hashes, and cards")
PY

ADOPTION_ENGINE="$WORK_DIR/adoption-engine"
ADOPTION_STORE="$WORK_DIR/adoption.db"
/bin/cp -R "$PACKAGED_ENGINE" "$ADOPTION_ENGINE"
/bin/rm "$ADOPTION_ENGINE/cards/pm.card.json"
run_catalog_db "$ADOPTION_STORE" sync --flow "$ADOPTION_ENGINE" \
  --engine "$ADOPTION_ENGINE" --project adoption --domain '' \
  --topology default >/dev/null
python3 - "$ADOPTION_STORE" "$WORK_DIR/adoption-before.json" <<'PY'
import json
import sqlite3
import sys


connection = sqlite3.connect(sys.argv[1])
connection.row_factory = sqlite3.Row
row = connection.execute(
    "SELECT id, content_hash, metadata FROM personas WHERE key = 'pm'"
).fetchone()
assert "card" not in json.loads(row["metadata"])
json.dump({"id": row["id"], "content_hash": row["content_hash"]},
          open(sys.argv[2], "w"), sort_keys=True)
PY
/bin/cp "$PACKAGED_ENGINE/cards/pm.card.json" \
  "$ADOPTION_ENGINE/cards/pm.card.json"
run_catalog_db "$ADOPTION_STORE" sync --flow "$ADOPTION_ENGINE" \
  --engine "$ADOPTION_ENGINE" --project adoption --domain '' \
  --topology default >/dev/null
python3 - "$ADOPTION_STORE" "$WORK_DIR/adoption-before.json" \
  "$PACKAGED_ENGINE/cards/pm.card.json" <<'PY'
import json
import sqlite3
import sys


connection = sqlite3.connect(sys.argv[1])
connection.row_factory = sqlite3.Row
before = json.load(open(sys.argv[2]))
card = json.load(open(sys.argv[3]))
row = connection.execute(
    "SELECT id, author, version, content_hash, metadata FROM personas "
    "WHERE key = 'pm'"
).fetchone()
assert row["id"] == before["id"]
assert row["content_hash"] == before["content_hash"]
assert json.loads(row["metadata"])["card"] == card
assert row["author"] == card["author"]
assert row["version"] == card["version"]
print("PASS: sync adds a shipped card in place to an already-synced persona")
PY

INVALID_ENGINE="$WORK_DIR/invalid-engine"
INVALID_SYNC_STORE="$WORK_DIR/invalid-sync.db"
/bin/cp -R "$PACKAGED_ENGINE" "$INVALID_ENGINE"
python3 - "$INVALID_ENGINE/cards/pm.card.json" <<'PY'
import json
import sys


path = sys.argv[1]
card = json.load(open(path))
card["skills"][0]["endpoint"] = "must-not-run"
with open(path, "w") as output:
    json.dump(card, output, indent=2)
    output.write("\n")
PY
set +e
invalid_sync="$(run_catalog_db "$INVALID_SYNC_STORE" sync \
  --flow "$INVALID_ENGINE" --engine "$INVALID_ENGINE" --project invalid \
  --domain '' --topology default 2>&1)"
invalid_sync_status=$?
set -e
[[ $invalid_sync_status -ne 0 ]]
[[ "$invalid_sync" == *'sync: card field "endpoint" is not allowed on a persona'* ]]
[[ "$invalid_sync" == *$'card field path: skills[0].endpoint'* ]]
[[ "$invalid_sync" == *$'card file: cards/pm.card.json'* ]]
python3 - "$INVALID_SYNC_STORE" <<'PY'
import sqlite3
import sys


connection = sqlite3.connect(sys.argv[1])
tables = (
    "clis", "projects", "topologies", "personas", "bindings", "rules",
    "topology_agents", "seat_personas", "rule_bindings", "tool_grants",
    "topology_edges",
)
counts = {table: connection.execute(
    f'SELECT COUNT(*) FROM "{table}"'
).fetchone()[0] for table in tables}
assert not any(counts.values()), counts
print("PASS: nested packaged-card refusal occurs before sync writes any row")
PY

ISOLATED_SYNC_ENGINE="$WORK_DIR/isolated-sync/engine"
ISOLATED_SYNC_STORE="$WORK_DIR/isolated-sync/catalog.db"
mkdir -p "$ISOLATED_SYNC_ENGINE"
/bin/cp "$CATALOG" "$ROOT/template/.agentic/pm_flow/store.py" \
  "$ROOT/template/.agentic/pm_flow/config.json" "$ISOLATED_SYNC_ENGINE/"
/bin/cp -R "$ROOT/template/.agentic/pm_flow/roles" \
  "$ROOT/template/.agentic/pm_flow/cards" "$ISOLATED_SYNC_ENGINE/"
set +e
isolated_sync="$(env -u PM_FLOW_ENGINE_ROOT -u PM_FLOW_FLOW_DIR \
  -u PM_FLOW_PROJECT -u PM_FLOW_PROJECT_DIR -u PM_FLOW_REPO_ROOT \
  -u PM_FLOW_ROOT -u PM_FLOW_RUNS_DIR -u PM_FLOW_SECTIONS_DIR \
  -u PM_FLOW_STATE_DIR -u PM_FLOW_STORE -u PYTHONPATH \
  python3 -S "$ISOLATED_SYNC_ENGINE/catalog.py" --db "$ISOLATED_SYNC_STORE" \
  sync --flow "$ISOLATED_SYNC_ENGINE" --engine "$ISOLATED_SYNC_ENGINE" \
  --project isolated --domain '' --topology default 2>&1)"
isolated_sync_status=$?
set -e
[[ $isolated_sync_status -ne 0 ]]
[[ "$isolated_sync" == *"sync: cannot find pm_flow.persona_card to validate persona card"* ]]
[[ "$isolated_sync" == *"card file: cards/10x_developer.card.json"* ]]
print 'PASS: packaged sync fails closed and names the card when its validator cannot load'

COMPARE_ROOT="$WORK_DIR/compare"
COMMAND_WORK="$COMPARE_ROOT/repo"
mkdir -p "$COMMAND_WORK/.agentic"
/bin/cp -R "$ROOT/template/.agentic/pm_flow" "$COMMAND_WORK/.agentic/pm_flow"
FLOW="$COMMAND_WORK/.agentic/pm_flow"
PROJECT_KEY="persona-card-compare"
PROJECT_DIR="$FLOW/$PROJECT_KEY"
COMPARE_STORE="$PROJECT_DIR/runs/pm_flow.db"
mkdir -p "$PROJECT_DIR/runs"
printf '%s\n' "$PROJECT_KEY" > "$FLOW/.project-key"
printf '%s\n' '{"domain":"generic"}' > "$PROJECT_DIR/project.json"
printf '# Persona card comparison fixture\n' > "$PROJECT_DIR/task_contract.md"
sed 's/{{DOMAIN}}/generic/' "$FLOW/config.json" > "$COMPARE_ROOT/config.json"
mv -- "$COMPARE_ROOT/config.json" "$FLOW/config.json"

run_catalog_db "$COMPARE_STORE" sync --flow "$FLOW" \
  --project "$PROJECT_KEY" --domain generic --topology lean >/dev/null
run_catalog_db "$COMPARE_STORE" sync --flow "$FLOW" \
  --project "$PROJECT_KEY" --domain generic --topology heavy >/dev/null
run_catalog_db "$COMPARE_STORE" persona add "$ALICE_PACK" >/dev/null
run_catalog_db "$COMPARE_STORE" persona add "$BOB_PACK" >/dev/null

STUB_BIN="$COMPARE_ROOT/bin"
mkdir -p "$STUB_BIN"
/bin/cp "$ROOT/tests/fixtures/stub_success.zsh" "$STUB_BIN/claude"
chmod +x "$STUB_BIN/claude"
printf 'export PATH="%s:$PATH"\n' "$STUB_BIN" > "$FLOW/local_env.sh"

for section in alice-arm bob-arm; do
  (cd "$COMMAND_WORK" && env -u PM_FLOW_ENGINE_ROOT -u PM_FLOW_FLOW_DIR \
    -u PM_FLOW_PROJECT -u PM_FLOW_PROJECT_DIR -u PM_FLOW_REPO_ROOT \
    -u PM_FLOW_ROOT -u PM_FLOW_RUNS_DIR -u PM_FLOW_SECTIONS_DIR \
    -u PM_FLOW_STATE_DIR -u PM_FLOW_STORE -u PM_FLOW_TOPOLOGY \
    PATH="$STUB_BIN:$PATH" zsh "$FLOW/pm_flow.sh" \
    --project "$PROJECT_KEY" init-section "$section") <<SECTIONBRIEF >/dev/null
## Objective

- Produce one real comparison attempt.

## Scope

- The fixture only.

## Priority

- must-have: the comparison needs a real attempt.

## Owned paths

- fixture/$section/**

## Dependencies

- None.

## Acceptance

- The fixture completes.

## Rejection conditions

- A real backend is reached.
SECTIONBRIEF
  mkdir -p "$PROJECT_DIR/sections/$section/cycles/001"
  printf 'COMPLETE\n' > "$PROJECT_DIR/sections/$section/cycles/001/decision.txt"
done

set +e
ambiguous_swap="$(run_catalog_db "$COMPARE_STORE" persona swap pm reviewer \
  --project "$PROJECT_KEY" --topology lean 2>&1)"
ambiguous_swap_status=$?
set -e
[[ $ambiguous_swap_status -ne 0 ]]
[[ "$ambiguous_swap" == *"unverified claim: Alice Example"* ]]
[[ "$ambiguous_swap" == *"unverified claim: Bob Example"* ]]
[[ "$ambiguous_swap" == *"--author"* ]]

alice_swap="$(run_catalog_db "$COMPARE_STORE" persona swap pm reviewer \
  --author 'Alice Example' --project "$PROJECT_KEY" --topology lean)"
bob_swap="$(run_catalog_db "$COMPARE_STORE" persona swap pm reviewer \
  --author 'Bob Example' --project "$PROJECT_KEY" --topology heavy)"
[[ "$alice_swap" == *"pm seat(s)"* ]]
[[ "$bob_swap" == *"pm seat(s)"* ]]
print 'PASS: persona swap refuses an ambiguous key and selects either claimed author'

(cd "$COMMAND_WORK" && env -u PM_FLOW_ENGINE_ROOT -u PM_FLOW_FLOW_DIR \
  -u PM_FLOW_PROJECT -u PM_FLOW_PROJECT_DIR -u PM_FLOW_REPO_ROOT \
  -u PM_FLOW_ROOT -u PM_FLOW_RUNS_DIR -u PM_FLOW_SECTIONS_DIR \
  -u PM_FLOW_STATE_DIR -u PM_FLOW_STORE -u PM_FLOW_TOPOLOGY \
  PATH="$STUB_BIN:$PATH" PM_FLOW_TOPOLOGY=lean \
  zsh "$FLOW/pm_flow.sh" --project "$PROJECT_KEY" --section alice-arm tick) \
  >/dev/null
(cd "$COMMAND_WORK" && env -u PM_FLOW_ENGINE_ROOT -u PM_FLOW_FLOW_DIR \
  -u PM_FLOW_PROJECT -u PM_FLOW_PROJECT_DIR -u PM_FLOW_REPO_ROOT \
  -u PM_FLOW_ROOT -u PM_FLOW_RUNS_DIR -u PM_FLOW_SECTIONS_DIR \
  -u PM_FLOW_STATE_DIR -u PM_FLOW_STORE -u PM_FLOW_TOPOLOGY \
  PATH="$STUB_BIN:$PATH" PM_FLOW_TOPOLOGY=heavy \
  zsh "$FLOW/pm_flow.sh" --project "$PROJECT_KEY" --section bob-arm tick) \
  >/dev/null

run_keys=("${(@f)$(sqlite3 "$COMPARE_STORE" \
  'SELECT run_key FROM runs ORDER BY id')}")
[[ ${#run_keys[@]} == 2 ]]
compare_report="$(python3 "$FLOW/compare.py" report \
  "${run_keys[1]}" "${run_keys[2]}" --flow "$FLOW" --project "$PROJECT_KEY")"
[[ "$(printf '%s\n' "$compare_report" | grep -c $'^personas\t.*pm=reviewer' || true)" == 2 ]]

python3 - "$COMPARE_STORE" "$CATALOG" "${run_keys[1]}" "${run_keys[2]}" <<'PY'
import json
import sqlite3
import subprocess
import sys


database, catalog, *run_keys = sys.argv[1:]
connection = sqlite3.connect(database)
connection.row_factory = sqlite3.Row
resolved = []
for run_key in run_keys:
    attempt = connection.execute(
        "SELECT a.persona_stack FROM attempts a JOIN runs r ON r.id = a.run_id "
        "WHERE r.run_key = ? AND a.role_key = 'pm' ORDER BY a.id LIMIT 1",
        (run_key,),
    ).fetchone()
    assert attempt is not None, f"run {run_key} has no pm attempt"
    base = next(item for item in json.loads(attempt["persona_stack"])
                if item["layer"] == "base")
    row = connection.execute(
        "SELECT metadata FROM personas WHERE key = ? AND content_hash = ?",
        (base["key"], base["content_hash"]),
    ).fetchone()
    assert row is not None
    card = json.loads(row["metadata"])["card"]
    shown = subprocess.run(
        [sys.executable, catalog, "--db", database, "persona", "show",
         base["key"], "--author", card["author"]],
        check=True, text=True, stdout=subprocess.PIPE,
    ).stdout
    assert f"author: {card['author']}" in shown
    assert f"version: {card['version']}" in shown
    resolved.append((base["key"], base["content_hash"],
                     card["author"], card["version"]))
assert resolved[0][0] == resolved[1][0] == "reviewer"
assert resolved[0][1] != resolved[1][1]
assert resolved[0][2] != resolved[1][2]
assert resolved[0][3] != resolved[1][3]
for item in resolved:
    print("resolved=" + "|".join(item))
print("PASS: real comparison attempts resolve through catalog.py to distinct cards")
PY
print 'PASS: compare report records pm=reviewer on both arms while cards differ'

compare_counts_before="$(dispatch_counts "$COMPARE_STORE")"
[[ "$compare_counts_before" != "0 0" ]]
run_catalog_db "$COMPARE_STORE" persona show reviewer \
  --author 'Alice Example' >/dev/null
compare_counts_after="$(dispatch_counts "$COMPARE_STORE")"
[[ "$compare_counts_after" == "$compare_counts_before" ]] || {
  print -u2 "persona show dispatched: before=$compare_counts_before after=$compare_counts_after"
  exit 1
}
print "PASS: persona show leaves non-zero attempts and spans unchanged ($compare_counts_before -> $compare_counts_after)"

ISOLATED_FLOW="$WORK_DIR/isolated/engine"
ISOLATED_STORE="$WORK_DIR/isolated/catalog.db"
mkdir -p "$ISOLATED_FLOW"
/bin/cp "$CATALOG" "$ROOT/template/.agentic/pm_flow/store.py" "$ISOLATED_FLOW/"
set +e
missing_module="$(env -u PM_FLOW_ENGINE_ROOT -u PM_FLOW_FLOW_DIR \
  -u PM_FLOW_PROJECT -u PM_FLOW_PROJECT_DIR -u PM_FLOW_REPO_ROOT \
  -u PM_FLOW_ROOT -u PM_FLOW_RUNS_DIR -u PM_FLOW_SECTIONS_DIR \
  -u PM_FLOW_STATE_DIR -u PM_FLOW_STORE -u PYTHONPATH \
  python3 -S "$ISOLATED_FLOW/catalog.py" --db "$ISOLATED_STORE" \
  persona add "$CARDED_PACK" 2>&1)"
missing_module_status=$?
set -e
[[ $missing_module_status -ne 0 ]]
[[ "$missing_module" == "persona add: cannot find pm_flow.persona_card to validate persona card" ]]
env -u PM_FLOW_ENGINE_ROOT -u PM_FLOW_FLOW_DIR -u PM_FLOW_PROJECT \
  -u PM_FLOW_PROJECT_DIR -u PM_FLOW_REPO_ROOT -u PM_FLOW_ROOT \
  -u PM_FLOW_RUNS_DIR -u PM_FLOW_SECTIONS_DIR -u PM_FLOW_STATE_DIR \
  -u PM_FLOW_STORE -u PYTHONPATH \
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
