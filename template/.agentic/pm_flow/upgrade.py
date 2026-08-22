#!/usr/bin/env python3
"""What version is installed, what changed upstream, and what you edited.

An install used to be unversioned. Reinstalling was the only upgrade path, it
overwrote whatever it felt like, and nothing recorded what had been installed or
whether you had since edited it. On a flow directory shared by ten project
workspaces that is not a safe operation to guess at.

So an install records the manifest it was made from. Three facts then fall out of
comparing that record against a new manifest, and the third is the one that
matters:

    added      in the new manifest, not installed
    changed    shipped content differs from what was installed
    modified   installed content differs from what *we* installed - your edit

An upgrade replaces `engine` files, leaves `seed` files alone, and refuses to
touch anything in `modified` unless told to. Losing an edit you made to a role
persona is worse than running a version behind.

    upgrade.py status                    what is installed
    upgrade.py check  --new <manifest>   what an upgrade would do
    upgrade.py apply  --new <manifest> --source <dir>
    upgrade.py record --new <manifest>   stamp an install (the installer calls this)

Standard library only.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sys
import time
from pathlib import Path

FLOW = Path(__file__).resolve().parent
INSTALLED = FLOW / ".pm-flow" / "manifest.json"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(65536), b""):
                digest.update(chunk)
    except OSError:
        return ""
    return digest.hexdigest()


def load(path) -> dict:
    try:
        return json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return {}


def installed_manifest() -> dict:
    return load(INSTALLED)


def target_for(rel: str) -> Path:
    """Where a manifest path lands, relative to the repository root.

    The manifest is rooted at `template/`, and the flow lives at
    `<repo>/.agentic/pm_flow`, so the repository root is two levels up.
    """
    repo = FLOW.parent.parent
    return repo / rel


def compare(new: dict, old: dict) -> dict:
    """Classify every file in the new manifest against what is on disk."""
    old_by_path = {entry["path"]: entry for entry in old.get("files", [])}
    report = {"added": [], "changed": [], "unchanged": [], "modified": [],
              "seed_kept": [], "removed": [], "project_template": []}

    for entry in new.get("files", []):
        rel = entry["path"]
        kind = entry.get("class", "engine")
        target = target_for(rel)
        previous = old_by_path.get(rel)
        on_disk = sha256(target) if target.is_file() else ""

        # The per-project scaffold is a source template, rendered into
        # `<project_key>/` at install time and never placed at its own path. An
        # upgrade must not create it there; a *new* project picks up the new
        # version on its own.
        if kind == "project":
            if previous and previous.get("sha256") != entry["sha256"]:
                report["project_template"].append(rel)
            continue

        if not on_disk:
            report["added"].append(rel)
            continue

        # A seed file is yours once written. config.json holds model bindings
        # and budgets; replacing it on upgrade would silently re-bind every role.
        if kind == "seed":
            report["seed_kept"].append(rel)
            continue

        # Edited since we installed it. Never clobbered without --force.
        if previous and previous.get("sha256") and on_disk != previous["sha256"]:
            if on_disk != entry["sha256"]:
                report["modified"].append(rel)
            else:
                report["unchanged"].append(rel)
            continue

        if on_disk != entry["sha256"]:
            report["changed"].append(rel)
        else:
            report["unchanged"].append(rel)

    new_paths = {entry["path"] for entry in new.get("files", [])}
    for rel in old_by_path:
        if rel not in new_paths:
            report["removed"].append(rel)

    return report


def cmd_status(args) -> int:
    current = installed_manifest()
    if not current:
        print("no install record found")
        print(f"  expected at: {INSTALLED}")
        print("  this install predates versioning; reinstall to stamp it")
        return 1
    print(f"pm-flow {current.get('version', 'unknown')}")
    stamped = current.get("installed_at")
    if stamped:
        print(f"  installed {time.strftime('%Y-%m-%d %H:%M:%SZ', time.gmtime(stamped))}")
    print(f"  {len(current.get('files', []))} files tracked")

    # Only engine files. A seed file is yours by design - config.json carries
    # your bindings, projects.md gains a line per workspace - so reporting them
    # as drift would mean every healthy install looks modified.
    drifted = [
        entry["path"] for entry in current.get("files", [])
        if entry.get("class", "engine") == "engine"
        and target_for(entry["path"]).is_file()
        and sha256(target_for(entry["path"])) != entry.get("sha256")
    ]
    if drifted:
        print(f"  {len(drifted)} file(s) edited since install:")
        for rel in drifted[:20]:
            print(f"    {rel}")
        if len(drifted) > 20:
            print(f"    ... and {len(drifted) - 20} more")
    return 0


def render(report: dict, new: dict, old: dict) -> None:
    old_version = old.get("version", "unversioned")
    new_version = new.get("version", "unknown")
    if old_version == new_version:
        print(f"pm-flow {new_version} (already current)")
    else:
        print(f"pm-flow {old_version} -> {new_version}")

    for key, label in (("added", "add"), ("changed", "update")):
        if report[key]:
            print(f"\n{label} ({len(report[key])}):")
            for rel in report[key]:
                print(f"  {rel}")
    if report["seed_kept"]:
        print(f"\nkeep, yours ({len(report['seed_kept'])}):")
        for rel in report["seed_kept"]:
            print(f"  {rel}")
    if report["modified"]:
        print(f"\nEDITED SINCE INSTALL - not touched without --force "
              f"({len(report['modified'])}):")
        for rel in report["modified"]:
            print(f"  {rel}")
    if report["project_template"]:
        print(f"\nnew projects only ({len(report['project_template'])}):")
        for rel in report["project_template"]:
            print(f"  {rel}")
    if report["removed"]:
        print(f"\nno longer shipped ({len(report['removed'])}):")
        for rel in report["removed"]:
            print(f"  {rel}")
    if not any(report[k] for k in ("added", "changed", "modified", "removed",
                                   "project_template")):
        print("\nnothing to do")


def cmd_check(args) -> int:
    new = load(args.new)
    if not new:
        print(f"could not read manifest: {args.new}", file=sys.stderr)
        return 2
    render(compare(new, installed_manifest()), new, installed_manifest())
    return 0


def cmd_apply(args) -> int:
    new = load(args.new)
    if not new:
        print(f"could not read manifest: {args.new}", file=sys.stderr)
        return 2
    source = Path(args.source)
    if not source.is_dir():
        print(f"not a directory: {source}", file=sys.stderr)
        return 2

    old = installed_manifest()
    report = compare(new, old)
    if report["modified"] and not args.force:
        print("refusing to upgrade: these are edited and would be overwritten\n")
        for rel in report["modified"]:
            print(f"  {rel}")
        print("\nre-run with --force to replace them, or revert them first.")
        return 1

    by_path = {entry["path"]: entry for entry in new["files"]}
    applied = 0
    for rel in report["added"] + report["changed"] + (
            report["modified"] if args.force else []):
        entry = by_path[rel]
        src = source / rel
        if not src.is_file():
            print(f"  missing from source, skipped: {rel}", file=sys.stderr)
            continue
        dst = target_for(rel)
        dst.parent.mkdir(parents=True, exist_ok=True)
        # Written beside the target and renamed, so an interrupted upgrade never
        # leaves a half-written script the next run would try to execute.
        tmp = dst.with_name(f".{dst.name}.upgrade.{os.getpid()}")
        shutil.copyfile(src, tmp)
        if entry.get("executable"):
            tmp.chmod(tmp.stat().st_mode | 0o111)
        os.replace(tmp, dst)
        applied += 1

    record(new)
    print(f"upgraded to {new.get('version')}: {applied} file(s) written")
    if report["seed_kept"]:
        print(f"{len(report['seed_kept'])} file(s) left as yours")
    return 0


def record(new: dict) -> None:
    """Stamp what was installed, with the hashes as installed."""
    stamped = dict(new)
    stamped["installed_at"] = time.time()
    files = []
    for entry in new.get("files", []):
        target = target_for(entry["path"])
        files.append({**entry, "sha256": sha256(target) if target.is_file()
                      else entry.get("sha256", "")})
    stamped["files"] = files
    INSTALLED.parent.mkdir(parents=True, exist_ok=True)
    tmp = INSTALLED.with_name(f".{INSTALLED.name}.{os.getpid()}")
    tmp.write_text(json.dumps(stamped, indent=2, sort_keys=True) + "\n")
    os.replace(tmp, INSTALLED)


def cmd_record(args) -> int:
    new = load(args.new)
    if not new:
        print(f"could not read manifest: {args.new}", file=sys.stderr)
        return 2
    record(new)
    print(f"recorded pm-flow {new.get('version')} "
          f"({len(new.get('files', []))} files)")
    return 0


def main(argv) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("status"); p.set_defaults(func=cmd_status)

    p = sub.add_parser("check")
    p.add_argument("--new", required=True)
    p.set_defaults(func=cmd_check)

    p = sub.add_parser("apply")
    p.add_argument("--new", required=True)
    p.add_argument("--source", required=True)
    p.add_argument("--force", action="store_true")
    p.set_defaults(func=cmd_apply)

    p = sub.add_parser("record")
    p.add_argument("--new", required=True)
    p.set_defaults(func=cmd_record)

    args = parser.parse_args(argv[1:])
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
