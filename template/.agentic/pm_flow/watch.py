#!/usr/bin/env python3
"""Live view of a pm-flow project: what is running, where, since when.

Read-only. Safe to run against a live driver.

  ./.agentic/pm_flow/watch.py            one shot
  ./.agentic/pm_flow/watch.py -w         refresh every 5s
  ./.agentic/pm_flow/watch.py -w -n 2    refresh every 2s
"""

from __future__ import annotations

import argparse
import json
import os
import sqlite3
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

FLOW = Path(__file__).resolve().parent
BOLD, DIM, RESET = "\033[1m", "\033[2m", "\033[0m"
GREEN, YELLOW, RED, CYAN = "\033[32m", "\033[33m", "\033[31m", "\033[36m"


def project_dir() -> Path:
    key = os.environ.get("PM_FLOW_PROJECT") or (FLOW / ".project-key").read_text().strip()
    return FLOW / key


def read(path: Path, default: str = "") -> str:
    try:
        return path.read_text().strip()
    except OSError:
        return default


def ago(seconds: float) -> str:
    seconds = max(0, int(seconds))
    if seconds < 60:
        return f"{seconds}s"
    if seconds < 3600:
        return f"{seconds // 60}m{seconds % 60:02d}s"
    return f"{seconds // 3600}h{(seconds % 3600) // 60:02d}m"


