#!/usr/bin/env python3
"""The state service's command line. Every command prints one JSON document.

    python3 <flow>/state_service/cli.py migrate --db <store> --dry-run
    python3 <flow>/state_service/cli.py migrate --db <store> --apply
    python3 <flow>/state_service/cli.py apply --db <store> --request <json-file>
    python3 <flow>/state_service/cli.py timeline log --db <store> --project <key> --timeline <key>
    python3 <flow>/state_service/cli.py timeline projection --db <store> --project <key> --timeline <key>
    python3 <flow>/state_service/cli.py timeline verify --db <store> --project <key> --timeline <key>

A refused request prints `{"error": code, "detail": message}` and exits 1.
`timeline verify` prints its report either way and exits 1 when it does not
match.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path

# Run as a script, only this file's directory is on sys.path; `store` and the
# `state_service` package both live one level up, in the engine directory.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import store  # noqa: E402
from state_service import migrate, projection, service  # noqa: E402
from state_service.errors import INVALID_CONTRACT, StateError  # noqa: E402


def command_migrate(args) -> tuple[dict, int]:
    if not args.db:
        raise migrate.MigrationError("--db is required")
    return (migrate.plan(args.db) if args.dry_run else migrate.apply(args.db)), 0


def command_apply(args) -> tuple[dict, int]:
    try:
        request = json.loads(Path(args.request).read_text(encoding="utf-8"))
    except OSError as error:
        raise StateError(INVALID_CONTRACT,
                         f"cannot read request file {args.request}: {error.strerror}") from error
    except ValueError as error:
        raise StateError(INVALID_CONTRACT, f"request file is not JSON: {error}") from error
    return service.apply(args.db, request), 0


def command_timeline(args) -> tuple[dict, int]:
    connection = service.open_store(args.db)
    try:
        # One read snapshot, so a commit landing mid-command cannot make the
        # log, the stored hash and the live rows disagree.
        connection.execute("BEGIN")
        timeline = service.resolve_timeline(connection, args.project, args.timeline)
        document = {"project": args.project, "timeline": args.timeline}
        if args.timeline_command == "log":
            return {**document, **service.log(connection, timeline)}, 0
        if args.timeline_command == "projection":
            whole, tables = projection.digests(connection, timeline["id"])
            return {**document, "head_seq": timeline["head_seq"],
                    "projection_hash": whole, "tables": tables}, 0
        report = projection.verify(connection, timeline["id"])
        return {**document, **report}, 0 if report["match"] else 1
    finally:
        connection.rollback()
        connection.close()


def _db_option(parser) -> None:
    # Accepted on either side of the command; SUPPRESS keeps the subcommand
    # from overwriting a --db given before it.
    parser.add_argument("--db", default=argparse.SUPPRESS, help="path to the store")


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="state_service/cli.py")
    parser.add_argument("--db", help="path to the store")
    commands = parser.add_subparsers(dest="command", required=True)

    migrate_parser = commands.add_parser(
        "migrate", help="bring a store to this engine's schema version")
    _db_option(migrate_parser)
    mode = migrate_parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--dry-run", action="store_true",
                      help="report the pending steps without writing")
    mode.add_argument("--apply", action="store_true",
                      help="migrate, backing the store up before each step")
    migrate_parser.set_defaults(handler=command_migrate)

    apply_parser = commands.add_parser(
        "apply", help="commit one versioned request as one transaction")
    _db_option(apply_parser)
    apply_parser.add_argument("--request", required=True, help="request JSON file")
    apply_parser.set_defaults(handler=command_apply)

    timeline_parser = commands.add_parser("timeline", help="read a timeline")
    timeline_commands = timeline_parser.add_subparsers(dest="timeline_command", required=True)
    for name, help_text in (
            ("log", "committed transactions in sequence order"),
            ("projection", "projection hash and per-table digests of the live rows"),
            ("verify", "replay the log and compare with the stored and live hashes")):
        sub = timeline_commands.add_parser(name, help=help_text)
        _db_option(sub)
        sub.add_argument("--project", required=True, help="project key")
        sub.add_argument("--timeline", required=True, help="timeline key")
        sub.set_defaults(handler=command_timeline)

    args = parser.parse_args(argv)
    try:
        document, status = args.handler(args)
    except StateError as error:
        document, status = error.document(), 1
    except migrate.MigrationError as error:
        document, status = {"error": "migration_failed", "detail": str(error)}, 1
    except SystemExit as error:
        # store.connect refuses a newer store or a failed backup this way.
        document, status = {"error": "migration_failed", "detail": str(error.code)}, 1
    except (sqlite3.Error, OSError) as error:
        code = "migration_failed" if args.command == "migrate" else "store_error"
        document, status = {"error": code, "detail": str(error)}, 1
    print(store.dumps(document))
    return status


if __name__ == "__main__":
    sys.exit(main())
