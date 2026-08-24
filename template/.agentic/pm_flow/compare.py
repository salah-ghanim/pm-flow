"""Run two topology arms from one commit and import their telemetry."""

from __future__ import annotations

import argparse
import json
import os
import re
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import store  # noqa: E402
import topology  # noqa: E402


class CompareError(Exception):
    """A comparison arm could not be prepared, run, or imported."""


def checked(command, *, cwd=None, env=None) -> str:
    result = subprocess.run(
        [str(part) for part in command], cwd=cwd, env=env,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        rendered = " ".join(str(part) for part in command)
        raise CompareError(
            f"command failed ({result.returncode}): {rendered}"
            + (f"\n{detail}" if detail else "")
        )
    return result.stdout


def repository_root(flow: Path) -> Path:
    named = os.environ.get("PM_FLOW_REPO_ROOT", "").strip()
    candidate = Path(named) if named else flow.parent.parent
    return candidate.resolve()


def copy_checkout(repo: Path, commit: str, key: str) -> Path:
    safe_key = re.sub(r"[^A-Za-z0-9_.-]+", "-", key).strip("-") or "arm"
    parent = Path(tempfile.mkdtemp(prefix=f"pm-flow-compare-{safe_key}-"))
    checkout = parent / "checkout"
    checked(["git", "clone", "--quiet", "--no-hardlinks", "--no-checkout",
             repo, checkout])
    checked(["git", "-C", checkout, "checkout", "--quiet", "--detach", commit])
    return checkout.resolve()


def read_run_keys(db_path: Path) -> set[str]:
    if not db_path.is_file():
        return set()
    connection = sqlite3.connect(str(db_path))
    try:
        return {row[0] for row in connection.execute("SELECT run_key FROM runs")}
    finally:
        connection.close()


def _source_row(connection, table: str, row_id: int):
    return connection.execute(
        f"SELECT * FROM {table} WHERE id = ?", (row_id,)
    ).fetchone()


def import_store(source_path: Path, destination_path: Path) -> list[str]:
    """Import runs and attempts, remapping definition ids by stable keys."""
    source = sqlite3.connect(str(source_path))
    source.row_factory = sqlite3.Row
    destination = store.connect(destination_path)
    project_ids = {}
    topology_ids = {}
    task_ids = {}
    persona_ids = {}
    binding_ids = {}
    artifact_ids = {}

    def map_cli(key):
        if not key:
            return None
        existing = destination.execute(
            "SELECT key FROM clis WHERE key = ?", (key,)
        ).fetchone()
        if existing is not None:
            return key
        row = source.execute("SELECT * FROM clis WHERE key = ?", (key,)).fetchone()
        if row is None:
            return None
        destination.execute(
            "INSERT OR IGNORE INTO clis"
            " (key, display_name, exec_name, thinking_levels, capabilities,"
            "  default_params) VALUES (?, ?, ?, ?, ?, ?)",
            (row["key"], row["display_name"], row["exec_name"],
             row["thinking_levels"], row["capabilities"], row["default_params"]),
        )
        return key

    def map_project(source_id):
        if source_id is None:
            return None
        if source_id in project_ids:
            return project_ids[source_id]
        row = _source_row(source, "projects", source_id)
        destination.execute(
            "INSERT OR IGNORE INTO projects (key, name, domain, created_at)"
            " VALUES (?, ?, ?, ?)",
            (row["key"], row["name"], row["domain"], row["created_at"]),
        )
        mapped = destination.execute(
            "SELECT id FROM projects WHERE key = ?", (row["key"],)
        ).fetchone()["id"]
        project_ids[source_id] = mapped
        return mapped

    def map_topology(source_id):
        if source_id is None:
            return None
        if source_id in topology_ids:
            return topology_ids[source_id]
        row = _source_row(source, "topologies", source_id)
        project_id = map_project(row["project_id"])
        destination.execute(
            "INSERT OR IGNORE INTO topologies"
            " (key, name, project_id, domain, created_at) VALUES (?, ?, ?, ?, ?)",
            (row["key"], row["name"], project_id, row["domain"], row["created_at"]),
        )
        mapped = destination.execute(
            "SELECT id FROM topologies WHERE key = ? AND project_id IS ?",
            (row["key"], project_id),
        ).fetchone()["id"]
        topology_ids[source_id] = mapped
        return mapped

    def map_task(source_id):
        if source_id is None:
            return None
        if source_id in task_ids:
            return task_ids[source_id]
        row = _source_row(source, "tasks", source_id)
        project_id = map_project(row["project_id"])
        destination.execute(
            "INSERT OR IGNORE INTO tasks"
            " (project_id, key, title, brief, priority, status, metadata,"
            "  source_path, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (project_id, row["key"], row["title"], row["brief"], row["priority"],
             row["status"], row["metadata"], row["source_path"], row["created_at"]),
        )
        mapped = destination.execute(
            "SELECT id FROM tasks WHERE project_id = ? AND key = ?",
            (project_id, row["key"]),
        ).fetchone()["id"]
        task_ids[source_id] = mapped
        return mapped

    def map_persona(source_id):
        if source_id is None:
            return None
        if source_id in persona_ids:
            return persona_ids[source_id]
        row = _source_row(source, "personas", source_id)
        destination.execute(
            "INSERT OR IGNORE INTO personas"
            " (key, title, summary, body, layer, author, license, source_url,"
            "  version, tags, metadata, content_hash, source_path, created_at)"
            " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (row["key"], row["title"], row["summary"], row["body"], row["layer"],
             row["author"], row["license"], row["source_url"], row["version"],
             row["tags"], row["metadata"], row["content_hash"],
             row["source_path"], row["created_at"]),
        )
        mapped = destination.execute(
            "SELECT id FROM personas WHERE key = ? AND content_hash = ?",
            (row["key"], row["content_hash"]),
        ).fetchone()["id"]
        persona_ids[source_id] = mapped
        return mapped

    def map_binding(source_id):
        if source_id is None:
            return None
        if source_id in binding_ids:
            return binding_ids[source_id]
        row = _source_row(source, "bindings", source_id)
        cli = map_cli(row["cli"])
        destination.execute(
            "INSERT OR IGNORE INTO bindings"
            " (key, cli, model, thinking_level, access_tier, cli_params,"
            "  content_hash, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (row["key"], cli, row["model"], row["thinking_level"],
             row["access_tier"], row["cli_params"], row["content_hash"],
             row["created_at"]),
        )
        mapped = destination.execute(
            "SELECT id FROM bindings WHERE key = ? AND content_hash = ?",
            (row["key"], row["content_hash"]),
        ).fetchone()["id"]
        binding_ids[source_id] = mapped
        return mapped

    def map_artifact(source_id):
        if source_id is None:
            return None
        if source_id in artifact_ids:
            return artifact_ids[source_id]
        row = _source_row(source, "artifacts", source_id)
        destination.execute(
            "INSERT OR IGNORE INTO artifacts"
            " (sha256, media_type, bytes, truncated, content, created_at)"
            " VALUES (?, ?, ?, ?, ?, ?)",
            (row["sha256"], row["media_type"], row["bytes"], row["truncated"],
             row["content"], row["created_at"]),
        )
        mapped = destination.execute(
            "SELECT id FROM artifacts WHERE sha256 = ?", (row["sha256"],)
        ).fetchone()["id"]
        artifact_ids[source_id] = mapped
        return mapped

    imported = []
    try:
        with destination:
            for run in source.execute("SELECT * FROM runs ORDER BY id"):
                existing = destination.execute(
                    "SELECT id FROM runs WHERE run_key = ?", (run["run_key"],)
                ).fetchone()
                if existing is not None:
                    continue
                project_id = map_project(run["project_id"])
                topology_id = map_topology(run["topology_id"])
                cursor = destination.execute(
                    "INSERT INTO runs"
                    " (run_key, trace_id, project_id, topology_id, command, label,"
                    "  started_at, ended_at, status, host, pid, metadata)"
                    " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (run["run_key"], run["trace_id"], project_id, topology_id,
                     run["command"], run["label"], run["started_at"],
                     run["ended_at"], run["status"], run["host"], run["pid"],
                     run["metadata"]),
                )
                run_id = cursor.lastrowid
                for attempt in source.execute(
                        "SELECT * FROM attempts WHERE run_id = ? ORDER BY id",
                        (run["id"],)):
                    destination.execute(
                        "INSERT INTO attempts"
                        " (run_id, project_id, task_id, persona_id, binding_id,"
                        "  persona_stack, role_key, seat, cycle, attempt_no, label,"
                        "  step, trace_id, span_id, cli, model, thinking_level,"
                        "  access_tier, started_at, ended_at, duration_s, status,"
                        "  failure_reason, cost_usd, input_tokens, output_tokens,"
                        "  reasoning_tokens, cache_read_tokens, cache_write_tokens,"
                        "  total_tokens, input_artifact_id, output_artifact_id,"
                        "  response_path, metadata)"
                        " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,"
                        " ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                        (run_id, map_project(attempt["project_id"]),
                         map_task(attempt["task_id"]),
                         map_persona(attempt["persona_id"]),
                         map_binding(attempt["binding_id"]),
                         attempt["persona_stack"], attempt["role_key"],
                         attempt["seat"], attempt["cycle"], attempt["attempt_no"],
                         attempt["label"], attempt["step"], attempt["trace_id"],
                         attempt["span_id"], attempt["cli"], attempt["model"],
                         attempt["thinking_level"], attempt["access_tier"],
                         attempt["started_at"], attempt["ended_at"],
                         attempt["duration_s"], attempt["status"],
                         attempt["failure_reason"], attempt["cost_usd"],
                         attempt["input_tokens"], attempt["output_tokens"],
                         attempt["reasoning_tokens"], attempt["cache_read_tokens"],
                         attempt["cache_write_tokens"], attempt["total_tokens"],
                         map_artifact(attempt["input_artifact_id"]),
                         map_artifact(attempt["output_artifact_id"]),
                         attempt["response_path"], attempt["metadata"]),
                    )
                imported.append(run["run_key"])
    finally:
        source.close()
        destination.close()
    return imported


