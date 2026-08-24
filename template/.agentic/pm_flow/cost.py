"""Import legacy dispatch costs and read current costs from the store.

Two things make this less trivial than reading one key.

A *successful* claude dispatch publishes the CLI's own JSON, so `total_cost_usd`
sits at the top level. A *failed* one does not: the harness wraps whatever the
CLI emitted as a string in `result`, and the cost ends up nested inside that
string with no top-level key. Those are exactly the dispatches worth counting -
a call that died after the model had already answered is paid for and bought
nothing - so the nested form is parsed too, with a regex as the last resort.

Legacy totals remain available while the driver still uses their explicit TSV
arity. New total and report calls silently absorb that history once, then answer
only from attempts in the project store.
"""

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import store  # noqa: E402

NESTED_COST = re.compile(r'"total_cost_usd"\s*:\s*([0-9]+(?:\.[0-9]+)?)')


def cost_of(path):
    """The dollar cost recorded in one response envelope, or None."""
    try:
        raw = Path(path).read_text(errors="replace")
    except OSError:
        return None
    payload = None
    try:
        payload = json.loads(raw)
    except ValueError:
        pass
    if isinstance(payload, dict):
        value = payload.get("total_cost_usd")
        if value is not None:
            try:
                return float(value)
            except (TypeError, ValueError):
                pass
        inner = payload.get("result")
        if isinstance(inner, str):
            try:
                nested = json.loads(inner)
            except ValueError:
                nested = None
            if isinstance(nested, dict) and nested.get("total_cost_usd") is not None:
                try:
                    return float(nested["total_cost_usd"])
                except (TypeError, ValueError):
                    pass
    match = NESTED_COST.search(raw)
    if match:
        return float(match.group(1))
    return None


def section_of(path, project_dir):
    """The section key a response envelope belongs to, or '(project)'."""
    try:
        parts = Path(path).resolve().relative_to(Path(project_dir).resolve()).parts
    except ValueError:
        return "(project)"
    if len(parts) >= 2 and parts[0] == "sections":
        return parts[1]
    return "(project)"


def response_files(project_dir):
    root = Path(project_dir)
    seen = []
    for pattern in ("**/*.response.json", "**/proposal_*.json"):
        for path in root.glob(pattern):
            if path.is_file():
                seen.append(path)
    return sorted(set(seen))


def ledger_rows(ledger_path):
    path = Path(ledger_path)
    if not path.is_file():
        return []
    rows = []
    for line in path.read_text(errors="replace").splitlines():
        fields = line.split("\t")
        if len(fields) < 5:
            continue
        rows.append({
            "ts": fields[0],
            "section": fields[1],
            "role": fields[2],
            "label": fields[3],
            "cost": fields[4],
            "response": fields[5] if len(fields) > 5 else "",
        })
    return rows


def import_legacy(project_dir):
    """Import legacy ledger rows and response envelopes into the store."""
    project = Path(project_dir)
    connection = store.connect(store.default_path(project))
    imported = 0
    telemetry_module = None

    def started_at(stamp, response):
        if stamp.endswith("Z"):
            try:
                return datetime.fromisoformat(stamp[:-1] + "+00:00").timestamp()
            except ValueError:
                pass
        if response:
            try:
                return Path(response).stat().st_mtime
            except OSError:
                pass
        return store.now()

    def task_id(project_id, section):
        if section == "(project)":
            return None
        connection.execute(
            "INSERT OR IGNORE INTO tasks (project_id, key, title, created_at)"
            " VALUES (?, ?, ?, ?)",
            (project_id, section, section, store.now()),
        )
        row = connection.execute(
            "SELECT id FROM tasks WHERE project_id = ? AND key = ?",
            (project_id, section),
        ).fetchone()
        return row["id"] if row else None

    def usage_for(response):
        nonlocal telemetry_module
        if not response or not Path(response).is_file():
            return {}
        if telemetry_module is None:
            import telemetry as telemetry_module_import
            telemetry_module = telemetry_module_import
        return telemetry_module.usage_from_response(response)

    def insert_attempt(project_id, section, role, label, stamp, cost,
                       response, source):
        nonlocal imported
        usage = usage_for(response)
        connection.execute(
            "INSERT INTO attempts"
            " (project_id, task_id, role_key, label, started_at, status, cost_usd,"
            "  input_tokens, output_tokens, reasoning_tokens, cache_read_tokens,"
            "  cache_write_tokens, total_tokens, response_path, metadata)"
            " VALUES (?, ?, ?, ?, ?, 'imported', ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (project_id, task_id(project_id, section), role, label,
             started_at(stamp, response), cost, usage.get("input_tokens"),
             usage.get("output_tokens"), usage.get("reasoning_tokens"),
             usage.get("cache_read_tokens"), usage.get("cache_write_tokens"),
             usage.get("total_tokens"), response, store.dumps({"source": source})),
        )
        imported += 1

    try:
        with connection:
            project_key = project.resolve().name
            connection.execute(
                "INSERT OR IGNORE INTO projects (key, created_at) VALUES (?, ?)",
                (project_key, store.now()),
            )
            project_row = connection.execute(
                "SELECT id FROM projects WHERE key = ?", (project_key,)
            ).fetchone()
            project_id = project_row["id"]
            existing = {
                row["response_path"]
                for row in connection.execute(
                    "SELECT response_path FROM attempts"
                    " WHERE response_path IS NOT NULL"
                )
            }

            for row in ledger_rows(project / "runs" / "cost_ledger.tsv"):
                response = row["response"]
                if response in existing:
                    continue
                amount = float(row["cost"]) if row["cost"] else None
                insert_attempt(
                    project_id, row["section"], row["role"], row["label"],
                    row["ts"], amount, response, "cost_ledger.tsv",
                )
                existing.add(response)

            for path in response_files(project):
                response = str(path)
                if response in existing:
                    continue
                insert_attempt(
                    project_id, section_of(path, project), "unknown", path.name,
                    "", cost_of(path), response, "envelope",
                )
                existing.add(response)
    finally:
        connection.close()

    return imported


