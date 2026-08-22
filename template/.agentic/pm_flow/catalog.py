#!/usr/bin/env python3
"""Index the definitions, and project them back out as markdown.

Definitions - who an agent is, what rules bind it, how a topology is arranged -
are markdown and JSON on disk. This module reads them into the store so they can
be queried and joined against the record of what actually happened, and writes
them back out as a linked markdown vault so they can be read and edited in a
graph editor.

Two directions, and they are not symmetrical:

    sync       disk -> store.  The files are the truth. Definitions are
                              content-addressed, so re-syncing an unchanged file
                              is a no-op and editing one produces a new version
                              rather than mutating the old, which is what makes
                              a result attributable to an exact definition.

    export-md  store -> vault. A rendering, safe to delete and regenerate,
                              carrying [[wikilinks]] so the arrangement is a
                              graph rather than a pile of documents.

The vault is where a visual editor would eventually read and write. Nothing here
assumes one exists; the markdown is useful on its own.

Standard library only.
"""

from __future__ import annotations

import argparse
import contextlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import store  # noqa: E402

# The shape of the flow as the driver actually runs it. Seeded so a fresh
# topology is the real arrangement rather than an empty graph waiting to be
# drawn; once it is in the store it is data, and editing it is the point.
DEFAULT_EDGES = [
    ("cpo", "pm", "assigns"),
    ("pm", "developer", "assigns"),
    ("pm", "developer", "reviews"),
    ("developer", "consultant", "escalates_to"),
    ("consultant", "cpo", "adjudicates"),
    ("cpo", "10x_developer", "assigns"),
    ("pm", "10x_developer", "reviews"),
    ("pm", "cpo", "escalates_to"),
]

FRONTMATTER = re.compile(r"\A---\r?\n(.*?)\r?\n---\r?\n?", re.S)


def split_frontmatter(text: str):
    """A very small YAML-ish frontmatter reader.

    Deliberately not a YAML parser: the frontmatter this writes and reads is
    flat scalars and simple lists, and taking a dependency to parse six keys
    would be a poor trade.
    """
    match = FRONTMATTER.match(text or "")
    if not match:
        return {}, text or ""
    meta = {}
    for line in match.group(1).splitlines():
        line = line.strip()
        if not line or line.startswith("#") or ":" not in line:
            continue
        key, _, value = line.partition(":")
        value = value.strip().strip('"').strip("'")
        if value.startswith("[") and value.endswith("]"):
            inner = value[1:-1].strip()
            meta[key.strip()] = [
                item.strip().strip('"').strip("'")
                for item in inner.split(",") if item.strip()
            ] if inner else []
        else:
            meta[key.strip()] = value
    return meta, text[match.end():]


def yaml_scalar(value) -> str:
    if isinstance(value, bool):
        # Python's True/False are not YAML's, and a graph editor reading the
        # frontmatter would see a string where it expected a boolean.
        return "true" if value else "false"
    if isinstance(value, list):
        return "[" + ", ".join(f'"{item}"' for item in value) + "]"
    if value is None:
        return '""'
    text = str(value)
    if text == "" or any(ch in text for ch in ':#"\n'):
        return json.dumps(text)
    return text


def frontmatter_block(meta: dict) -> str:
    lines = ["---"]
    for key, value in meta.items():
        if value is None or value == "":
            continue
        lines.append(f"{key}: {yaml_scalar(value)}")
    lines.append("---")
    return "\n".join(lines) + "\n"


# --------------------------------------------------------------- disk -> store

def persona_digest(key, layer, body) -> str:
    """A persona's identity: its key, its layer, its exact words."""
    return store.content_hash(key, layer, body)


def find_persona(connection, key, digest):
    """The row for this exact wording, or None.

    The whole row rather than the id, because adopting a persona into a pack
    has to know what provenance it already carries.
    """
    return connection.execute(
        "SELECT * FROM personas WHERE key = ? AND content_hash = ?", (key, digest)
    ).fetchone()


def insert_persona(connection, *, key, title, summary, body, layer, digest,
                   source_path, author=None, license=None, source_url=None,
                   version=None, tags=None, extends_id=None, pack_id=None,
                   metadata=None) -> int:
    """The bare insert. The caller owns the transaction, because installing a
    pack has to land its pack row and all of its personas in one commit."""
    cursor = connection.execute(
        "INSERT INTO personas (key, title, summary, body, layer, extends_id,"
        " pack_id, author, license, source_url, version, tags, metadata,"
        " content_hash, source_path, created_at)"
        " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (key, title, summary, body, layer, extends_id, pack_id, author, license,
         source_url, version, store.dumps(tags or []),
         store.dumps(metadata or {}), digest, source_path, store.now()),
    )
    return cursor.lastrowid


def upsert_persona(connection, *, key, title, summary, body, layer,
                   source_path, author=None, license=None, source_url=None,
                   version=None, tags=None, extends_id=None, pack_id=None) -> int:
    """A persona, identified by its content.

    Re-reading an unchanged prompt returns the same row; editing one produces a
    new version rather than mutating the old. That is what makes a measured
    result attributable to exact wording.
    """
    digest = persona_digest(key, layer, body)
    found = find_persona(connection, key, digest)
    if found is not None:
        return found["id"]
    with connection:
        return insert_persona(
            connection, key=key, title=title, summary=summary, body=body,
            layer=layer, digest=digest, source_path=source_path, author=author,
            license=license, source_url=source_url, version=version, tags=tags,
            extends_id=extends_id, pack_id=pack_id,
        )


def upsert_binding(connection, *, key, cli, model, thinking, access,
                   cli_params) -> int:
    """The local half: which backend actually runs a persona."""
    digest = store.content_hash(key, cli, model, thinking, access,
                                store.dumps(cli_params))
    row = connection.execute(
        "SELECT id FROM bindings WHERE key = ? AND content_hash = ?", (key, digest)
    ).fetchone()
    if row:
        return row["id"]
    with connection:
        cursor = connection.execute(
            "INSERT INTO bindings (key, cli, model, thinking_level, access_tier,"
            " cli_params, content_hash, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (key, cli, model, thinking, access, store.dumps(cli_params), digest,
             store.now()),
        )
        return cursor.lastrowid


def upsert_rule(connection, *, key, title, kind, body, source_path) -> int:
    digest = store.content_hash(key, kind, body)
    row = connection.execute(
        "SELECT id FROM rules WHERE key = ? AND content_hash = ?", (key, digest)
    ).fetchone()
    if row:
        return row["id"]
    with connection:
        cursor = connection.execute(
            "INSERT INTO rules (key, title, kind, body, metadata, content_hash,"
            " source_path, created_at) VALUES (?, ?, ?, ?, '{}', ?, ?, ?)",
            (key, title, kind, body, digest, source_path, store.now()),
        )
        return cursor.lastrowid


