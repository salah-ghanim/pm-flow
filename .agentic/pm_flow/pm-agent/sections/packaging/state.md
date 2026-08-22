# packaging section PM state

## Objective

- Run the engine from an installed, per-project Python package while keeping only mutable project data in `.agentic/`, then remove copy-versioning machinery and migrate existing installs without losing state.

## Owned paths

- `pyproject.toml`
- `src/**`
- `install.sh`
- `MANIFEST`
- `template/.agentic/pm_flow/pm_flow.sh`
- `template/.agentic/pm_flow/upgrade.py`
- `template/.agentic/pm_flow/.gitignore`
- `tests/**`
- `.gitignore`

## Plan

- First prove the installed shell entry reads repository data from the invoked repository and packaged defaults from the wheel, with no copied engine.
- Then move dispatch and persona overlays across the same engine/data boundary.
- Replace installation with project-data creation and a lossless legacy migration; delete MANIFEST, upgrade.py, and copy lifecycle code.
- Close with independent-version, upgrade-immutability, migration-equivalence, and full-suite probes against installed artifacts.

## Decisions and evidence

- `green-suite/handoff.md` records six PASS groups across three full runs and requires fixture ticks to drain project-level governance work.
- `worktree-isolation/handoff.md` records isolated section worktrees and safe merge-back; simultaneous dispatch is not required by packaging.
- Commit `b864674` provides `pyproject.toml`, `pm_flow.cli`, `pm_flow.paths`, wheel package data, and a console entry point.
- Cycle 001 is `NO_GO`: its focused packaged-layout proof passed and caught a project-data mutation, but the exact full-suite command inherited PM-flow selectors and exited before any PASS group.
- Cycle 002 is `NO_GO`: both exact full-suite commands exited 0 with the same seven PASS groups, and a disposable mutation disabling the new selector cleanup was caught. The exact `zsh tests/packaged_layout_test.sh` command exited 1 before any of its six PASS groups because `uv build` panicked while initializing macOS system configuration. The returned implementation remains uncommitted.
- The Cycle 002 developer notes that redirecting to a fresh cache requires network to fetch the wheel build backend. That exchanges caller-cache dependence for an external dependency and does not meet the hermetic exact-command criterion.

## Current assignment

- None. Two consecutive rejected cycles meet `escalation.failures_before_consultant = 2`; prepare consultant escalation with the exact `uv` panic, the cache/network dependency, the successful seven-group selector-isolation runs, and the caught mutation. Do not re-issue the same assignment.

## Dependencies

- green-suite: done; full suite completion is established.
- worktree-isolation: done; section work and accepted merge-back are isolated.