def stored_totals(project_dir):
    """Per-section totals from every attempt in this project's store."""
    connection = store.connect(store.default_path(project_dir))
    try:
        return {
            row["section"]: float(row["cost"])
            for row in connection.execute(
                "SELECT COALESCE(t.key, '(project)') AS section,"
                " SUM(COALESCE(a.cost_usd, 0)) AS cost"
                " FROM attempts a LEFT JOIN tasks t ON t.id = a.task_id"
                " GROUP BY COALESCE(t.key, '(project)')"
            )
        }
    finally:
        connection.close()


def stored_attempts(project_dir):
    """Attempts in report order, with sections resolved through task_id."""
    connection = store.connect(store.default_path(project_dir))
    try:
        return list(connection.execute(
            "SELECT a.started_at, COALESCE(t.key, '(project)') AS section,"
            " a.role_key, a.label, a.cli, a.cost_usd, a.input_tokens,"
            " a.output_tokens FROM attempts a"
            " LEFT JOIN tasks t ON t.id = a.task_id"
            " ORDER BY a.started_at, a.id"
        ))
    finally:
        connection.close()


def report_store(project_dir):
    per_section = stored_totals(project_dir)
    for section in sorted(per_section):
        print(f"{section}\t{per_section[section]:.4f}")
    print(f"TOTAL\t{sum(per_section.values()):.4f}")

    def present(value):
        return "-" if value is None else str(value)

    for row in stored_attempts(project_dir):
        stamp = "-"
        if row["started_at"] is not None:
            stamp = datetime.fromtimestamp(
                row["started_at"], timezone.utc
            ).strftime("%Y-%m-%dT%H:%M:%SZ")
        amount = "-" if row["cost_usd"] is None else f"{row['cost_usd']:.4f}"
        print("\t".join((
            "ATTEMPT", stamp, row["section"], row["role_key"],
            present(row["label"]), present(row["cli"]), amount,
            present(row["input_tokens"]), present(row["output_tokens"]),
        )))


def totals(project_dir, ledger_path):
    """Per-section and project totals, counting each dispatch exactly once."""
    per_section = {}
    counted = set()

    def add(section, amount):
        per_section[section] = per_section.get(section, 0.0) + amount

    for row in ledger_rows(ledger_path):
        if row["response"]:
            counted.add(row["response"])
        if not row["cost"]:
            continue
        try:
            add(row["section"], float(row["cost"]))
        except ValueError:
            continue

    # Anything the ledger never saw: dispatches from before it existed, and
    # dispatches whose cost the older harness discarded.
    for path in response_files(project_dir):
        key = str(path)
        if key in counted:
            continue
        amount = cost_of(path)
        if amount is None:
            continue
        add(section_of(path, project_dir), amount)

    return per_section


def main(argv):
    if len(argv) >= 3 and argv[1] == "one":
        amount = cost_of(argv[2])
        print("" if amount is None else f"{amount:.6f}")
        return 0
    if (len(argv) in (4, 5) and argv[1] == "total"
            and argv[3].endswith(".tsv")):
        per_section = totals(argv[2], argv[3])
        wanted = argv[4] if len(argv) > 4 else ""
        if wanted:
            print(f"{per_section.get(wanted, 0.0):.4f}")
        else:
            print(f"{sum(per_section.values()):.4f}")
        return 0
    if len(argv) in (3, 4) and argv[1] == "total":
        import_legacy(argv[2])
        per_section = stored_totals(argv[2])
        wanted = argv[3] if len(argv) == 4 else ""
        if wanted:
            print(f"{per_section.get(wanted, 0.0):.4f}")
        else:
            print(f"{sum(per_section.values()):.4f}")
        return 0
    if len(argv) == 3 and argv[1] == "report":
        import_legacy(argv[2])
        report_store(argv[2])
        return 0
    if len(argv) == 3 and argv[1] == "import":
        print(f"imported={import_legacy(argv[2])}")
        return 0
    print("usage: cost.py one <response.json>", file=sys.stderr)
    print("       cost.py total <project_dir> [section]", file=sys.stderr)
    print("       cost.py total <project_dir> <ledger> [section]", file=sys.stderr)
    print("       cost.py report <project_dir>", file=sys.stderr)
    print("       cost.py import <project_dir>", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