def bind_rule(connection, rule_id, scope_type, scope_id, ordering=0):
    with connection:
        connection.execute(
            "INSERT OR IGNORE INTO rule_bindings (rule_id, scope_type, scope_id, ordering)"
            " VALUES (?, ?, ?, ?)",
            (rule_id, scope_type, scope_id, ordering),
        )


def register_clis(connection):
    """What each backend can do, as data.

    These are not preferences. They are the observed differences the exporter
    and the recorder have to compensate for: where token counts can be read
    from, whether an inbound traceparent is honoured, and whether the CLI's own
    telemetry says anything a GenAI-aware backend can use.
    """
    known = {
        "claude": {
            "display_name": "Claude Code",
            "thinking_levels": {"low": "low", "medium": "medium", "high": "high",
                                "xhigh": "xhigh", "max": "max"},
            "capabilities": {
                "usage_source": "response_envelope",
                "reports_cost": True,
                "accepts_traceparent": True,
                "emits_gen_ai_semconv": True,
                "scoped_write": True,
            },
        },
        "codex": {
            "display_name": "Codex CLI",
            # codex exposes three levels, so the top two collapse.
            "thinking_levels": {"low": "low", "medium": "medium", "high": "high",
                                "xhigh": "high", "max": "high"},
            "capabilities": {
                # Its response file holds only the last message, so usage has to
                # come out of the JSONL event stream instead.
                "usage_source": "jsonl_events",
                "reports_cost": False,
                "accepts_traceparent": True,
                # Emits OTLP under a private codex.* schema with no gen_ai.*
                # attributes, much of it log-only. pm-flow describes the call.
                "emits_gen_ai_semconv": False,
                "scoped_write": False,
            },
        },
        "copilot": {
            "display_name": "GitHub Copilot CLI",
            "thinking_levels": {"low": "low", "medium": "medium", "high": "high",
                                "xhigh": "xhigh", "max": "max"},
            "capabilities": {
                "usage_source": None,
                "reports_cost": False,
                "accepts_traceparent": False,
                "emits_gen_ai_semconv": False,
                "scoped_write": False,
            },
        },
    }
    with connection:
        for key, spec in known.items():
            connection.execute(
                "INSERT OR REPLACE INTO clis"
                " (key, display_name, exec_name, thinking_levels, capabilities, default_params)"
                " VALUES (?, ?, ?, ?, ?, COALESCE((SELECT default_params FROM clis WHERE key = ?), '{}'))",
                (key, spec["display_name"], key,
                 store.dumps(spec["thinking_levels"]),
                 store.dumps(spec["capabilities"]), key),
            )


def read_persona_layers(engine_dir: Path, role: str, domain: str,
                        project_dir: Path | None = None, project_key: str = ""):
    """The persona layers on disk for one role, base first.

    The flow already stores prompts this way - a craft persona in `roles/`, an
    optional domain overlay in `domains/<domain>/roles/` - it just never treated
    the two as separately addressable things. They are exactly a base layer and
    a domain layer, so they are read as such.

    The third layer is the repository's own. It lives under the project
    workspace, never inside the engine, so customising a role is adding a file
    to your own repository rather than editing a packaged one - which is what
    makes upgrading the package a no-op for anything you wrote.

    This is the single definition of what a seat is made of. Both the prompt
    that goes to the CLI and the provenance recorded against the attempt are
    built from it, so the two cannot disagree about which layers were applied
    or in what order.
    """
    layers = []
    base = engine_dir / "roles" / f"{role}.md"
    if base.is_file():
        layers.append(("base", role, base.read_text(errors="replace"), str(base)))
    if domain:
        overlay = engine_dir / "domains" / domain / "roles" / f"{role}.md"
        if overlay.is_file():
            layers.append(("domain", f"{domain}/{role}",
                           overlay.read_text(errors="replace"), str(overlay)))
    if project_dir is not None:
        local = Path(project_dir) / "roles" / f"{role}.md"
        if local.is_file():
            layers.append(("style", f"{project_key or 'local'}/{role}",
                           local.read_text(errors="replace"), str(local)))
    return layers


