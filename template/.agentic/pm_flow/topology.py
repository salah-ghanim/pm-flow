"""Validate named topology documents and render config overlays."""

from __future__ import annotations

import argparse
import json
import os
import sqlite3
import sys
from pathlib import Path


FALLBACK_MODELS = {
    "claude": [
        "claude-fable-5",
        "claude-opus-5",
        "claude-sonnet-5",
        "claude-haiku-4-5-20251001",
    ],
    "codex": ["gpt-5.6-sol", "gpt-5.1-codex"],
    # Empty lists are deliberately unconstrained, not registries with no valid model.
    "copilot": [],
    "acp": [],
}
DEFAULT_ENGINE = Path(__file__).resolve().parent


class TopologyError(Exception):
    """A topology cannot be used safely."""


def load_json(path: Path, label: str):
    try:
        return json.loads(path.read_text())
    except OSError as error:
        raise TopologyError(f"cannot read {label} at {path}: {error}") from error
    except json.JSONDecodeError as error:
        raise TopologyError(f"invalid JSON in {label} at {path}: {error}") from error


def store_path(flow: Path) -> Path | None:
    named = os.environ.get("PM_FLOW_STORE", "").strip()
    if named:
        return Path(named)
    key_path = flow / ".project-key"
    if not key_path.is_file():
        return None
    try:
        project_key = key_path.read_text().splitlines()[0].strip()
    except (OSError, IndexError):
        return None
    if not project_key:
        return None
    return flow / project_key / "runs" / "pm_flow.db"


def stored_models(flow: Path) -> dict[str, list[str]] | None:
    """Return the reachable registry without creating or migrating a store."""
    path = store_path(flow)
    if path is None or not path.is_file():
        return None
    connection = None
    try:
        connection = sqlite3.connect(f"{path.resolve().as_uri()}?mode=ro", uri=True)
        rows = connection.execute("SELECT key, capabilities FROM clis").fetchall()
        registry = {}
        for key, raw_capabilities in rows:
            capabilities = json.loads(raw_capabilities or "{}")
            models = capabilities.get("models", [])
            if not isinstance(models, list) or not all(
                    isinstance(model, str) for model in models):
                raise ValueError(f"invalid models capability for {key}")
            registry[key] = models
        return registry or None
    except (OSError, sqlite3.Error, ValueError, json.JSONDecodeError):
        return None
    finally:
        if connection is not None:
            connection.close()


def model_registry(flow: Path) -> dict[str, list[str]]:
    return stored_models(flow) or FALLBACK_MODELS


def config_enums(engine: Path) -> tuple[set[str], set[str]]:
    schema_path = engine / "schemas" / "config.schema.json"
    try:
        schema = json.loads(schema_path.read_text())
        seat_properties = schema["$defs"]["seat"]["properties"]
        cli_enum = seat_properties["cli"]["enum"]
        difficulty_enum = seat_properties["difficulty"]["enum"]
        if (
            not isinstance(cli_enum, list)
            or not isinstance(difficulty_enum, list)
            or not all(isinstance(item, str) for item in cli_enum + difficulty_enum)
        ):
            raise TypeError("cli and difficulty enums must contain only strings")
    except (OSError, json.JSONDecodeError, KeyError, TypeError) as error:
        raise TopologyError(
            f"cannot load config schema at {schema_path}: {error}") from error
    return set(cli_enum), set(difficulty_enum)


def load_config(flow: Path) -> dict:
    path = flow / "config.json"
    if not path.is_file():
        raise TopologyError(f"missing agent config: {path}")
    config = load_json(path, "agent config")
    if not isinstance(config, dict):
        raise TopologyError(f"agent config at {path} must be an object")
    if config.get("version") != 1 or isinstance(config.get("version"), bool):
        raise TopologyError(f"unsupported config version: {config.get('version')!r}")
    roles = config.get("roles")
    if not isinstance(roles, dict) or not roles:
        raise TopologyError("config.json defines no roles")
    return config


def load_document(
        key: str, flow: Path, engine: Path = DEFAULT_ENGINE) -> dict:
    flow_path = flow / "topologies" / f"{key}.json"
    engine_path = engine / "topologies" / f"{key}.json"
    path = flow_path if flow_path.is_file() else engine_path
    if not path.is_file():
        raise TopologyError(
            f"topology {key!r} is missing; expected document at {flow_path}; "
            f"also looked at {engine_path}")
    document = load_json(path, f"topology {key!r}")
    if not isinstance(document, dict):
        raise TopologyError(f"topology {key!r} at {path} must be an object")
    if document.get("version") != 1 or isinstance(document.get("version"), bool):
        raise TopologyError(
            f"topology {key!r} has unsupported version: {document.get('version')!r}")
    if document.get("key") != key:
        raise TopologyError(
            f"topology {key!r} has mismatched document key: {document.get('key')!r}")
    roles = document.get("roles")
    if not isinstance(roles, dict) or not roles:
        raise TopologyError(f"topology {key!r} defines no roles")
    return document