def sync_arm(arm, engine: Path, project: str) -> None:
    config = arm["overlay"]
    domain = config.get("domain") or "generic"
    checked([
        sys.executable, engine / "catalog.py", "--db", arm["db"], "sync",
        "--flow", arm["flow"], "--engine", engine,
        "--project", project, "--domain", domain, "--topology", arm["key"],
    ])


def swap_first_arm(arm, engine: Path, project: str) -> None:
    checked([
        sys.executable, engine / "catalog.py", "--db", arm["db"],
        "persona", "swap", "pm", "cpo",
        "--project", project, "--topology", arm["key"],
    ])


def run_arm(arm, engine: Path, project: str, max_ticks: int) -> list[str]:
    before = read_run_keys(arm["db"])
    environment = dict(os.environ)
    environment.update({
        "PM_FLOW_ENGINE_ROOT": str(engine),
        "PM_FLOW_REPO_ROOT": str(arm["copy"]),
        "PM_FLOW_FLOW_DIR": str(arm["flow"]),
        "PM_FLOW_TOPOLOGY": arm["key"],
    })
    for stale in ("PM_FLOW_STORE", "PM_FLOW_RUN_KEY", "PM_FLOW_TRACE_ID",
                  "PM_FLOW_PROJECT_DIR", "PM_FLOW_RUNS_DIR",
                  "PM_FLOW_SECTIONS_DIR", "PM_FLOW_STATE_DIR"):
        environment.pop(stale, None)
    checked(
        ["zsh", engine / "pm_flow.sh", "--project", project,
         "run", "--max-ticks", str(max_ticks)],
        cwd=arm["copy"], env=environment,
    )
    created = sorted(read_run_keys(arm["db"]) - before)
    if not created:
        raise CompareError(f"topology {arm['key']!r} produced no run")
    return created


