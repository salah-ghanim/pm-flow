"""Run two topology arms from one commit and import their telemetry."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cost  # noqa: E402
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
    """Import complete runs, remapping definition and record ids."""
    source = sqlite3.connect(str(source_path))
    source.row_factory = sqlite3.Row
    destination = store.connect(destination_path)
    project_ids = {}
    topology_ids = {}
    task_ids = {}
    persona_ids = {}
    binding_ids = {}
    artifact_ids = {}
    attempt_ids = {}

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
        for edge in source.execute(
                "SELECT from_role, to_role, kind, metadata"
                " FROM topology_edges WHERE topology_id = ? ORDER BY id",
                (source_id,)):
            destination.execute(
                "INSERT OR IGNORE INTO topology_edges"
                " (topology_id, from_role, to_role, kind, metadata)"
                " VALUES (?, ?, ?, ?, ?)",
                (mapped, edge["from_role"], edge["to_role"], edge["kind"],
                 edge["metadata"]),
            )
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
                    attempt_cursor = destination.execute(
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
                    attempt_ids[attempt["id"]] = attempt_cursor.lastrowid
                for outcome in source.execute(
                        "SELECT * FROM outcomes WHERE run_id = ? ORDER BY id",
                        (run["id"],)):
                    source_attempt_id = outcome["attempt_id"]
                    mapped_attempt_id = None
                    if source_attempt_id is not None:
                        if source_attempt_id not in attempt_ids:
                            raise CompareError(
                                f"outcome {outcome['id']} names an attempt outside "
                                f"its imported run")
                        mapped_attempt_id = attempt_ids[source_attempt_id]
                    destination.execute(
                        "INSERT INTO outcomes"
                        " (run_id, project_id, task_id, attempt_id, metric,"
                        "  value_num, value_text, source, recorded_at, metadata)"
                        " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                        (run_id, map_project(outcome["project_id"]),
                         map_task(outcome["task_id"]),
                         mapped_attempt_id, outcome["metric"],
                         outcome["value_num"], outcome["value_text"],
                         outcome["source"], outcome["recorded_at"],
                         outcome["metadata"]),
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


def apply_persona_swap(
        arm, engine: Path, project: str, role: str, persona: str) -> None:
    checked([
        sys.executable, engine / "catalog.py", "--db", arm["db"],
        "persona", "swap", role, persona,
        "--project", project, "--topology", arm["key"],
    ])


def parse_persona_swaps(values: list[str], keys: tuple[str, str],
                        overlays: dict[str, dict], flow: Path):
    swaps = {key: [] for key in keys}
    for value in values:
        match = re.fullmatch(r"([^:=]+):([^:=]+)=([^:=]+)", value)
        if match is None:
            raise CompareError(
                f"invalid --persona value {value!r}; expected topology:role=persona")
        key, role, persona = match.groups()
        if key not in swaps:
            raise CompareError(
                f"persona swap names topology {key!r}, which is not one of "
                f"the comparison arms: {keys[0]!r}, {keys[1]!r}")
        if role not in overlays[key].get("roles", {}):
            raise CompareError(
                f"persona swap names unknown role {role!r} in topology {key!r}")
        domain = overlays[key].get("domain") or "generic"
        persona_paths = (
            flow / "roles" / f"{persona}.md",
            flow / "domains" / domain / "roles" / f"{persona}.md",
        )
        if not any(path.is_file() for path in persona_paths):
            raise CompareError(
                f"persona swap names unknown persona {persona!r} for topology {key!r}")
        swaps[key].append((role, persona))
    return swaps


def _placeholders(values) -> str:
    return ",".join("?" for _value in values)


def resolve_arms(connection, project: str, run_keys: tuple[str, str]):
    project_row = connection.execute(
        "SELECT id FROM projects WHERE key = ?", (project,)
    ).fetchone()
    if project_row is None:
        raise CompareError(f"project {project!r} has no recorded runs")
    seeds = []
    for run_key in run_keys:
        row = connection.execute(
            "SELECT r.id, r.run_key, r.topology_id, t.key AS topology_key"
            " FROM runs r JOIN topologies t ON t.id = r.topology_id"
            " WHERE r.project_id = ? AND r.run_key = ?",
            (project_row["id"], run_key),
        ).fetchone()
        if row is None:
            raise CompareError(
                f"run {run_key!r} is not recorded for project {project!r}")
        seeds.append(row)
    if seeds[0]["topology_id"] == seeds[1]["topology_id"]:
        raise CompareError("report requires runs from two different topology arms")
    arms = []
    for seed in seeds:
        rows = connection.execute(
            "SELECT id, run_key, started_at FROM runs"
            " WHERE project_id = ? AND topology_id = ?"
            " ORDER BY started_at, id",
            (project_row["id"], seed["topology_id"]),
        ).fetchall()
        arms.append({
            "key": seed["topology_key"],
            "topology_id": seed["topology_id"],
            "run_ids": [row["id"] for row in rows],
            "run_keys": [row["run_key"] for row in rows],
        })
    return arms


def longest_escalation_depth(connection, topology_id: int,
                             run_ids: list[int]) -> int:
    if not run_ids:
        return 0
    marks = _placeholders(run_ids)
    section_roles = {}
    for row in connection.execute(
            "SELECT task_id, role_key FROM attempts"
            f" WHERE run_id IN ({marks}) AND task_id IS NOT NULL"
            " GROUP BY task_id, role_key", run_ids):
        section_roles.setdefault(row["task_id"], set()).add(row["role_key"])
    edges = [
        (row["from_role"], row["to_role"])
        for row in connection.execute(
            "SELECT from_role, to_role FROM topology_edges"
            " WHERE topology_id = ? AND kind = 'escalates_to'",
            (topology_id,),
        )
    ]

    def depth_from(role, adjacency, seen):
        best = 0
        for target in adjacency.get(role, ()):
            if target in seen:
                continue
            best = max(best, 1 + depth_from(target, adjacency, seen | {target}))
        return best

    longest = 0
    for roles in section_roles.values():
        adjacency = {}
        for source, target in edges:
            if source in roles and target in roles:
                adjacency.setdefault(source, []).append(target)
        for role in roles:
            longest = max(longest, depth_from(role, adjacency, {role}))
    return longest


def arm_metrics(connection, arm) -> dict[str, float | int | None]:
    run_ids = arm["run_ids"]
    marks = _placeholders(run_ids)
    tokens = connection.execute(
        f"SELECT SUM(COALESCE(total_tokens, 0)) FROM attempts"
        f" WHERE run_id IN ({marks})", run_ids,
    ).fetchone()[0] or 0
    # This is cost.stored_totals' accounting query, restricted to these runs.
    cost_usd = connection.execute(
        f"SELECT SUM(COALESCE(cost_usd, 0)) FROM attempts"
        f" WHERE run_id IN ({marks})", run_ids,
    ).fetchone()[0] or 0.0
    cycles_to_done = connection.execute(
        "WITH completed AS ("
        " SELECT DISTINCT task_id FROM outcomes"
        f" WHERE run_id IN ({marks}) AND metric = 'section_status'"
        " AND value_text = 'complete' AND task_id IS NOT NULL"
        "), section_cycles AS ("
        " SELECT a.task_id, MAX(a.cycle) AS last_cycle FROM attempts a"
        " JOIN completed c ON c.task_id = a.task_id"
        f" WHERE a.run_id IN ({marks}) GROUP BY a.task_id"
        ") SELECT AVG(last_cycle) FROM section_cycles",
        run_ids + run_ids,
    ).fetchone()[0]
    section_count = connection.execute(
        f"SELECT COUNT(DISTINCT task_id) FROM attempts"
        f" WHERE run_id IN ({marks}) AND task_id IS NOT NULL", run_ids,
    ).fetchone()[0]
    rescued = connection.execute(
        f"SELECT COUNT(DISTINCT task_id) FROM attempts"
        f" WHERE run_id IN ({marks}) AND task_id IS NOT NULL"
        " AND role_key = '10x_developer'", run_ids,
    ).fetchone()[0]
    abandoned = connection.execute(
        f"SELECT COUNT(DISTINCT task_id) FROM outcomes"
        f" WHERE run_id IN ({marks}) AND task_id IS NOT NULL"
        " AND metric = 'section_status' AND value_text = 'abandoned'", run_ids,
    ).fetchone()[0]
    wall_clock = connection.execute(
        f"SELECT SUM(ended_at - started_at) FROM runs"
        f" WHERE id IN ({marks})", run_ids,
    ).fetchone()[0] or 0.0
    return {
        "cost_usd": float(cost_usd),
        "tokens": int(tokens),
        "cycles_to_done": cycles_to_done,
        "rescue_rate": rescued / section_count if section_count else None,
        "abandon_rate": abandoned / section_count if section_count else None,
        "escalation_depth": longest_escalation_depth(
            connection, arm["topology_id"], run_ids),
        "wall_clock_s": float(wall_clock),
        "n_runs": len(run_ids),
    }


def arm_personas(connection, run_ids: list[int]) -> list[str]:
    marks = _placeholders(run_ids)
    pairs = set()
    for row in connection.execute(
            f"SELECT role_key, persona_stack FROM attempts"
            f" WHERE run_id IN ({marks}) ORDER BY role_key, id", run_ids):
        try:
            stack = json.loads(row["persona_stack"] or "[]")
        except (TypeError, json.JSONDecodeError):
            continue
        for layer in stack:
            if isinstance(layer, dict) and layer.get("layer") == "base":
                persona = layer.get("key")
                if persona:
                    pairs.add((row["role_key"], str(persona)))
                break
    return [f"{role}={persona}" for role, persona in sorted(pairs)]


def render_report(flow: Path, project: str,
                  run_keys: tuple[str, str]) -> int:
    project_dir = flow.resolve() / project
    cost.import_legacy(project_dir)
    connection = store.connect(store.default_path(project_dir))
    try:
        arms = resolve_arms(connection, project, run_keys)
        metrics = [arm_metrics(connection, arm) for arm in arms]
        print(f"metric\t{arms[0]['key']}\t{arms[1]['key']}")
        formats = (
            ("cost_usd", lambda value: f"{value:.4f}"),
            ("tokens", lambda value: str(value)),
            ("cycles_to_done", lambda value: "-" if value is None else f"{value:.2f}"),
            ("rescue_rate", lambda value: "-" if value is None else f"{value:.2f}"),
            ("abandon_rate", lambda value: "-" if value is None else f"{value:.2f}"),
            ("escalation_depth", lambda value: str(value)),
            ("wall_clock_s", lambda value: f"{value:.1f}"),
            ("n_runs", lambda value: str(value)),
        )
        for name, present in formats:
            print(f"{name}\t{present(metrics[0][name])}\t{present(metrics[1][name])}")
        for arm in arms:
            print(f"arm\t{arm['key']}")
            print(f"runs\t{','.join(arm['run_keys'])}")
            print(f"personas\t{','.join(arm_personas(connection, arm['run_ids']))}")
        sizes = [metric["n_runs"] for metric in metrics]
        sentence = (
            f"Limits: {arms[0]['key']} n={sizes[0]}; "
            f"{arms[1]['key']} n={sizes[1]}."
        )
        if 1 in sizes:
            sentence += " No difference between the arms can be inferred."
        else:
            sentence += " This descriptive comparison does not establish significance."
        print(sentence)
    finally:
        connection.close()
    return 0


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
                max_ticks: int, persona_values: list[str],
                keep_copies: bool) -> int:
    flow = flow.resolve()

    # Preflight is deliberately complete before the repository or temp area is
    # touched. A bad second arm must not leave a valid first arm half-started.
    overlays = {}
    for key in (first, second):
        overlays[key], _summaries = topology.validate(key, flow)
    swaps = parse_persona_swaps(
        persona_values, (first, second), overlays, flow)

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
        for role, persona in swaps[arm["key"]]:
            apply_persona_swap(arm, engine, project, role, persona)

    destination = store.default_path(flow / project)
    results = []
    for arm in arms:
        run_keys = run_arm(arm, engine, project, max_ticks)
        import_store(arm["db"], destination)
        results.append((arm, run_keys))

    print(f"starting_commit={commit}")
    for arm, run_keys in results:
        copy_status = "retained" if keep_copies else "removed"
        if not keep_copies:
            shutil.rmtree(arm["copy"].parent)
        print(f"arm_key={arm['key']} copy_path={arm['copy']} "
              f"imported_run_key={','.join(run_keys)} copy_status={copy_status}")
    return render_report(flow, project, (results[0][1][0], results[1][1][0]))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    run = subparsers.add_parser("run")
    run.add_argument("first")
    run.add_argument("second")
    run.add_argument("--flow", required=True, type=Path)
    run.add_argument("--project", required=True)
    run.add_argument("--max-ticks", type=int, default=100)
    run.add_argument("--persona", action="append", default=[])
    run.add_argument("--keep-copies", action="store_true")
    report = subparsers.add_parser("report")
    report.add_argument("first_run")
    report.add_argument("second_run")
    report.add_argument("--flow", required=True, type=Path)
    report.add_argument("--project", required=True)
    return parser


def main(argv):
    args = build_parser().parse_args(argv[1:])
    try:
        if args.command == "report":
            return render_report(
                args.flow, args.project, (args.first_run, args.second_run))
        if args.max_ticks < 0:
            raise CompareError("--max-ticks requires a positive integer")
        return run_compare(
            args.first, args.second, args.flow, args.project, args.max_ticks,
            args.persona, args.keep_copies)
    except (CompareError, topology.TopologyError, OSError, sqlite3.Error) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