def sync(connection, flow_dir: Path, project_key: str, domain: str,
         topology_key: str, engine_dir: Path | None = None) -> dict:
    """Read the flow directory into the store. Idempotent.

    Two roots, because installed they are two directories: `flow_dir` is the
    repository's project data - config.json, the project workspace, the local
    persona overlays - and `engine_dir` is the packaged defaults. They default
    to the same path, which is the copied layout.
    """
    register_clis(connection)
    engine_dir = Path(engine_dir) if engine_dir else flow_dir

    config_path = flow_dir / "config.json"
    config = {}
    if config_path.is_file():
        try:
            config = json.loads(config_path.read_text())
        except ValueError:
            config = {}

    access = config.get("access") or {}
    write_roles = set(access.get("write_roles") or ["developer", "10x_developer"])
    scoped_roles = set(access.get("scoped_roles") or ["pm", "cpo"])

    # -- project
    with connection:
        connection.execute(
            "INSERT OR IGNORE INTO projects (key, name, domain, created_at)"
            " VALUES (?, ?, ?, ?)",
            (project_key, project_key, domain, store.now()),
        )
        connection.execute(
            "UPDATE projects SET domain = COALESCE(?, domain) WHERE key = ?",
            (domain, project_key),
        )
    project_id = connection.execute(
        "SELECT id FROM projects WHERE key = ?", (project_key,)
    ).fetchone()["id"]

    # -- topology
    with connection:
        connection.execute(
            "INSERT OR IGNORE INTO topologies (key, name, project_id, domain, created_at)"
            " VALUES (?, ?, ?, ?, ?)",
            (topology_key, topology_key, project_id, domain, store.now()),
        )
    topology_id = connection.execute(
        "SELECT id FROM topologies WHERE key = ? AND project_id IS ?",
        (topology_key, project_id),
    ).fetchone()["id"]

    # -- agents, one row per seat
    counts = {"personas": 0, "bindings": 0, "rules": 0, "seats": 0, "edges": 0}
    roles = config.get("roles") or {}
    project_dir = flow_dir / project_key
    for role_key, binding in sorted(roles.items()):
        seats = binding if isinstance(binding, list) else [binding]
        layers = read_persona_layers(engine_dir, role_key, domain,
                                     project_dir, project_key)
        tier = ("write" if role_key in write_roles
                else "scoped" if role_key in scoped_roles else "read")

        persona_ids = []
        extends = None
        for layer, layer_key, body, path in layers:
            persona_id = upsert_persona(
                connection, key=layer_key,
                title=role_key.replace("_", " ").title(),
                summary=f"{layer} persona for {role_key}",
                body=body, layer=layer, source_path=path, extends_id=extends,
                tags=[role_key] + ([domain] if layer == "domain" else []),
            )
            persona_ids.append(persona_id)
            extends = persona_id
            counts["personas"] += 1

        for index, seat_binding in enumerate(seats, start=1):
            if not isinstance(seat_binding, dict):
                continue
            cli_params = {
                key: value for key, value in seat_binding.items()
                if key not in ("cli", "model", "difficulty")
            }
            binding_id = upsert_binding(
                connection, key=f"{role_key}.{index}",
                cli=seat_binding.get("cli"), model=seat_binding.get("model"),
                thinking=seat_binding.get("difficulty"), access=tier,
                cli_params=cli_params,
            )
            counts["bindings"] += 1
            with connection:
                connection.execute(
                    "INSERT OR REPLACE INTO topology_agents"
                    " (topology_id, role_key, persona_id, binding_id, seat, ordering, overrides)"
                    " VALUES (?, ?, ?, ?, ?, ?, '{}')",
                    (topology_id, role_key, persona_ids[-1] if persona_ids else None,
                     binding_id, index, index),
                )
            seat_row = connection.execute(
                "SELECT id FROM topology_agents WHERE topology_id = ? AND role_key = ?"
                " AND seat = ?", (topology_id, role_key, index),
            ).fetchone()
            if seat_row:
                with connection:
                    for order, persona_id in enumerate(persona_ids):
                        connection.execute(
                            "INSERT OR IGNORE INTO seat_personas"
                            " (topology_agent_id, persona_id, ordering) VALUES (?, ?, ?)",
                            (seat_row["id"], persona_id, order),
                        )
            counts["seats"] += 1

            # The access tier as tool grants, so what an agent may reach for is
            # queryable rather than buried in the dispatcher.
            grants = []
            if tier == "write":
                grants = [("Edit", "**", "allow"), ("Write", "**", "allow"),
                          ("Bash", "*", "allow")]
            elif tier == "scoped":
                grants = [("Edit", "<project>/**", "allow")]
                grants += [("Bash", prefix, "allow")
                           for prefix in (access.get("scoped_bash") or [])[:64]]
                for pattern in access.get("audit_deny_paths") or []:
                    if role_key in set(access.get("audit_deny_roles") or ["cpo"]):
                        grants.append(("Edit", pattern, "deny"))
            else:
                grants = [("Read", "**", "allow")]
            with connection:
                for tool, pattern, mode in grants:
                    connection.execute(
                        "INSERT OR IGNORE INTO tool_grants"
                        " (binding_id, tool, pattern, mode) VALUES (?, ?, ?, ?)",
                        (binding_id, tool, pattern, mode),
                    )

    # -- rules: the contract binds the project, the task procedures the topology
    contract = project_dir / "task_contract.md"
    if not contract.is_file():
        contract = engine_dir / "project" / "task_contract.md"
    if contract.is_file():
        rule_id = upsert_rule(
            connection, key="task_contract", title="Task contract", kind="contract",
            body=contract.read_text(errors="replace"), source_path=str(contract),
        )
        bind_rule(connection, rule_id, "project", project_id)
        counts["rules"] += 1

    task_dirs = [engine_dir / "tasks"]
    if domain:
        task_dirs.insert(0, engine_dir / "domains" / domain / "tasks")
    seen_tasks = set()
    for task_dir in task_dirs:
        if not task_dir.is_dir():
            continue
        for path in sorted(task_dir.glob("*.md")):
            if path.stem in seen_tasks:
                continue
            seen_tasks.add(path.stem)
            rule_id = upsert_rule(
                connection, key=path.stem,
                title=path.stem.replace("_", " ").title(), kind="procedure",
                body=path.read_text(errors="replace"), source_path=str(path),
            )
            bind_rule(connection, rule_id, "topology", topology_id)
            counts["rules"] += 1

    # -- edges, only between roles this topology actually has
    present = {
        row["role_key"] for row in connection.execute(
            "SELECT DISTINCT role_key FROM topology_agents WHERE topology_id = ?",
            (topology_id,),
        )
    }
    with connection:
        for from_role, to_role, kind in DEFAULT_EDGES:
            if from_role in present and to_role in present:
                connection.execute(
                    "INSERT OR IGNORE INTO topology_edges"
                    " (topology_id, from_role, to_role, kind) VALUES (?, ?, ?, ?)",
                    (topology_id, from_role, to_role, kind),
                )
                counts["edges"] += 1

    return counts


# ------------------------------------------------------------- persona packs
#
# A pack is a directory of markdown personas plus one JSON index. That is the
# whole format: publishing one is pushing a repository, and installing one
# copies nothing but text into the store. JSON for the index rather than more
# frontmatter, because the frontmatter reader above is deliberately small and a
# manifest is the wrong reason to grow it into a YAML parser.
#
# Installing must never run anything from a pack. Nothing here imports or
# executes, and nothing here even reads a file the index does not name.

PACK_MANIFEST = "persona-pack.json"

PERSONA_LAYERS = ("base", "domain", "task", "style")

# The local half an agent gets on arrival: which backend runs it, at what tier,
# with what tools. A pack carrying these is neither portable nor safe to
# install, so they are refused rather than dropped - a silently ignored model
# name still misleads the person who wrote it.
FORBIDDEN_KEYS = frozenset({
    "cli", "clis", "exec", "exec_name", "command", "argv", "entrypoint",
    "model", "models", "thinking_level", "difficulty",
    "binding", "bindings", "access", "access_tier", "tier", "permissions",
    "tool", "tools", "tool_grant", "tool_grants", "allowed_tools",
    "disallowed_tools", "mcp_servers",
})

PERSONA_ENTRY_KEYS = frozenset({"key", "file", "layer", "title", "summary", "tags"})


class PackError(Exception):
    """A pack that will not be installed, and the reason why."""


def _required_text(value, field) -> str:
    if not isinstance(value, str) or not value.strip():
        raise PackError(f"{field} must be a non-empty string")
    return value.strip()


def _optional_text(value):
    return value.strip() if isinstance(value, str) and value.strip() else None


