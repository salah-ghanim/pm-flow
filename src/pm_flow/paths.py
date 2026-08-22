"""Every path pm-flow knows, defined once.

This module exists because of what it cost not to have it. Renaming the flow
directory from `agentic/` to `.agentic/` touched 118 references across shell
scripts, personas, task files, tests and documentation - and still missed 39
*recorded* paths inside project state, because those were written at runtime by
code that had built them from its own local idea of the layout. The layout was
knowledge held in dozens of places, so moving it was a search-and-replace with a
long tail of things that only broke later.

So the layout lives here, and both languages read it from here. zsh consumes it
through `--shell`, which prints assignments to eval; python imports it. Adding a
derived path means adding one property, and moving the flow directory means
editing one constant.

Four roots, and keeping them distinct is the point:

    engine_root   the flow itself - scripts, default personas, tasks, domains.
                  Shipped with the package, never written to, never edited.
    repo_root     the repository being worked on.
    flow_dir      project data inside that repository: config, overrides, state.
    project_dir   one project workspace inside the flow directory.

The engine/data split is what lets the engine be a versioned package rather than
a copy in every repository. Anything that blurs it puts us back to copying.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

# The one constant that moved this turn. Hidden, like .idea and .vscode: the
# flow is workspace machinery, not part of the product being built.
DIR_NAME = ".agentic"
FLOW_SUBDIR = "pm_flow"
LEGACY_DIR_NAME = "agentic"

# Names of things inside a project workspace, so no caller spells them.
RUNS = "runs"
SECTIONS = "sections"
STATE = "project_state"
CYCLES = "cycles"
STORE_FILE = "pm_flow.db"
CONFIG_FILE = "config.json"
PROJECT_KEY_FILE = ".project-key"
INSTALL_RECORD = Path(".pm-flow") / "MANIFEST"


def engine_root() -> Path:
    """Where the engine's own files live.

    Installed, this is the package's `engine/` directory. Running from a
    checkout it is `template/.agentic/pm_flow`. Resolved by looking, so a
    developer working in a clone and a user running an installed package take
    the same code path.
    """
    override = os.environ.get("PM_FLOW_ENGINE_ROOT")
    if override:
        return Path(override)

    packaged = Path(__file__).resolve().parent / "engine"
    if (packaged / "pm_flow.sh").is_file():
        return packaged

    # A source checkout: src/pm_flow/paths.py -> repo root -> template/...
    checkout = (Path(__file__).resolve().parent.parent.parent
                / "template" / DIR_NAME / FLOW_SUBDIR)
    if (checkout / "pm_flow.sh").is_file():
        return checkout
    return packaged


def find_repo_root(start: Path | None = None) -> Path:
    """The repository a command was invoked in.

    Walks up looking for a flow directory first and a `.git` second, so running
    inside a subdirectory of a project behaves the way every other repo-scoped
    tool does.
    """
    override = os.environ.get("PM_FLOW_REPO_ROOT")
    if override:
        return Path(override).resolve()

    current = (start or Path.cwd()).resolve()
    for candidate in (current, *current.parents):
        if (candidate / DIR_NAME / FLOW_SUBDIR).is_dir():
            return candidate
        if (candidate / LEGACY_DIR_NAME / FLOW_SUBDIR).is_dir():
            return candidate
    for candidate in (current, *current.parents):
        if (candidate / ".git").exists():
            return candidate
    return current


class Paths:
    """The layout of one repository, and optionally one project inside it."""

    def __init__(self, repo_root: Path | str | None = None,
                 project_key: str | None = None):
        self.repo_root = Path(repo_root).resolve() if repo_root else find_repo_root()
        self._project_key = project_key

    # -- the flow directory --------------------------------------------------

    @property
    def flow_dir(self) -> Path:
        """Project data. Falls back to the pre-rename location so a repository
        that has not been migrated is still readable rather than invisible."""
        current = self.repo_root / DIR_NAME / FLOW_SUBDIR
        if current.is_dir():
            return current
        legacy = self.repo_root / LEGACY_DIR_NAME / FLOW_SUBDIR
        if legacy.is_dir():
            return legacy
        return current

    @property
    def is_legacy_layout(self) -> bool:
        return self.flow_dir.parent.name == LEGACY_DIR_NAME

    @property
    def config_file(self) -> Path:
        return self.flow_dir / CONFIG_FILE

    @property
    def install_record(self) -> Path:
        return self.flow_dir / INSTALL_RECORD

    # -- one project ---------------------------------------------------------

    @property
    def project_key(self) -> str:
        if self._project_key:
            return self._project_key
        from_env = os.environ.get("PM_FLOW_PROJECT")
        if from_env:
            return from_env
        marker = self.flow_dir / PROJECT_KEY_FILE
        try:
            return marker.read_text().splitlines()[0].strip()
        except (OSError, IndexError):
            return ""

    @property
    def project_dir(self) -> Path:
        return self.flow_dir / self.project_key

    @property
    def runs_dir(self) -> Path:
        return self.project_dir / RUNS

    @property
    def sections_dir(self) -> Path:
        return self.project_dir / SECTIONS

    @property
    def state_dir(self) -> Path:
        return self.project_dir / STATE

    @property
    def store(self) -> Path:
        return self.runs_dir / STORE_FILE

    def section_dir(self, key: str) -> Path:
        return self.sections_dir / key

    def cycle_dir(self, section_key: str, cycle: int) -> Path:
        return self.section_dir(section_key) / CYCLES / f"{cycle:03d}"

    # -- crossing the boundary ------------------------------------------------

    def relative(self, path: Path | str) -> str:
        """A path as the repository sees it.

        Resolved on both sides before comparing. That is not defensive: on macOS
        a temporary directory is reached through a symlink, so a path built from
        one and a path built from the other are different strings for the same
        file, and a rule that compares them textually silently fails to match.
        """
        target = Path(path)
        try:
            return str(target.resolve().relative_to(self.repo_root))
        except ValueError:
            return str(target)

    # -- path macros ---------------------------------------------------------
    #
    # Borrowed from IntelliJ, which solved this a long time ago. A path written
    # to disk is stored against a named root - `$PROJECT$/runs/...` - and
    # expanded when read. Nothing persisted then depends on where the roots
    # actually are, so moving one is a change to this file and nothing else.
    #
    # This is not theoretical. Renaming the flow directory left 39 recorded
    # paths pointing at a location that no longer existed, each written by code
    # that had built it from its own idea of the layout. Sections whose run
    # directory cannot be found are sections the flow will not act on, so the
    # project looked intact and would not move. Macros make that class of bug
    # impossible rather than merely fixed.
    #
    # Ordered longest-root-first so the most specific root wins: a path under
    # the project directory contracts to $PROJECT$, not to $REPO$.

    def _macro_roots(self) -> list[tuple[str, Path]]:
        roots = []
        if self.project_key:
            roots.append(("$PROJECT$", self.project_dir))
        roots.append(("$FLOW$", self.flow_dir))
        roots.append(("$ENGINE$", engine_root()))
        roots.append(("$REPO$", self.repo_root))
        roots.append(("$HOME$", Path.home()))
        return sorted(roots, key=lambda pair: len(str(pair[1])), reverse=True)

    def contract(self, path: Path | str) -> str:
        """An absolute path in the form that is safe to write down."""
        target = Path(path)
        try:
            resolved = target.resolve()
        except OSError:
            resolved = target
        for name, root in self._macro_roots():
            try:
                relative = resolved.relative_to(root.resolve())
            except (ValueError, OSError):
                continue
            return name if str(relative) == "." else f"{name}/{relative.as_posix()}"
        return str(resolved)

    def expand(self, stored: str) -> Path:
        """A stored path, resolved against this repository's roots."""
        text = (stored or "").strip()
        for name, root in self._macro_roots():
            if text == name:
                return root
            if text.startswith(name + "/"):
                return root / text[len(name) + 1:]
        candidate = Path(text)
        # A path with no macro is either already absolute or - the pre-macro
        # form - relative to the repository root.
        return candidate if candidate.is_absolute() else self.repo_root / candidate

    def as_env(self) -> dict:
        """The layout as environment variables, for the shell half of the flow."""
        values = {
            "PM_FLOW_DIR_NAME": DIR_NAME,
            "PM_FLOW_ENGINE_ROOT": str(engine_root()),
            "PM_FLOW_REPO_ROOT": str(self.repo_root),
            "PM_FLOW_FLOW_DIR": str(self.flow_dir),
        }
        if self.project_key:
            values.update({
                "PM_FLOW_PROJECT": self.project_key,
                "PM_FLOW_PROJECT_DIR": str(self.project_dir),
                "PM_FLOW_RUNS_DIR": str(self.runs_dir),
                "PM_FLOW_SECTIONS_DIR": str(self.sections_dir),
                "PM_FLOW_STATE_DIR": str(self.state_dir),
                "PM_FLOW_STORE": str(self.store),
            })
        return values


def shell_quote(value: str) -> str:
    return "'" + value.replace("'", "'\\''") + "'"


def main(argv) -> int:
    parser = argparse.ArgumentParser(description="Resolve pm-flow's paths.")
    parser.add_argument("--repo")
    parser.add_argument("--project")
    parser.add_argument("--shell", action="store_true",
                        help="print assignments to eval in zsh")
    parser.add_argument("--get", help="print one path and exit")
    args = parser.parse_args(argv[1:])

    paths = Paths(args.repo, args.project)

    if args.get:
        value = paths.as_env().get(args.get.upper()) or \
            paths.as_env().get(f"PM_FLOW_{args.get.upper()}")
        if value is None:
            print(f"unknown path: {args.get}", file=sys.stderr)
            return 1
        print(value)
        return 0

    for key, value in paths.as_env().items():
        print(f"{key}={shell_quote(value)}" if args.shell else f"{key}={value}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
