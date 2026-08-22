"""The `pm-flow` command.

Thin on purpose. The engine is still zsh, and this does not reimplement it - it
resolves where things are and hands over. What it changes is *where the engine
comes from*: an installed package rather than a copy sitting in the repository
being worked on.

That is the whole point of packaging. One engine per virtual environment,
versioned by the package manager, never edited in place - so upgrading is
`pip install -U pm-flow` and there is nothing to merge, because there is nothing
in the repository to merge against.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

from . import paths as paths_module
from .paths import Paths, engine_root


def _engine_script() -> Path:
    script = engine_root() / "pm_flow.sh"
    if not script.is_file():
        raise SystemExit(
            f"pm-flow's engine is missing: {script}\n"
            "The package may be installed incorrectly; reinstall it."
        )
    return script


def cmd_paths(argv) -> int:
    """Print the resolved layout. Useful on its own, and how zsh reads it."""
    return paths_module.main(["paths"] + list(argv))


def cmd_version(argv) -> int:
    try:
        from importlib.metadata import version
        print(f"pm-flow {version('pm-flow')}")
    except Exception:  # noqa: BLE001 - a source checkout has no distribution
        version_file = Path(__file__).resolve().parent.parent.parent / "VERSION"
        stamp = version_file.read_text().strip() if version_file.is_file() else "unknown"
        print(f"pm-flow {stamp} (source checkout)")
    print(f"  engine: {engine_root()}")
    return 0


def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)

    if not argv or argv[0] in ("-h", "--help", "help"):
        print(__doc__.strip())
        print("\\nUsage:\\n  pm-flow paths [--project <key>] [--shell]"
              "\\n  pm-flow version"
              "\\n  pm-flow <command> [args...]   anything else goes to the engine")
        return 0

    if argv[0] == "paths":
        return cmd_paths(argv[1:])
    if argv[0] in ("version", "--version", "-V"):
        return cmd_version(argv[1:])

    # Everything else is the engine's. The resolved layout is exported so the
    # shell half never has to work out where anything is - one definition,
    # read by both languages.
    project = None
    if argv[0] == "--project" and len(argv) > 1:
        project = argv[1]
        argv = argv[2:]

    layout = Paths(project_key=project)
    environment = dict(os.environ)
    environment.update(layout.as_env())

    command = ["zsh", str(_engine_script())]
    if project:
        command += ["--project", project]
    command += argv

    try:
        return subprocess.call(command, cwd=str(layout.repo_root), env=environment)
    except FileNotFoundError:
        raise SystemExit("zsh is required to run pm-flow's engine and was not found")


if __name__ == "__main__":
    raise SystemExit(main())
