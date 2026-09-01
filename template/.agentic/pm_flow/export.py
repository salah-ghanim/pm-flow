#!/usr/bin/env python3
"""Parse and validate pm-flow boundary artifacts using only the stdlib."""

import argparse
import json
from pathlib import Path
import re
import sys


SCHEMA_NAMES = {
    "brief": "section_brief.schema.json",
    "handoff": "handoff.schema.json",
    "verdict": "verdict.schema.json",
    "config": "config.schema.json",
    "export": "project_export.schema.json",
}


class SchemaReferenceError(ValueError):
    """A schema reference is invalid or cannot be loaded."""


def _type_matches(value, expected):
    checks = {
        "object": lambda item: isinstance(item, dict),
        "array": lambda item: isinstance(item, list),
        "string": lambda item: isinstance(item, str),
        "integer": lambda item: isinstance(item, int) and not isinstance(item, bool),
        "number": lambda item: isinstance(item, (int, float)) and not isinstance(item, bool),
        "boolean": lambda item: isinstance(item, bool),
        "null": lambda item: item is None,
    }
    try:
        return checks[expected](value)
    except KeyError as error:
        raise ValueError(f"unsupported schema type {expected!r}") from error


def _resolve_reference(reference, root, schema_dir):
    target, separator, fragment = reference.partition("#")
    referenced_root = root
    if target:
        target_path = Path(target)
        if target_path.is_absolute() or ".." in target_path.parts:
            raise SchemaReferenceError(f"invalid schema reference {reference!r}")
        schema_path = schema_dir / target_path
        try:
            referenced_root = json.loads(schema_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise SchemaReferenceError(
                f"cannot load referenced schema at {schema_path}: {error}"
            ) from error

    if not separator or not fragment:
        return referenced_root, referenced_root
    if not fragment.startswith("/"):
        raise SchemaReferenceError(f"unsupported schema reference {reference!r}")

    resolved = referenced_root
    try:
        for raw_key in fragment[1:].split("/"):
            key = raw_key.replace("~1", "/").replace("~0", "~")
            if isinstance(resolved, list):
                resolved = resolved[int(key)]
            else:
                resolved = resolved[key]
    except (IndexError, KeyError, TypeError, ValueError) as error:
        raise SchemaReferenceError(
            f"unresolvable schema pointer {reference!r}"
        ) from error
    return resolved, referenced_root


def validate_schema(payload, schema, path="$", root=None, schema_dir=None):
    """Validate the JSON Schema subset used by the boundary schemas."""
    root = schema if root is None else root
    schema_dir = (
        Path(__file__).resolve().parent / "schemas"
        if schema_dir is None
        else Path(schema_dir)
    )
    try:
        reference = schema.get("$ref")
        if isinstance(reference, str):
            schema, root = _resolve_reference(reference, root, schema_dir)

        expected_type = schema.get("type")
        if expected_type and not _type_matches(payload, expected_type):
            raise ValueError(f"{path} must be of type {expected_type}")

        if "enum" in schema and payload not in schema["enum"]:
            raise ValueError(f"{path} must be one of {schema['enum']}, got {payload!r}")

        if "pattern" in schema:
            if not isinstance(payload, str) or not re.search(schema["pattern"], payload):
                raise ValueError(f"{path} must match pattern {schema['pattern']!r}")

        if isinstance(payload, dict):
            properties = schema.get("properties", {})
            for key in schema.get("required", []):
                if key not in payload:
                    label = properties.get(key, {}).get("title", key)
                    raise ValueError(f"{path}.{label} is required")
            for key, child_schema in properties.items():
                if key in payload:
                    validate_schema(
                        payload[key], child_schema, f"{path}.{key}", root, schema_dir
                    )
            extra_schema = schema.get("additionalProperties")
            if isinstance(extra_schema, dict):
                for key, value in payload.items():
                    if key not in properties:
                        validate_schema(
                            value, extra_schema, f"{path}.{key}", root, schema_dir
                        )

        if isinstance(payload, list):
            if len(payload) < schema.get("minItems", 0):
                raise ValueError(
                    f"{path} must contain at least {schema['minItems']} item(s)"
                )
            item_schema = schema.get("items")
            if item_schema:
                for index, item in enumerate(payload):
                    item_label = item.get("key", index) if isinstance(item, dict) else index
                    validate_schema(
                        item, item_schema, f"{path}[{item_label}]", root, schema_dir
                    )

        if "maximum" in schema and payload > schema["maximum"]:
            raise ValueError(f"{path} must be at most {schema['maximum']}, got {payload}")

        if "oneOf" in schema:
            matches = 0
            errors = []
            for choice in schema["oneOf"]:
                try:
                    validate_schema(payload, choice, path, root, schema_dir)
                    matches += 1
                except SchemaReferenceError:
                    raise
                except ValueError as error:
                    errors.append(str(error))
            if matches != 1:
                detail = "; ".join(errors) if errors else f"matched {matches} alternatives"
                raise ValueError(f"{path} does not match exactly one allowed shape: {detail}")
    except (KeyError, TypeError) as error:
        raise ValueError(f"invalid payload at {path}: {error}") from error
    return payload


def _markdown_sections(text):
    heading_re = re.compile(r"^#{1,6}\s+(.+?)\s*$", re.IGNORECASE)
    sections = {}
    display_names = {}
    current = None
    content = []
    for line in text.splitlines():
        match = heading_re.match(line)
        if match:
            if current is not None and current not in sections:
                sections[current] = "\n".join(content).strip()
            display = match.group(1).strip()
            current = display.casefold()
            display_names.setdefault(current, display)
            content = []
        elif current is not None:
            content.append(line)
    if current is not None and current not in sections:
        sections[current] = "\n".join(content).strip()
    return sections, display_names


def _brief_contract(schema):
    choices = schema["oneOf"]
    headings = []
    for choice in choices:
        for heading in choice["properties"]["headings"]["required"]:
            if heading not in headings:
                headings.append(heading)
    return headings


def parse_brief(text, schema=None):
    """Return headings, Acceptance bullet identifiers, priority, and its loss."""
    schema = schema or _load_schema("brief")
    contract_headings = _brief_contract(schema)
    sections, display_names = _markdown_sections(text)
    canonical = {heading.casefold(): heading for heading in contract_headings}
    headings = {
        canonical.get(key, display_names[key]): sections[key] for key in sections
    }
    acceptance_heading = schema["x-acceptance-heading"].casefold()
    acceptance = sections.get(acceptance_heading, "")
    acceptance_ids = re.findall(r"(?m)^\s*[-*]\s+(.*)$", acceptance)

    priority_value = ""
    priority_heading = schema["x-priority-heading"].casefold()
    for line in sections.get(priority_heading, "").splitlines():
        candidate = re.sub(r"^\s*(?:[-*+]|\d+[.)])\s*", "", line)
        candidate = candidate.strip().strip("`*_ ")
        if candidate:
            priority_value = candidate
            break
    priority_match = re.match(
        r"^(must[\s-]?have|nice[\s-]?to[\s-]?have)\b[\s:,.-]*(.*)$",
        priority_value,
        re.I,
    )
    priority = ""
    priority_loss = ""
    if priority_match:
        priority = (
            "must-have"
            if priority_match.group(1).lower().startswith("must")
            else "nice-to-have"
        )
        priority_loss = priority_match.group(2).strip().strip("`*_ ")

    return {
        "shape": (
            "full"
            if schema["x-full-shape-heading"].casefold() in sections
            else "legacy"
        ),
        "headings": headings,
        "acceptance_ids": acceptance_ids,
        "priority": priority,
        "priority_loss": priority_loss,
    }


def parse_handoff(text, schema=None):
    """Return stable handoff fields plus validate_handoff-compatible budgets."""
    schema = schema or _load_schema("handoff")
    sections, _ = _markdown_sections(text)
    properties = schema["properties"]
    field_headings = {
        field: properties[field]["title"]
        for field in schema["required"]
        if "title" in properties[field]
    }
    result = {}
    for field, heading in field_headings.items():
        key = heading.casefold()
        if key in sections:
            result[field] = sections[key]

    shell_text = text.rstrip("\n") + "\n"
    result["word_count"] = len(shell_text.split())
    result["byte_count"] = len(shell_text.encode("utf-8", errors="replace"))
    return result


def parse_verdict(text, allowed, heading="Decision"):
    """Match markdown_verdict_parse's forgiving presentation rules."""
    allowed = set(allowed)
    heading_re = re.compile(
        r"^[\s>]*"
        r"(?:#{1,6}\s*)?"
        r"(?:\d+[.)]\s*)?"
        r"(?:\*{1,3}|_{1,3})?\s*"
        + re.escape(heading)
        + r"\s*(?:\*{1,3}|_{1,3})?"
        r"\s*(?:[:\-]+[ \t]*(?P<inline>.*?))?\s*$",
        re.IGNORECASE,
    )
    next_heading_re = re.compile(r"^[\s>]*#{1,6}\s+\S")

    def clean(value):
        value = re.sub(r"^[\s>]*", "", value)
        value = re.sub(r"^(?:[-*+]|\d+[.)])\s+", "", value)
        return value.strip().strip("*_` \t")

    lines = text.splitlines()
    sections = []
    index = 0
    while index < len(lines):
        match = heading_re.match(lines[index])
        if not match:
            index += 1
            continue
        values = []
        inline = clean(match.group("inline") or "")
        if inline:
            values.append(inline)
        index += 1
        while index < len(lines):
            line = lines[index]
            if next_heading_re.match(line) or heading_re.match(line):
                break
            candidate = clean(line)
            if candidate:
                values.append(candidate)
            index += 1
        sections.append(values)

    if not sections:
        raise ValueError(f"response has no {heading} section")

    token_re = re.compile(r"^([A-Z][A-Z_]*)\b")
    last_seen = None
    for values in reversed(sections):
        if not values:
            continue
        last_seen = values[0]
        token_match = token_re.match(values[0])
        verdict = token_match.group(1) if token_match else values[0]
        if verdict in allowed:
            return {"heading": heading, "token": verdict, "value_line": values[0]}

    if last_seen is None:
        raise ValueError(f"response {heading} section is empty")
    raise ValueError(
        f"response {heading} must begin with one of {sorted(allowed)}, got {last_seen!r}"
    )


def _load_schema(kind):
    schema_path = Path(__file__).resolve().parent / "schemas" / SCHEMA_NAMES[kind]
    try:
        return json.loads(schema_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"cannot load {kind} schema at {schema_path}: {error}") from error


def _read_text(path, section_key, field):
    try:
        return path.read_text(encoding="utf-8")
    except OSError as error:
        raise ValueError(
            f"section {section_key}.{field} cannot be read at {path}: {error}"
        ) from error


def _first_line(path, section_key, field, default):
    if not path.is_file():
        return default
    lines = _read_text(path, section_key, field).splitlines()
    value = lines[0].strip() if lines else ""
    return value or default


def _nonempty_lines(path, section_key, field):
    return [
        line.strip()
        for line in _read_text(path, section_key, field).splitlines()
        if line.strip()
    ]


def _acceptance_pattern(schema):
    for choice in schema.get("oneOf", []):
        try:
            return choice["properties"]["acceptance_ids"]["items"]["pattern"]
        except KeyError:
            continue
    raise ValueError("brief schema has no acceptance ID pattern")


def _bare_acceptance_id(value, pattern):
    match = re.match(pattern, value)
    if not match:
        return None
    return match.group(0).strip().strip("`:.—- ")


def _acceptance_state(identifier, state_text):
    sections, _ = _markdown_sections(state_text)
    evidence = "\n".join(
        body
        for heading, body in sections.items()
        if heading not in {"blockers", "next eligible task"}
    )
    return "met" if re.search(rf"(?<!\w){re.escape(identifier)}(?!\w)", evidence) else "open"


def emit(flow_dir, project_key):
    export_schema = _load_schema("export")
    brief_schema = _load_schema("brief")
    acceptance_pattern = _acceptance_pattern(brief_schema)
    sections_dir = Path(flow_dir) / project_key / "sections"
    try:
        section_dirs = sorted(
            path
            for path in sections_dir.iterdir()
            if path.is_dir() and not path.name.startswith(".")
        )
    except OSError as error:
        raise ValueError(f"cannot read sections directory at {sections_dir}: {error}") from error

    sections = []
    for section_dir in section_dirs:
        key = section_dir.name
        brief = parse_brief(
            _read_text(section_dir / "brief.md", key, "brief"), brief_schema
        )
        validate_schema(brief, brief_schema, f"section {key}.brief")
        acceptance_ids = []
        for value in brief["acceptance_ids"]:
            identifier = _bare_acceptance_id(value, acceptance_pattern)
            if identifier is not None:
                acceptance_ids.append(identifier)
        state_text = _read_text(section_dir / "state.md", key, "state")
        handoff = parse_handoff(
            _read_text(section_dir / "handoff.md", key, "handoff")
        )
        sections.append(
            {
                "key": key,
                "name": _first_line(section_dir / "name.txt", key, "name", key),
                "status": _first_line(section_dir / "status.txt", key, "status", "unknown"),
                "priority": _first_line(
                    section_dir / "priority.txt", key, "priority", "must-have"
                ),
                "summary": _first_line(
                    section_dir / "summary.txt",
                    key,
                    "summary",
                    "No bounded handoff yet.",
                ),
                "updated_at": _first_line(
                    section_dir / "updated_at.txt", key, "updated_at", "unknown"
                ),
                "owned_paths": _nonempty_lines(
                    section_dir / "owned_paths.txt", key, "owned_paths"
                ),
                "dependencies": _nonempty_lines(
                    section_dir / "dependency_handoffs.txt", key, "dependencies"
                ),
                "acceptance": [
                    {"id": identifier, "state": _acceptance_state(identifier, state_text)}
                    for identifier in acceptance_ids
                ],
                "handoff": handoff,
            }
        )

    payload = {"project": project_key, "sections": sections}
    validate_schema(payload, export_schema, "export")
    return payload


def check(kind, path, allowed_csv=None):
    schema = _load_schema(kind)
    source = Path(path)
    try:
        text = source.read_text(encoding="utf-8")
    except OSError as error:
        raise ValueError(f"cannot read {kind} artifact {source}: {error}") from error

    if kind == "brief":
        payload = parse_brief(text, schema)
    elif kind == "handoff":
        payload = parse_handoff(text, schema)
    elif kind == "verdict":
        if not allowed_csv:
            raise ValueError("verdict check requires --allowed <csv>")
        allowed = [token for token in allowed_csv.split(",") if token]
        if not allowed:
            raise ValueError("verdict --allowed must name at least one token")
        heading = schema.get("x-heading-name", "Decision")
        payload = parse_verdict(text, allowed, heading)
    else:
        try:
            payload = json.loads(text)
        except json.JSONDecodeError as error:
            raise ValueError(f"config JSON is invalid: {error}") from error
    return validate_schema(payload, schema, kind)


def _build_parser():
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    checker = subparsers.add_parser("check", help="validate one boundary artifact")
    checker.add_argument("--kind", choices=tuple(SCHEMA_NAMES), required=True)
    checker.add_argument("--allowed", help="comma-separated verdict tokens")
    checker.add_argument("path")
    verdict = subparsers.add_parser("verdict", help="parse a markdown verdict from stdin")
    verdict.add_argument("--allowed", required=True, help="comma-separated verdict tokens")
    verdict.add_argument("--heading", default="Decision")
    emitter = subparsers.add_parser("emit", help="emit a validated project export")
    emitter.add_argument("--json", action="store_true", required=True)
    emitter.add_argument("flow_dir")
    emitter.add_argument("project_key")
    return parser


def main(argv=None):
    args = _build_parser().parse_args(argv)
    if args.command == "check":
        try:
            check(args.kind, args.path, args.allowed)
        except (ValueError, TypeError, KeyError) as error:
            print(f"{args.kind} check failed: {error}", file=sys.stderr)
            return 1
        return 0
    if args.command == "verdict":
        try:
            allowed = [token for token in args.allowed.split(",") if token]
            if not allowed:
                raise ValueError("verdict --allowed must name at least one token")
            parsed = parse_verdict(sys.stdin.read(), allowed, args.heading)
        except (ValueError, TypeError, KeyError) as error:
            print(error, file=sys.stderr)
            return 1
        print(parsed["token"])
        print(parsed["value_line"])
        return 0
    if args.command == "emit":
        try:
            payload = emit(args.flow_dir, args.project_key)
        except (ValueError, TypeError, KeyError) as error:
            print(f"export failed: {error}", file=sys.stderr)
            return 1
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
