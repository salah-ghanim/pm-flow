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