def format_time(stamp: float) -> str:
    if not stamp:
        return "-"
    return datetime.fromtimestamp(stamp, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def store_rows(project: Path) -> list[dict]:
    """Read attempts without creating or migrating a missing store."""
    db = project / "runs" / "pm_flow.db"
    if not db.is_file():
        return []
    try:
        connection = sqlite3.connect(f"{db.resolve().as_uri()}?mode=ro", uri=True)
        connection.row_factory = sqlite3.Row
        try:
            return [
                {
                    "at": format_time(row["started_at"]),
                    "started": row["started_at"] or 0.0,
                    "section": row["section"],
                    "role": row["role_key"],
                    "label": row["label"] or "-",
                    "cost": float(row["cost"]),
                    "input_tokens": row["input_tokens"],
                    "output_tokens": row["output_tokens"],
                }
                for row in connection.execute(
                    "SELECT a.started_at, COALESCE(t.key, '(project)') AS section,"
                    " a.role_key, a.label, COALESCE(a.cost_usd, 0) AS cost,"
                    " a.input_tokens, a.output_tokens FROM attempts a"
                    " LEFT JOIN tasks t ON t.id = a.task_id"
                    " ORDER BY a.started_at, a.id"
                )
            ]
        finally:
            connection.close()
    except sqlite3.Error:
        return []


def in_flight(project: Path, last_ledger_ts: float):
    """The newest step claim with no ledger row after it is the live dispatch."""
    newest = None
    # Section steps claim under sections/<key>/cycles/<n>/. Project-level work
    # (a portfolio review) claims under project_state/, so globbing only the
    # section path reports a live review as IDLE.
    for pattern in ("sections/*/cycles/*/.claim-*", "project_state/*/*/.claim-*"):
        for claim in project.glob(pattern):
            mtime = claim.stat().st_mtime
            if newest is None or mtime > newest[0]:
                newest = (mtime, claim)
    if newest is None or newest[0] <= last_ledger_ts:
        return None
    mtime, claim = newest
    cycle = claim.parent
    step = claim.name.replace(".claim-", "")
    heartbeat = read(cycle / "heartbeat.txt").splitlines()
    is_section = cycle.parent.parent.parent.name == "sections"
    return {
        "section": cycle.parent.parent.name if is_section else "(project)",
        "cycle": cycle.name,
        "step": step if is_section else "portfolio-review",
        "since": mtime,
        "last_line": heartbeat[-1] if heartbeat else "",
    }


STEP_ROLE = {
    "scope": "pm", "review": "pm", "complete": "pm", "handoff": "pm",
    "develop": "developer", "rescue": "10x_developer",
    "review-rescue": "pm", "escalate": "consultant", "adjudicate": "cpo",
    "portfolio-review": "cpo", "analysis": "pm", "proposals": "consultant",
}


def roles_config() -> dict:
    try:
        return json.loads((FLOW / "config.json").read_text()).get("roles", {})
    except (OSError, ValueError):
        return {}


def seat_label(seat: dict) -> str:
    model = str(seat.get("model", "?"))
    for prefix in ("claude-", "gpt-"):
        if model.startswith(prefix):
            model = model[len(prefix):]
    return f"{seat.get('cli', '?')}/{model} {seat.get('difficulty', '?')}"


def binding_label(role: str) -> str:
    binding = roles_config().get(role)
    if isinstance(binding, list):
        return " + ".join(seat_label(s) for s in binding)
    if isinstance(binding, dict):
        return seat_label(binding)
    return "?"


def md_section(path: Path, heading: str, limit: int = 3) -> str:
    """First lines under a `## <heading>` block, joined."""
    lines, grabbing, out = read(path).splitlines(), False, []
    for line in lines:
        if line.startswith("## "):
            if grabbing:
                break
            grabbing = line[3:].strip().lower().startswith(heading.lower())
            continue
        if grabbing and line.strip():
            out.append(line.strip().lstrip("-* ").strip())
        if len(out) >= limit:
            break
    return " ".join(out)


def latest_cycle(section: Path):
    cycles = sorted(section.glob("cycles/*/"), key=lambda p: p.name)
    if not cycles:
        return None, ""
    last = cycles[-1]
    return last.name, read(last / "decision.txt")


def why_blocked(section: Path, status: str, decision: str) -> str:
    """A status word alone does not tell you whether to intervene."""
    if status == "blocked":
        return md_section(section / "handoff.md", "Outcome", 2)[:150]
    if decision == "NO_GO":
        review = sorted(section.glob("cycles/*/review.md"))
        if review:
            tail = md_section(review[-1], "Decision", 1)
            return tail[:150] if tail else "rejected, see review"
        return "last cycle rejected"
    if status == "waiting-dependencies":
        deps = read(section / "dependency_handoffs.txt").splitlines()
        return "waits on " + ", ".join(Path(d).parent.name for d in deps if d)
    return ""


def driver_alive() -> bool:
    try:
        out = subprocess.run(["pgrep", "-f", "pm_flow.sh"], capture_output=True, text=True)
        return bool(out.stdout.strip())
    except OSError:
        return False


def render(project: Path) -> str:
    rows = store_rows(project)
    spent = sum(r["cost"] for r in rows)
    last_ts = max((r["started"] for r in rows), default=0.0)
    budget = {}
    try:
        budget = json.loads((FLOW / "config.json").read_text()).get("budget", {})
    except (OSError, ValueError):
        pass
    cap = budget.get("max_usd") or 0
    reviews = sum(1 for r in rows if r["role"] == "cpo" and "portfolio review" in r["label"])

    out = [f"{BOLD}pm-flow{RESET}  {project.name}"
           f"{DIM}    {datetime.now().strftime('%H:%M:%S')} local{RESET}", ""]

    live = in_flight(project, last_ts)
    if live:
        role = STEP_ROLE.get(live["step"], "?")
        out.append(f"{GREEN}{BOLD}RUNNING{RESET}  {live['section']}  "
                   f"{live['step']} {live['cycle']}  "
                   f"{CYAN}{ago(time.time() - live['since'])}{RESET}")
        out.append(f"         {BOLD}{role}{RESET}  {binding_label(role)}")
        if live["last_line"]:
            out.append(f"         {DIM}{live['last_line'][:110]}{RESET}")
    elif driver_alive():
        out.append(f"{YELLOW}IDLE{RESET}     driver alive, between dispatches")
    else:
        out.append(f"{RED}STOPPED{RESET}  no driver running")
    out.append("")

    pct = f" ({spent / cap * 100:.0f}%)" if cap else ""
    out.append(f"{BOLD}SPEND{RESET}    ${spent:.2f}"
               + (f" / ${cap:.0f}{pct}" if cap else "")
               + f"    reviews {reviews}")
    out.append("")

    per_section: dict[str, float] = {}
    latest: dict[str, float] = {}
    for r in rows:
        per_section[r["section"]] = per_section.get(r["section"], 0.0) + r["cost"]
        latest[r["section"]] = max(latest.get(r["section"], 0.0), r["started"])

    out.append(f"{BOLD}SECTIONS{RESET}")
    sections = sorted(project.glob("sections/*/"), key=lambda p: p.name)
    for sec in sections:
        status = read(sec / "status.txt", "?")
        if status in {"cancelled", "done"} and per_section.get(sec.name, 0) == 0:
            continue
        spend = per_section.get(sec.name, 0.0)
        seen = latest.get(sec.name, 0.0)
        cycle, decision = latest_cycle(sec)
        colour = {"done": GREEN, "cancelled": DIM, "blocked": YELLOW,
                  "active": CYAN}.get(status, "")
        flag = RED if decision == "NO_GO" else ""
        head = (f"{BOLD}{sec.name}{RESET}  {colour}{status}{RESET}"
                f"  {DIM}cycle {cycle or '-'}{RESET}")
        if decision:
            head += f"  {flag}{decision}{RESET}"
        head += (f"  {DIM}${spend:.0f}"
                 f"  {ago(time.time() - seen) if seen else 'never'}{RESET}")
        out.append(head)

        goal = md_section(sec / "brief.md", "Objective", 2)
        if goal:
            out.append(f"    {DIM}goal {RESET}{goal[:104]}")
        done = md_section(sec / "handoff.md", "Outcome", 2)
        if done:
            out.append(f"    {DIM}done {RESET}{done[:104]}")
        nxt = md_section(sec / "handoff.md", "Next action", 2)
        if nxt:
            out.append(f"    {DIM}next {RESET}{nxt[:104]}")
        reason = why_blocked(sec, status, decision)
        if reason:
            out.append(f"    {YELLOW}why  {RESET}{reason[:104]}")
        out.append("")

    out.append(f"{BOLD}ROLES{RESET}")
    for role in ("cpo", "pm", "developer", "consultant", "10x_developer"):
        if role in roles_config():
            out.append(f"{role:<16}{binding_label(role)}")
    out.append("")

    out.append(f"{BOLD}RECENT{RESET}")
    for r in rows[-8:][::-1]:
        tokens = (f"{r['input_tokens'] if r['input_tokens'] is not None else '-'}in/"
                  f"{r['output_tokens'] if r['output_tokens'] is not None else '-'}out")
        out.append(f"{DIM}{r['at'][11:16]}{RESET}  {r['section']:<26}"
                   f"{r['role']:<11}{r['label'][:30]:<30}${r['cost']:.2f}  {tokens}")
    return "\n".join(out)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("-w", "--watch", action="store_true", help="refresh continuously")
    ap.add_argument("-n", "--interval", type=float, default=5.0, help="refresh seconds")
    args = ap.parse_args()

    project = project_dir()
    if not project.is_dir():
        print(f"no such project: {project}", file=sys.stderr)
        return 1
    if not args.watch:
        print(render(project))
        return 0
    try:
        while True:
            sys.stdout.write("\033[2J\033[H" + render(project) + "\n")
            sys.stdout.flush()
            time.sleep(args.interval)
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
