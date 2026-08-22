# packaging section PM state

## Objective

- Run the engine from an installed, per-project Python package while keeping
  only mutable project data in `.agentic/`, then remove copy-versioning
  machinery and migrate existing installs without losing state.

## Owned paths

- `pyproject.toml`, `src/**`, `install.sh`, `MANIFEST`, `template/**`,
  `tests/**`, `.gitignore`, and `README.md`.

## Plan

- First prove the installed shell entry reads repository data from the invoked
  repository and packaged defaults from the wheel, with no copied engine.
- Then move dispatch and persona overlays across the same engine/data boundary.
- Replace installation with project-data creation and a lossless legacy
  migration; delete MANIFEST, upgrade.py, and copy lifecycle code.
- Close with independent-version, upgrade-immutability, migration-equivalence,
  and full-suite probes against installed artifacts.

## Decisions and evidence

- `green-suite/handoff.md` records six PASS groups across three full runs and
  requires fixture ticks to drain project-level governance work.
- `worktree-isolation/handoff.md` records isolated section worktrees and safe
  merge-back; its only unproven point is simultaneous dispatch, which packaging
  does not require.
- Commit `b864674` already provides `pyproject.toml`, `pm_flow.cli`,
  `pm_flow.paths`, wheel package data, and a console entry point. The brief says
  that wheel was run from a clean venv, so rebuilding that scaffold is out of
  scope.
- Current gap: packaged `pm_flow.sh` sets `PROJECT_ROOT` from its own location
  and uses `SCRIPT_DIR` for `.project-key`, config, and project workspaces.
  `pm_flow.cli` already exports `PM_FLOW_ENGINE_ROOT`, `PM_FLOW_REPO_ROOT`, and
  `PM_FLOW_FLOW_DIR`; the shell entry does not yet consume the data roots.
- Cycle 001 starts with no prior accepted cycle. The dirty packaging
  `status.txt`, `summary.txt`, timestamps, and dispatch markers are current
  orchestration state, not uncommitted accepted implementation.

## Current assignment

- Make installed `pm-flow status` and `pm-flow role-prompt pm` operate against a
  fixture whose `.agentic/pm_flow` contains project data only, while the command
  and default persona/domain come from the installed artifact.

## Dependencies

- green-suite: done; full suite completion is established.
- worktree-isolation: done; section work and accepted merge-back are isolated.
