#!/usr/bin/env python3
"""The state service's command line. Every command prints one JSON document.

    python3 <flow>/state_service/cli.py migrate --db <store> --dry-run
    python3 <flow>/state_service/cli.py migrate --db <store> --apply

A failure prints `{"error": code, "detail": message}` and exits non-zero.
"""

from __future__ import annotations

import argparse
import sqlite3
import sys
from pathlib import Path

# Run as a script, only this file's directory is on sys.path; `store` and the
# `state_service` package both live one level up, in the engine directory.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import store  # noqa: E402
from state_service import migrate  # noqa: E402


def command_migrate(args) -> dict:
    return migrate.plan(args.db) if args.dry_run else migrate.apply(args.db)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="state_service/cli.py")
    parser.add_argument("--db", help="path to the store")
    commands = parser.add_subparsers(dest="command", required=True)

    migrate_parser = commands.add_parser(
        "migrate", help="bring a store to this engine's schema version")
    # Accepted on either side of the command; SUPPRESS keeps the subcommand
    # from overwriting a --db given before it.
    migrate_parser.add_argument("--db", default=argparse.SUPPRESS,
                                help="path to the store")
    mode = migrate_parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--dry-run", action="store_true",
                      help="report the pending steps without writing")
    mode.add_argument("--apply", action="store_true",
                      help="migrate, backing the store up before each step")
    migrate_parser.set_defaults(handler=command_migrate)

    args = parser.parse_args(argv)
    try:
        if not args.db:
            raise migrate.MigrationError("--db is required")
        result = args.handler(args)
    except (migrate.MigrationError, sqlite3.Error, OSError) as error:
        detail = str(error)
    except SystemExit as error:
        # store.connect refuses a newer store or a failed backup this way.
        detail = str(error.code)
    else:
        print(store.dumps(result))
        return 0
    print(store.dumps({"error": "migration_failed", "detail": detail}))
    return 1


if __name__ == "__main__":
    sys.exit(main())
