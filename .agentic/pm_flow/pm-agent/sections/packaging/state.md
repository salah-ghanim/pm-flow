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
- The two-failure escalation was archived after dispatch caches were redirected into the writable project run directory, and the failure streak was explicitly reset at Cycle 002. A Cycle 003 scope probe ran the preserved Cycle 002 `zsh tests/packaged_layout_test.sh` with `UV_CACHE_DIR`, `XDG_CACHE_HOME`, and `PIP_CACHE_DIR` all beneath that run directory; it still exited 1 with the same `system-configuration` NULL-object panic. Cache writability did not fix the `uv` initialization failure.
- The viable different path is an offline, repository-local wheelhouse for Hatchling and its transitive build requirements, used through `python3 -m venv` and pip with index access disabled. This removes `uv`, network, and caller-cache state from the focused artifact proof without weakening the installed-wheel boundary.
- Cycle 003 is `GO`: all four exact acceptance commands exited 0. Both focused runs produced the same six packaged-layout PASS groups; both full-suite runs produced the same nine current PASS groups. The assignment's reference to seven full-suite groups was stale, and no group was lost.
- Reviewer mutation probes independently established that removing a locked wheel fails before the first PASS group, redirecting `PROJECT_DIR` to the packaged engine is caught, and disabling full-suite selector cleanup makes the hostile-selector run fail.
- The accepted build path uses a separate build venv populated from six pinned, hashed `py3-none-any` wheels with `--no-index --find-links --require-hashes`, then installs only the newly built pm-flow wheel into a clean runtime venv. `uv`, indexes, caller caches, and checkout installation are not used.

## Current assignment

- Next scope: move dispatch and repository-local persona overlays across the accepted packaged-engine/project-data boundary. Reuse the installed-wheel harness and path model; do not begin installer, migration, MANIFEST, upgrade, or copy-lifecycle removal until dispatch and overlay provenance are proven from the installed artifact.

## Dependencies

- green-suite: done; full suite completion is established.
- worktree-isolation: done; section work and accepted merge-back are isolated.