def run_compare(first: str, second: str, flow: Path, project: str,
                max_ticks: int) -> int:
    flow = flow.resolve()

    # Preflight is deliberately complete before the repository or temp area is
    # touched. A bad second arm must not leave a valid first arm half-started.
    overlays = {}
    for key in (first, second):
        overlays[key], _summaries = topology.validate(key, flow)

    repo = repository_root(flow)
    commit = checked(["git", "-C", repo, "rev-parse", "HEAD"]).strip()
    if not commit:
        raise CompareError(f"could not read the starting commit from {repo}")

    arms = []
    for key in (first, second):
        checkout = copy_checkout(repo, commit, key)
        arm_flow = checkout / ".agentic" / "pm_flow"
        config_path = arm_flow / "config.json"
        if not config_path.parent.is_dir():
            raise CompareError(f"checkout has no flow directory: {arm_flow}")
        config_path.write_text(json.dumps(overlays[key], indent=2) + "\n")
        arms.append({
            "key": key,
            "copy": checkout,
            "flow": arm_flow,
            "db": store.default_path(arm_flow / project),
            "overlay": overlays[key],
        })

    engine = Path(__file__).resolve().parent
    for arm in arms:
        sync_arm(arm, engine, project)
    swap_first_arm(arms[0], engine, project)

    destination = store.default_path(flow / project)
    results = []
    for arm in arms:
        run_keys = run_arm(arm, engine, project, max_ticks)
        import_store(arm["db"], destination)
        results.append((arm, run_keys))

    print(f"starting_commit={commit}")
    for arm, run_keys in results:
        print(f"arm_key={arm['key']} copy_path={arm['copy']} "
              f"imported_run_key={','.join(run_keys)}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    run = subparsers.add_parser("run")
    run.add_argument("first")
    run.add_argument("second")
    run.add_argument("--flow", required=True, type=Path)
    run.add_argument("--project", required=True)
    run.add_argument("--max-ticks", type=int, default=100)
    return parser


def main(argv):
    args = build_parser().parse_args(argv[1:])
    try:
        if args.max_ticks < 0:
            raise CompareError("--max-ticks requires a positive integer")
        return run_compare(
            args.first, args.second, args.flow, args.project, args.max_ticks)
    except (CompareError, topology.TopologyError, OSError, sqlite3.Error) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
