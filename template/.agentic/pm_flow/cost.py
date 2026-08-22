"""What a dispatch cost, read back out of its response envelope.

Two things make this less trivial than reading one key.

A *successful* claude dispatch publishes the CLI's own JSON, so `total_cost_usd`
sits at the top level. A *failed* one does not: the harness wraps whatever the
CLI emitted as a string in `result`, and the cost ends up nested inside that
string with no top-level key. Those are exactly the dispatches worth counting -
a call that died after the model had already answered is paid for and bought
nothing - so the nested form is parsed too, with a regex as the last resort.

The second problem is history. The ledger only knows about dispatches made since
it existed, and a budget that starts from zero on a project already deep into its
spend will authorise the whole budget again. So the total is the ledger plus
every response envelope on disk that the ledger has never seen.
"""

import json
import re
import sys
from pathlib import Path

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
            "section": fields[1],
            "cost": fields[4],
            "response": fields[5] if len(fields) > 5 else "",
        })
    return rows


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
    if len(argv) >= 4 and argv[1] == "total":
        per_section = totals(argv[2], argv[3])
        wanted = argv[4] if len(argv) > 4 else ""
        if wanted:
            print(f"{per_section.get(wanted, 0.0):.4f}")
        else:
            print(f"{sum(per_section.values()):.4f}")
        return 0
    if len(argv) >= 4 and argv[1] == "report":
        per_section = totals(argv[2], argv[3])
        for section in sorted(per_section):
            print(f"{section}\t{per_section[section]:.4f}")
        print(f"TOTAL\t{sum(per_section.values()):.4f}")
        return 0
    print("usage: cost.py one <response.json>", file=sys.stderr)
    print("       cost.py total <project_dir> <ledger> [section]", file=sys.stderr)
    print("       cost.py report <project_dir> <ledger>", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