def _tag_list(value, field):
    if value is None:
        return []
    if isinstance(value, str):
        value = [value] if value.strip() else []
    if not isinstance(value, list) or any(not isinstance(t, str) for t in value):
        raise PackError(f"{field} must be a list of strings")
    return [t.strip() for t in value if t.strip()]


def reject_local_fields(value, where, path="") -> None:
    """Refuse machine-local metadata anywhere in a pack, at any depth.

    Nested rather than top-level only, because burying a model name one level
    down inside a persona entry is exactly how it would arrive.
    """
    if isinstance(value, dict):
        for key, item in value.items():
            normalised = str(key).strip().lower().replace("-", "_")
            if normalised in FORBIDDEN_KEYS:
                at = f" at {path}" if path else ""
                raise PackError(
                    f"{where} carries machine-local field '{key}'{at}: a persona "
                    "names no cli, model, binding, access tier or tool grant")
            reject_local_fields(item, where, f"{path}.{key}" if path else str(key))
    elif isinstance(value, list):
        for index, item in enumerate(value):
            reject_local_fields(item, where, f"{path}[{index}]")


def resolve_inside(root: Path, relative) -> Path:
    """A pack may only index files it contains.

    Resolved rather than merely joined, so a symlink pointing out of the pack is
    caught instead of followed.
    """
    if not isinstance(relative, str) or not relative.strip():
        raise PackError("persona file must be a non-empty pack-relative path")
    candidate = Path(relative)
    if candidate.is_absolute() or ".." in candidate.parts:
        raise PackError(f"persona file '{relative}' must stay inside the pack")
    resolved = (root / candidate).resolve()
    if root not in resolved.parents:
        raise PackError(f"persona file '{relative}' resolves outside the pack")
    if resolved.suffix.lower() != ".md":
        raise PackError(f"persona file '{relative}' must be a .md file")
    if not resolved.is_file():
        raise PackError(f"persona file '{relative}' is missing")
    return resolved


def read_pack(path) -> dict:
    """Validate a pack completely, and return what installing it needs.

    Everything a pack can be wrong about is decided here, before the store is
    opened: a pack that fails halfway through validation must leave the store
    exactly as it was, and the cheapest way to guarantee that is to have written
    nothing yet.
    """
    root = Path(path).expanduser()
    if root.is_file() and root.name == PACK_MANIFEST:
        root = root.parent
    root = root.resolve()
    if not root.is_dir():
        raise PackError(f"{path} is not a pack directory")
    manifest_path = root / PACK_MANIFEST
    if not manifest_path.is_file():
        raise PackError(f"no {PACK_MANIFEST} in {root}")
    try:
        manifest = json.loads(manifest_path.read_text(errors="replace"))
    except ValueError as error:
        raise PackError(f"{PACK_MANIFEST} is not valid JSON: {error}")
    if not isinstance(manifest, dict):
        raise PackError(f"{PACK_MANIFEST} must be a JSON object")
    reject_local_fields(manifest, PACK_MANIFEST)

    name = _required_text(manifest.get("name"), "name")
    author = _required_text(manifest.get("author"), "author")
    licence = _required_text(manifest.get("license"), "license")
    version = _required_text(manifest.get("version"), "version")
    if "tags" not in manifest:
        raise PackError("tags is required; use [] for none")
    pack_tags = _tag_list(manifest.get("tags"), "tags")
    entries = manifest.get("personas")
    if not isinstance(entries, list) or not entries:
        raise PackError("personas must be a non-empty list")

    personas = []
    seen = set()
    for index, entry in enumerate(entries):
        field = f"personas[{index}]"
        if not isinstance(entry, dict):
            raise PackError(f"{field} must be an object")
        unknown = set(entry) - PERSONA_ENTRY_KEYS
        if unknown:
            raise PackError(f"{field} has unsupported field(s): "
                            + ", ".join(sorted(str(u) for u in unknown)))
        key = _required_text(entry.get("key"), f"{field}.key")
        if key in seen:
            raise PackError(f"duplicate persona key '{key}'")
        seen.add(key)
        layer = _required_text(entry.get("layer"), f"{field}.layer")
        if layer not in PERSONA_LAYERS:
            raise PackError(f"{field}.layer '{layer}' is not one of "
                            + ", ".join(PERSONA_LAYERS))
        file_path = resolve_inside(root, entry.get("file"))
        meta, body = split_frontmatter(file_path.read_text(errors="replace"))
        reject_local_fields(meta, f"{entry.get('file')} frontmatter")
        if not body.strip():
            raise PackError(f"{field} file '{entry.get('file')}' has no prompt body")
        tags = []
        for tag in (pack_tags + _tag_list(entry.get("tags"), f"{field}.tags")
                    + _tag_list(meta.get("tags"), f"{field} frontmatter tags")):
            if tag not in tags:
                tags.append(tag)
        personas.append({
            "key": key,
            "layer": layer,
            "title": _optional_text(entry.get("title")) or _optional_text(meta.get("title")) or key,
            "summary": _optional_text(entry.get("summary")) or _optional_text(meta.get("summary")),
            "body": body.strip(),
            "tags": tags,
            "source_path": str(file_path),
            # Where the file sits inside the pack, which stays true however the
            # pack itself was obtained.
            "relative_path": str(file_path.relative_to(root)),
        })

    return {
        "root": root, "name": name, "author": author, "license": licence,
        "version": version, "tags": pack_tags,
        "description": _optional_text(manifest.get("description")),
        "manifest": manifest, "personas": personas,
    }


# ------------------------------------------------------- packs from a git URL
#
# A pack is a git repository, so installing from a URL is a clone followed by
# exactly the local install above. The clone is scaffolding: it is validated,
# installed and then deleted, and what is kept is the URL the caller gave plus
# the commit that was installed. The checkout path is never provenance - it does
# not exist by the time anyone reads the store back.
#
# Nothing from the repository is executed. Git runs as a real argv and never
# through a shell, so nothing in a URL is interpolated; the transports that can
# spawn a command are refused; hooks are pointed away; and the only thing read
# afterwards is the text the manifest names.

GIT_URL_SCHEMES = ("https://", "http://", "ssh://", "git://", "git+ssh://",
                   "file://")

# scp-like remotes (git@host:owner/pack.git) carry no scheme at all.
SCP_LIKE_URL = re.compile(r"\A[\w.+-]+@[\w.-]+:[^\s:]+\Z")

# ext:: runs an arbitrary command as a transport, so the allowed set is the
# transports that only move bytes.
GIT_TRANSPORTS = "file:git:http:https:ssh"