def merged_config(
        key: str, flow: Path,
        engine: Path = DEFAULT_ENGINE) -> tuple[dict, dict]:
    config = load_config(flow)
    document = load_document(key, flow, engine)
    merged = dict(config)
    merged_roles = dict(config["roles"])
    merged_roles.update(document["roles"])
    merged["roles"] = merged_roles
    missing = sorted(set(config["roles"]) - set(merged_roles))
    if missing:
        raise TopologyError(
            f"topology {key!r} drops configured role(s): {', '.join(missing)}")
    return document, merged


def domain_definition(
        flow: Path, config: dict,
        engine: Path = DEFAULT_ENGINE) -> tuple[str, dict]:
    domain = config.get("domain") or "generic"
    flow_path = flow / "domains" / f"{domain}.json"
    engine_path = engine / "domains" / f"{domain}.json"
    path = flow_path if flow_path.is_file() else engine_path
    if not path.is_file():
        raise TopologyError(
            f"unknown domain {domain!r}; no definition at {flow_path}; "
            f"also looked at {engine_path}")
    definition = load_json(path, f"domain {domain!r}")
    if not isinstance(definition, dict):
        raise TopologyError(f"domain {domain!r} at {path} must be an object")
    return domain, definition


def validate_binding(
        key: str,
        role: str,
        binding,
        flow: Path,
        domain: str,
        titles: dict,
        registry: dict[str, list[str]],
        check_model: bool,
        engine: Path = DEFAULT_ENGINE,
) -> list[dict]:
    cli_enum, difficulty_enum = config_enums(engine)
    seats = binding if isinstance(binding, list) else [binding]
    if not seats:
        raise TopologyError(f"role {role!r} is an empty panel in topology {key!r}")
    flow_base_persona = flow / "roles" / f"{role}.md"
    flow_domain_persona = flow / "domains" / domain / "roles" / f"{role}.md"
    engine_base_persona = engine / "roles" / f"{role}.md"
    engine_domain_persona = engine / "domains" / domain / "roles" / f"{role}.md"
    persona_paths = (
        flow_base_persona,
        flow_domain_persona,
        engine_base_persona,
        engine_domain_persona,
    )
    if not any(path.is_file() for path in persona_paths):
        raise TopologyError(
            f"role {role!r} has no persona file at {flow_base_persona}"
            f" or {flow_domain_persona}; also looked at {engine_base_persona}"
            f" or {engine_domain_persona}")
    if role not in titles:
        raise TopologyError(f"domain {domain!r} does not define a title for role {role!r}")
    for index, seat in enumerate(seats, start=1):
        if not isinstance(seat, dict):
            raise TopologyError(f"role {role!r} seat {index} has an invalid binding")
        cli = seat.get("cli", "")
        if cli not in cli_enum:
            raise TopologyError(
                f"role {role!r} seat {index} has an unsupported cli: {cli!r}")
        difficulty = seat.get("difficulty", "medium")
        if difficulty not in difficulty_enum:
            raise TopologyError(
                f"role {role!r} seat {index} has an invalid difficulty: {difficulty!r}")
        model = seat.get("model")
        models = registry.get(cli, [])
        if check_model and model not in (None, "") and models and model not in models:
            raise TopologyError(
                f"role {role!r} seat {index} binds cli {cli!r} to unsupported "
                f"model {model!r} in topology {key!r}")
    return seats


def validate(
        key: str, flow: Path,
        engine: Path = DEFAULT_ENGINE) -> tuple[dict, list[str]]:
    document, merged = merged_config(key, flow, engine)
    domain, definition = domain_definition(flow, merged, engine)
    titles = definition.get("titles", {})
    if not isinstance(titles, dict):
        titles = {}
    registry = model_registry(flow)
    summaries = []
    for role in sorted(merged["roles"]):
        seats = validate_binding(
            key, role, merged["roles"][role], flow, domain, titles, registry,
            role in document["roles"], engine)
        descriptions = []
        for index, seat in enumerate(seats, start=1):
            descriptions.append(
                f"seat {index}: cli={seat.get('cli', '')} "
                f"model={seat.get('model') or '(cli default)'} "
                f"difficulty={seat.get('difficulty', 'medium')}")
        summaries.append(f"{role}: seats={len(seats)} " + "; ".join(descriptions))
    return merged, summaries


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command in ("validate", "overlay"):
        subparser = subparsers.add_parser(command)
        subparser.add_argument("key")
        subparser.add_argument("--flow", required=True, type=Path)
        subparser.add_argument("--engine", type=Path, default=DEFAULT_ENGINE)
    subparser = subparsers.add_parser("list")
    subparser.add_argument("--flow", required=True, type=Path)
    subparser.add_argument("--engine", type=Path, default=DEFAULT_ENGINE)
    return parser


def main(argv):
    parser = build_parser()
    args = parser.parse_args(argv[1:])
    try:
        flow = args.flow.resolve()
        engine = args.engine.resolve()
        if args.command == "list":
            documents = {}
            for directory in (engine / "topologies", flow / "topologies"):
                if directory.is_dir():
                    for path in sorted(directory.glob("*.json")):
                        documents[path.stem] = path
            for stem in sorted(documents):
                print(stem)
            return 0
        merged, summaries = validate(args.key, flow, engine)
        if args.command == "validate":
            for summary in summaries:
                print(summary)
        else:
            json.dump(merged, sys.stdout, indent=2)
            print()
        return 0
    except TopologyError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
