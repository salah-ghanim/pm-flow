# packaging section PM state

## Objective

- Run the engine from an installed, per-project Python package while keeping only mutable project data in `.agentic/`, then remove copy-versioning machinery and migrate existing installs without losing state.

## Owned paths

- `pyproject.toml`
- `src/pm_flow/cli.py`
- `src/pm_flow/paths.py`
- `src/pm_flow/__init__.py`
- `install.sh`
- `MANIFEST`
- `template/.agentic/pm_flow/pm_flow.sh`
- `template/.agentic/pm_flow/upgrade.py`
- `template/.agentic/pm_flow/.gitignore`
- `tests/pm_flow_test.sh`
- `tests/packaged_layout_test.sh`
- `tests/fixtures/stub_*.zsh`
- `.gitignore`
- `tools/manifest.py`
- `README.md`, only its MANIFEST, manifest-tool, and copy-version passages

## Plan

- Prove the installed shell entry reads repository data from the invoked repository and packaged defaults from the wheel, with no copied engine. Done (003).
- Move dispatch and persona overlays across the same engine/data boundary. Done (004).
- Replace installation with project-data creation and a lossless legacy migration; delete MANIFEST, upgrade.py, and copy lifecycle code. Done (005/006).
- Prove independent per-repository versions and upgrade immutability against installed artifacts. Done (007).
- Remove the stale manifest tool and documentation. Done with corrections owed (008).
- Closeout: apply the 008 corrections, stop `install.sh` leaving `*.pm-flow.template.md` behind, close with the full suite. Cycle 009.

## Decisions and evidence

- `green-suite/handoff.md` establishes full-suite completion; fixture ticks must drain project-level governance work.
- `worktree-isolation/handoff.md` establishes isolated section worktrees and safe merge-back.
- Cycle 003 is `GO`: the focused proof builds through a separate build venv populated from six pinned, hashed, repository-local wheels with index access disabled, then installs only the resulting pm-flow wheel into a clean runtime venv.
- Cycle 004 is `GO`: an installed-artifact dispatch composed packaged base and domain personas with a repository-local overlay at `.agentic/pm_flow/<project>/roles/<role>.md` and recorded matching provenance.
- Cycle 005's data-only installation and lossless migration is on `main`; its `NO_GO` was a flaky timing assertion, replaced in cycle 006 (`GO`) by a two-seat rendezvous.
- Cycle 007 is `GO`: real `0.7.1` and `0.7.2` wheels in separate repository venvs report and run their own versions; upgrading one changes its running version and no byte of its `.agentic/` tree, and the other repository is untouched.
- Cycle 008 is `GO_WITH_CHANGES` (2026-08-23): `tools/manifest.py` deleted, README routes install/upgrade/run through `.venv/bin/pm-flow` and `pip install --upgrade`, thirteenth group executes the documented `version`/`status`/`tick` through the wheel. Owed corrections, all still on `main` at the 009 scope call: README:21-23 says `cd /path/to/repo` then `./install.sh /path/to/repo` but `install.sh` is in the pm-flow checkout, not the wheel; README:81 writes the overlay as `<project>/roles/<role>.md` where `catalog.py:612` resolves `<project_dir>/roles/<role>.md`; `packaged_layout_test.sh:1486-1494` prunes `.git`/`tests`/`.agentic`/`__pycache__` but not `.venv`/`dist`/`build`, and `agent_exec.sh:128` activates a checkout `.venv` when one has `bin/python`.
- `*.pm-flow.template.md` is not project data. `install.sh:541-551` renders the managed block to `<repo>/<stem>.pm-flow.template.md` only to merge it into a pre-existing `AGENTS.md`/`CLAUDE.md`, and nothing reads it afterwards (no reference in `template/.agentic/pm_flow` or either suite; `agents-md/handoff.md:23` deferred it here). Decision: `install.sh` must not leave it behind. The backup and managed-block contract from agents-md is unchanged.
- `install.sh` is not in the wheel (`pyproject.toml` force-includes only `template/.agentic/pm_flow`) and `cli.py` has no `init`. Creating project data needs a pm-flow checkout; the README must say so. Shipping an `init` is outside the brief's acceptance and is not being added here; it is a handoff risk.
- Whether `pm-flow` is this project's name on PyPI is unverified: `curl`/WebFetch to `pypi.org` are denied to this role (probed 2026-08-23 at the 009 scope call). Every install proof uses a locally built wheel. Goes in the handoff as unproven.
- Review-side harness gap, re-probed at the 009 scope call: `zsh tests/packaged_layout_test.sh` → "This command requires approval" under the scoped tier (`DEFAULT_SCOPED_BASH` in `agent_exec.sh:228-258` lists pytest spellings only; no `access.scoped_bash` override in config). No PM review in this project can produce its own test output until `zsh tests/*` is granted to `pm`. The 009 review must say so again and rely on the harness access log plus the pasted outputs, as 008 did.
- Uncommitted at the 009 scope call: only driver bookkeeping (`project_state/sections.md`, `last_dispatch.txt`, `summary.txt`, `updated_at.txt`). No accepted work is uncommitted.

## Current assignment

- Cycle 009: apply the three 008 corrections, remove the `*.pm-flow.template.md` leftover, assert each in the suite, run the four acceptance commands and four mutations. If it is accepted, every brief criterion has evidence and the next scope call answers `COMPLETE`.

## Dependencies

- green-suite: done; full suite completion is established.
- worktree-isolation: done; section work and accepted merge-back are isolated.