def looks_like_git_url(spec) -> bool:
    """Whether to clone this or read it off disk.

    An existing path wins: a directory named like a URL is not a remote, and
    local installation must keep behaving exactly as it did.
    """
    text = str(spec).strip()
    if Path(text).expanduser().exists():
        return False
    return text.startswith(GIT_URL_SCHEMES) or bool(SCP_LIKE_URL.match(text))


def run_git(arguments, cwd=None) -> str:
    """Git as a real process with a real argv.

    No shell, so a URL is an argument rather than a fragment of a command line.
    The clone also cannot stop to ask a question it would then hang on.
    """
    environment = dict(os.environ)
    environment["GIT_TERMINAL_PROMPT"] = "0"
    environment["GIT_ALLOW_PROTOCOL"] = GIT_TRANSPORTS
    try:
        done = subprocess.run(
            ["git", "-c", "protocol.ext.allow=never",
             "-c", "core.hooksPath=/dev/null", *arguments],
            cwd=cwd, env=environment, stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
    except OSError as error:
        raise PackError(f"could not run git: {error}")
    if done.returncode != 0:
        raise PackError(done.stderr.strip() or done.stdout.strip()
                        or f"git exited {done.returncode}")
    return done.stdout.strip()


@contextlib.contextmanager
def git_checkout(url: str):
    """Clone a pack repository into a checkout that outlives nothing.

    Shallow, because installing a pack needs the tree at one commit and not the
    history behind it, and this is not a cache: the directory goes away on the
    way out whether the install succeeded or failed.
    """
    directory = tempfile.mkdtemp(prefix="pm-flow-pack-")
    try:
        try:
            run_git(["clone", "--quiet", "--depth", "1", "--no-tags",
                     "--", url, directory])
            commit = run_git(["rev-parse", "HEAD"], cwd=directory)
        except PackError as error:
            # Git names the checkout it failed in. That path is about to stop
            # existing, so it is noise in the message rather than information.
            raise PackError(f"could not fetch {url}: "
                            + str(error).replace(directory, "<checkout>"))
        yield Path(directory).resolve(), commit
    finally:
        shutil.rmtree(directory, ignore_errors=True)


def read_pack_from_url(url: str, directory: Path, commit: str) -> dict:
    """The validated pack, carrying the caller's URL and the exact commit.

    read_pack is untouched and remains the only thing that decides whether a
    pack is acceptable. This records where it came from, and rewrites each
    persona's source path to its place inside the pack, so that no part of the
    temporary checkout survives into the store.
    """
    pack = read_pack(directory)
    pack["source_url"] = url.strip()
    pack["ref"] = commit
    for spec in pack["personas"]:
        spec["source_path"] = spec["relative_path"]
    return pack


PACK_PROVENANCE = ("pack_id", "author", "license", "source_url", "version",
                   "tags", "metadata", "source_path", "title", "summary")

# Where a persona row records the commit it was installed from.
GIT_COMMIT_KEY = "git_commit"


def persona_git_metadata(pack, existing=None) -> dict:
    """The commit one persona version came from, kept on that version.

    `persona_packs.ref` is the pack's *current* commit and moves forward every
    time the pack is re-added, so it can only ever describe the newest version.
    A superseded version still has to be able to say where its words came from,
    or every measurement recorded against it loses its source. The persona row
    already carries a metadata blob, so the commit goes there: one commit per
    version, alongside the source URL the row already keeps.

    A commit already recorded is never rewritten. A row is found by its exact
    words, so a row that is still here is a version that has not changed, and
    the commit that first published those words has not changed either.
    """
    metadata = dict(existing) if isinstance(existing, dict) else {}
    ref = pack.get("ref")
    if ref and not metadata.get(GIT_COMMIT_KEY):
        metadata[GIT_COMMIT_KEY] = ref
    return metadata


def persona_commit(raw_metadata):
    """The commit recorded on a persona row, or None."""
    metadata = store.loads(raw_metadata)
    return metadata.get(GIT_COMMIT_KEY) if isinstance(metadata, dict) else None


def adopt_persona(connection, row, spec, pack, pack_id, source) -> bool:
    """Bring a persona the store already holds into the pack that ships it.

    The same words may already be here as a standalone persona - written by
    hand, or installed before this pack existed. Inserting a second row would
    duplicate an identity that is defined by its content, and every measurement
    already recorded against the old row would keep pointing at a persona that
    belongs to no pack. So the row keeps its id and gains the pack's provenance.

    Only provenance is touched. Key, layer, body and content hash are the
    identity, and are the same by construction: this row was found by them. The
    commit inside the metadata is provenance the row may already hold, so it is
    carried rather than replaced - see `persona_git_metadata`.

    Returns whether anything actually changed, so re-adding an unchanged pack
    stays a reported no-op rather than announcing work it did not do.
    """
    wanted = {
        "pack_id": pack_id,
        "author": pack["author"],
        "license": pack["license"],
        "source_url": source,
        "version": pack["version"],
        "tags": store.dumps(spec["tags"]),
        "metadata": store.dumps(
            persona_git_metadata(pack, store.loads(row["metadata"]))),
        "source_path": spec["source_path"],
        "title": spec["title"],
        "summary": spec["summary"],
    }
    if all(row[column] == wanted[column] for column in PACK_PROVENANCE):
        return False
    connection.execute(
        "UPDATE personas SET "
        + ", ".join(f"{column} = ?" for column in PACK_PROVENANCE)
        + " WHERE id = ?",
        [wanted[column] for column in PACK_PROVENANCE] + [row["id"]],
    )
    return True


def reject_cross_pack_claim(connection, row, spec, pack, pack_id) -> None:
    """Refuse to move a persona away from the pack that already owns it.

    Adoption above is for a persona that belongs to no pack: it has no pack
    provenance to lose, so gaining this pack's is a strict improvement. A
    persona another pack already ships is a different case. Two packs are
    separate publications that happen to contain the same words, and silently
    re-attributing the row would rewrite the first pack's author, licence,
    version and source - while every measurement recorded against that row
    stays, now filed under a pack that never published it.

    Identical content is not a merge signal, so the second pack is refused
    whole rather than partly applied. The caller's transaction is what makes
    that atomic; this only decides, and says which persona collided with whom.
    """
    if row["pack_id"] is None or row["pack_id"] == pack_id:
        return
    owner = connection.execute(
        "SELECT name FROM persona_packs WHERE id = ?", (row["pack_id"],)
    ).fetchone()
    owner_name = owner["name"] if owner else f"pack id {row['pack_id']}"
    raise PackError(
        f"persona '{spec['key']}' is identical to one already installed from "
        f"pack '{owner_name}', which keeps it along with everything measured "
        f"about it; pack '{pack['name']}' was not installed. Give the persona "
        f"a different key, change its words so it is a distinct persona, or "
        f"remove '{owner_name}' first."
    )


def install_pack(connection, pack: dict) -> dict:
    """Record the pack and its personas in one commit.

    The pack row carries the manifest verbatim and the resolved source it came
    from, so a borrowed persona can say where it is from and be updated from
    there later. The personas themselves are content-addressed as always, which
    is what makes re-adding an unchanged pack a no-op.

    Updating from source is therefore the same command again rather than a new
    one: re-adding a URL whose prompts have moved on inserts the new wording as
    a further version, while the version that was measured stays exactly as it
    was - same row, same words, same commit, same id for everything already
    recorded against it.
    """
    # A pack fetched from a URL is provenance in the caller's terms: the URL
    # they gave and the commit that was installed. A local pack keeps the path
    # it was read from, and has no ref to record.
    source = pack.get("source_url") or str(pack["root"])
    ref = pack.get("ref")
    installed, updated, adopted, unchanged = [], [], [], []
    if connection.in_transaction:
        connection.commit()
    connection.execute("BEGIN IMMEDIATE")
    try:
        connection.execute(
            "INSERT INTO persona_packs (name, source_url, ref, author, license,"
            " description, manifest, installed_at)"
            " VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
            " ON CONFLICT(name) DO UPDATE SET source_url = excluded.source_url,"
            " ref = excluded.ref,"
            " author = excluded.author, license = excluded.license,"
            " description = excluded.description, manifest = excluded.manifest",
            (pack["name"], source, ref, pack["author"], pack["license"],
             pack["description"], store.dumps(pack["manifest"]), store.now()),
        )
        pack_id = connection.execute(
            "SELECT id FROM persona_packs WHERE name = ?", (pack["name"],)
        ).fetchone()["id"]
        for spec in pack["personas"]:
            digest = persona_digest(spec["key"], spec["layer"], spec["body"])
            found = find_persona(connection, spec["key"], digest)
            if found is not None:
                reject_cross_pack_claim(connection, found, spec, pack, pack_id)
                if adopt_persona(connection, found, spec, pack, pack_id, source):
                    adopted.append(spec["key"])
                else:
                    unchanged.append(spec["key"])
                continue
            # A key the store already holds under different words is the same
            # persona rewritten upstream, not a new one. Both rows stay; only
            # the wording of the report changes, so re-adding a moved-on pack
            # reads as the update it is rather than as a first installation.
            superseded = connection.execute(
                "SELECT 1 FROM personas WHERE key = ?", (spec["key"],)
            ).fetchone() is not None
            insert_persona(
                connection, key=spec["key"], title=spec["title"],
                summary=spec["summary"], body=spec["body"], layer=spec["layer"],
                digest=digest, source_path=spec["source_path"],
                author=pack["author"], license=pack["license"],
                source_url=source, version=pack["version"], tags=spec["tags"],
                pack_id=pack_id, metadata=persona_git_metadata(pack),
            )
            (updated if superseded else installed).append(spec["key"])
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    return {"pack_id": pack_id, "installed": installed, "updated": updated,
            "adopted": adopted, "unchanged": unchanged}


# --------------------------------------------------------------- store -> vault

def write_note(path: Path, parts) -> None:
    """Join a note and collapse the blank-line noise that accumulates from
    building it out of fragments. These are meant to be read, not just parsed."""
    text = "\n".join(part for part in parts if part is not None)
    text = re.sub(r"\n{3,}", "\n\n", text).strip()
    path.write_text(text + "\n")


def slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", str(text or "").lower()).strip("-") or "unnamed"


def export_markdown(connection, out_dir: Path) -> int:
    """Render the catalogue as a linked vault.

    Every cross-reference is a [[wikilink]], because that is what turns a folder
    of documents into a graph an editor can draw and walk.
    """
    written = 0
    for sub in ("personas", "rules", "topologies", "projects"):
        (out_dir / sub).mkdir(parents=True, exist_ok=True)

    # Personas: newest version of each key. These are the shareable half, so
    # each note is written to be readable on its own and installable elsewhere.
    personas = connection.execute(
        "SELECT * FROM personas a WHERE a.id ="
        " (SELECT MAX(id) FROM personas b WHERE b.key = a.key) ORDER BY a.layer, a.key"
    ).fetchall()
    for persona in personas:
        used_by = connection.execute(
            "SELECT DISTINCT t.key AS topology, ta.role_key FROM seat_personas sp"
            " JOIN topology_agents ta ON ta.id = sp.topology_agent_id"
            " JOIN topologies t ON t.id = ta.topology_id"
            " WHERE sp.persona_id = ? ORDER BY t.key", (persona["id"],)
        ).fetchall()
        meta = {
            "type": "persona", "key": persona["key"], "title": persona["title"],
            "layer": persona["layer"],
            "tags": store.loads(persona["tags"]) or None,
            "author": persona["author"], "license": persona["license"],
            "version": persona["version"], "source_url": persona["source_url"],
            "content_hash": (persona["content_hash"] or "")[:12],
        }
        body = [frontmatter_block(meta),
                f"\n# {persona['title'] or persona['key']}\n",
                f"\n`{persona['layer']}` layer\n"]
        if persona["summary"]:
            body.append(f"\n{persona['summary']}\n")
        if used_by:
            body.append("\n## Used by\n")
            body.extend(f"- [[topology-{slug(row['topology'])}]] as **{row['role_key']}**"
                        for row in used_by)
        body.append("\n## Prompt\n")
        body.append((persona["body"] or "").rstrip())
        path = out_dir / "personas" / f"persona-{slug(persona['key'])}.md"
        write_note(path, body)
        written += 1

    # Rules.
    rules = connection.execute(
        "SELECT * FROM rules r WHERE r.id ="
        " (SELECT MAX(id) FROM rules b WHERE b.key = r.key) ORDER BY r.key"
    ).fetchall()
    for rule in rules:
        meta = {"type": "rule", "key": rule["key"], "title": rule["title"],
                "kind": rule["kind"],
                "content_hash": (rule["content_hash"] or "")[:12],
                "source": rule["source_path"]}
        body = [frontmatter_block(meta), f"\n# {rule['title'] or rule['key']}\n",
                f"\nKind: `{rule['kind']}`\n", "\n---\n",
                (rule["body"] or "").rstrip()]
        path = out_dir / "rules" / f"rule-{slug(rule['key'])}.md"
        write_note(path, body)
        written += 1

    # Topologies: the graph itself.
    topologies = connection.execute(
        "SELECT t.*, p.key AS project_key FROM topologies t"
        " LEFT JOIN projects p ON p.id = t.project_id ORDER BY t.key"
    ).fetchall()
    for topology in topologies:
        seats = connection.execute(
            "SELECT ta.id, ta.role_key, ta.seat, p.key AS persona_key,"
            " b.cli, b.model, b.thinking_level FROM topology_agents ta"
            " LEFT JOIN personas p ON p.id = ta.persona_id"
            " LEFT JOIN bindings b ON b.id = ta.binding_id"
            " WHERE ta.topology_id = ? ORDER BY ta.ordering, ta.role_key, ta.seat",
            (topology["id"],),
        ).fetchall()
        edges = connection.execute(
            "SELECT from_role, to_role, kind FROM topology_edges"
            " WHERE topology_id = ? ORDER BY from_role, kind", (topology["id"],)
        ).fetchall()
        bound = connection.execute(
            "SELECT r.key FROM rules r JOIN rule_bindings b ON b.rule_id = r.id"
            " WHERE b.scope_type = 'topology' AND b.scope_id = ? ORDER BY r.key",
            (topology["id"],),
        ).fetchall()
        meta = {"type": "topology", "key": topology["key"],
                "project": topology["project_key"], "domain": topology["domain"],
                "is_template": bool(topology["is_template"])}
        body = [frontmatter_block(meta), f"\n# {topology['name'] or topology['key']}\n"]
        if topology["project_key"]:
            body.append(f"\nProject: [[project-{slug(topology['project_key'])}]]\n")
        body.append("\n## Seats\n")
        for seat in seats:
            stack = connection.execute(
                "SELECT p.key FROM seat_personas sp JOIN personas p ON p.id = sp.persona_id"
                " WHERE sp.topology_agent_id = ? ORDER BY sp.ordering", (seat["id"],)
            ).fetchall()
            layered = " + ".join(f"[[persona-{slug(r['key'])}]]" for r in stack) or "-"
            body.append(
                f"- **{seat['role_key']}** seat {seat['seat']} → {layered} "
                f"on `{seat['cli']}` / `{seat['model']}` / `{seat['thinking_level']}`"
            )
        if edges:
            body.append("\n## Wiring\n")
            body.append("```mermaid")
            body.append("graph TD")
            for edge in edges:
                body.append(f"  {slug(edge['from_role'])}[{edge['from_role']}] "
                            f"-->|{edge['kind']}| {slug(edge['to_role'])}[{edge['to_role']}]")
            body.append("```")
        if bound:
            body.append("\n## Rules\n")
            body.extend(f"- [[rule-{slug(rule['key'])}]]" for rule in bound)
        path = out_dir / "topologies" / f"topology-{slug(topology['key'])}.md"
        write_note(path, body)
        written += 1

    # Projects, with the comparison table that is the reason topologies are
    # addressable in the first place.
    projects = connection.execute("SELECT * FROM projects ORDER BY key").fetchall()
    for project in projects:
        runs = connection.execute(
            "SELECT * FROM topology_comparison WHERE project = ? ORDER BY run",
            (project["key"],),
        ).fetchall()
        meta = {"type": "project", "key": project["key"],
                "domain": project["domain"]}
        body = [frontmatter_block(meta), f"\n# {project['name'] or project['key']}\n"]
        tops = connection.execute(
            "SELECT key FROM topologies WHERE project_id = ? ORDER BY key",
            (project["id"],),
        ).fetchall()
        if tops:
            body.append("\n## Topologies\n")
            body.extend(f"- [[topology-{slug(row['key'])}]]" for row in tops)
        if runs:
            body.append("\n## Runs\n")
            body.append("| run | topology | status | attempts | failed | cost usd | tokens | duration s |")
            body.append("| --- | --- | --- | --- | --- | --- | --- | --- |")
            for run in runs:
                duration = run["duration_s"]
                body.append(
                    f"| `{run['run']}` | {run['topology'] or '-'} | {run['run_status'] or '-'} "
                    f"| {run['attempts']} | {run['failed_attempts']} "
                    f"| {run['cost_usd']:.4f} | {run['total_tokens']} "
                    f"| {duration:.1f} |" if duration is not None else
                    f"| `{run['run']}` | {run['topology'] or '-'} | {run['run_status'] or '-'} "
                    f"| {run['attempts']} | {run['failed_attempts']} "
                    f"| {run['cost_usd']:.4f} | {run['total_tokens']} | - |"
                )
        path = out_dir / "projects" / f"project-{slug(project['key'])}.md"
        write_note(path, body)
        written += 1

    return written


# ---------------------------------------------------------------- commands

def cmd_sync(args):
    connection = store.connect(args.db)
    counts = sync(connection, Path(args.flow), args.project, args.domain,
                  args.topology, Path(args.engine) if args.engine else None)
    print("synced " + ", ".join(f"{value} {key}" for key, value in counts.items()))
    return 0


def cmd_export_md(args):
    connection = store.connect(args.db)
    written = export_markdown(connection, Path(args.out))
    print(f"wrote {written} note(s) to {args.out}")
    return 0


def cmd_show(args):
    connection = store.connect(args.db)
    print("PERSONAS")
    for row in connection.execute(
        "SELECT key, layer, substr(content_hash,1,8) h FROM personas a"
        " WHERE a.id = (SELECT MAX(id) FROM personas b WHERE b.key = a.key)"
        " ORDER BY layer, key"
    ):
        print(f"  {row['key']:<30} {row['layer']:<8} {row['h']}")
    print("BINDINGS")
    for row in connection.execute(
        "SELECT key, cli, model, thinking_level, access_tier FROM bindings a"
        " WHERE a.id = (SELECT MAX(id) FROM bindings b WHERE b.key = a.key) ORDER BY key"
    ):
        print(f"  {row['key']:<16} {row['cli']:<8} {row['model']:<18} "
              f"{row['thinking_level']:<7} {row['access_tier']}")
    print("RULES")
    for row in connection.execute(
        "SELECT key, kind FROM rules r WHERE r.id ="
        " (SELECT MAX(id) FROM rules b WHERE b.key = r.key) ORDER BY kind, key"
    ):
        print(f"  {row['key']:<28} {row['kind']}")
    print("TOPOLOGIES")
    for row in connection.execute(
        "SELECT t.key, p.key project, COUNT(ta.id) seats FROM topologies t"
        " LEFT JOIN projects p ON p.id = t.project_id"
        " LEFT JOIN topology_agents ta ON ta.topology_id = t.id"
        " GROUP BY t.id ORDER BY t.key"
    ):
        print(f"  {row['key']:<20} project={row['project'] or '-':<16} seats={row['seats']}")
    return 0


def cmd_persona_add(args):
    # Validate before opening the store, whichever way the pack arrived: a pack
    # that cannot be fetched or cannot be read must not so much as create the
    # database file it was refused from.
    if looks_like_git_url(args.source):
        try:
            with git_checkout(args.source) as (directory, commit):
                pack = read_pack_from_url(args.source, directory, commit)
                # Installed while the checkout still exists, because the persona
                # bodies are read out of it; nothing of it is stored.
                return install_and_report(args.db, pack)
        except PackError as error:
            raise SystemExit(f"persona add: {error}")
    try:
        pack = read_pack(args.source)
    except PackError as error:
        raise SystemExit(f"persona add: {error}")
    return install_and_report(args.db, pack)


def install_and_report(db, pack: dict) -> int:
    connection = store.connect(db)
    try:
        result = install_pack(connection, pack)
    except PackError as error:
        # install_pack has already rolled back, so the store is exactly as it
        # was; the only thing left to do is say why, without a traceback.
        raise SystemExit(f"persona add: {error}")
    print(f"pack {pack['name']} {pack['version']} from "
          f"{pack.get('source_url') or pack['root']}")
    if pack.get("ref"):
        print(f"  commit {pack['ref']}")
    print(f"  author {pack['author']} | license {pack['license']} | "
          f"tags {', '.join(pack['tags']) or '-'}")
    for key in result["installed"]:
        print(f"  + {key}")
    for key in result["updated"]:
        print(f"  ^ {key} (new version; the previous one is kept)")
    for key in result["adopted"]:
        print(f"  ~ {key} (adopted into pack)")
    for key in result["unchanged"]:
        print(f"  = {key} (unchanged)")
    print(f"installed {len(result['installed'])}, updated {len(result['updated'])}, "
          f"adopted {len(result['adopted'])}, unchanged {len(result['unchanged'])}")
    return 0


def cmd_persona_list(args):
    connection = store.connect(args.db)
    rows = connection.execute(
        "SELECT p.key, p.layer, p.version, p.content_hash, p.source_url,"
        " p.source_path, p.metadata, p.body, k.name AS pack FROM personas p"
        " LEFT JOIN persona_packs k ON k.id = p.pack_id"
        " WHERE p.id = (SELECT MAX(id) FROM personas b WHERE b.key = p.key)"
        " ORDER BY p.layer, p.key"
    ).fetchall()
    if not rows:
        print("no personas installed")
        return 0
    # The commit is per version rather than per pack, so it belongs next to the
    # content hash: together they say which words these are and where they came
    # from, for the version being shown rather than for the pack's newest.
    print(f"{'KEY':<28} {'LAYER':<8} {'PACK':<18} {'VERSION':<10} {'HASH':<14} "
          f"{'COMMIT':<14} SOURCE")
    for row in rows:
        commit = persona_commit(row["metadata"]) or "-"
        print(f"{row['key']:<28} {row['layer']:<8} {row['pack'] or '-':<18} "
              f"{row['version'] or '-':<10} {(row['content_hash'] or '')[:12]:<14} "
              f"{commit[:12]:<14} "
              f"{row['source_url'] or row['source_path'] or '-'}")
    # A persona is its wording. The table says which version is current and
    # where it came from, but a hash cannot be read: the only way to see what
    # a seat will actually be told is to print the words. So they are printed
    # exactly as stored - the whole body, not truncated, reflowed or indented -
    # for the version the table names, and for no other.
    for row in rows:
        print()
        print(f"--- {row['key']} ---")
        print(persona_wording(row))
        print(f"--- end {row['key']} ---")
    return 0


def persona_wording(row):
    """The stored body of a persona row, verbatim.

    Nothing here shortens or rewrites it. A summary or a hash would describe
    the prompt; only the body is the prompt, and the point of listing is to
    read it.
    """
    return row["body"] or ""


def cmd_compare(args):
    connection = store.connect(args.db)
    rows = connection.execute(
        "SELECT * FROM topology_comparison"
        + (" WHERE project = ?" if args.project else "")
        + " ORDER BY project, topology, run",
        (args.project,) if args.project else (),
    ).fetchall()
    if not rows:
        print("no runs recorded yet")
        return 0
    print(f"{'PROJECT':<16} {'TOPOLOGY':<14} {'RUN':<26} {'STATUS':<9} "
          f"{'ATTEMPTS':>8} {'FAILED':>6} {'USD':>9} {'TOKENS':>9} {'SECONDS':>8}")
    for row in rows:
        duration = f"{row['duration_s']:.1f}" if row["duration_s"] is not None else "-"
        print(f"{row['project'] or '-':<16} {row['topology'] or '-':<14} "
              f"{row['run']:<26} {row['run_status'] or '-':<9} "
              f"{row['attempts']:>8} {row['failed_attempts']:>6} "
              f"{row['cost_usd']:>9.4f} {row['total_tokens']:>9} {duration:>8}")
    return 0


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--db", help="path to the store (or $PM_FLOW_STORE)")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("sync", help="read the flow directory into the store")
    p.add_argument("--flow", required=True, help="the repository's project data")
    p.add_argument("--engine", help="the packaged defaults (default: --flow)")
    p.add_argument("--project", required=True)
    p.add_argument("--domain", default="")
    p.add_argument("--topology", default="default")
    p.set_defaults(func=cmd_sync)

    p = sub.add_parser("export-md", help="render the catalogue as a linked vault")
    p.add_argument("--out", required=True)
    p.set_defaults(func=cmd_export_md)

    p = sub.add_parser("show", help="what the store knows")
    p.set_defaults(func=cmd_show)

    p = sub.add_parser("persona", help="install and inspect persona packs")
    persona_sub = p.add_subparsers(dest="persona_command", required=True)
    q = persona_sub.add_parser(
        "add", help="install a persona pack from a local path or a git URL")
    q.add_argument("source", metavar="path-or-url",
                   help="pack directory, its persona-pack.json, or a git URL")
    q.set_defaults(func=cmd_persona_add)
    q = persona_sub.add_parser("list", help="installed personas and their provenance")
    q.set_defaults(func=cmd_persona_list)

    p = sub.add_parser("compare", help="runs side by side, by topology")
    p.add_argument("--project")
    p.set_defaults(func=cmd_compare)

    args = parser.parse_args(argv[1:])
    args.db = args.db or os.environ.get("PM_FLOW_STORE", "")
    if not args.db:
        raise SystemExit("no store: pass --db or set PM_FLOW_STORE")
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
