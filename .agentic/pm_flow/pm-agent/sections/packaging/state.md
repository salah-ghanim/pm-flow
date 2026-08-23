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

- Prove the installed shell entry reads repository data from the invoked repository and packaged defaults from the wheel, with no copied engine.
- Move dispatch and persona overlays across the same engine/data boundary.
- Replace installation with project-data creation and a lossless legacy migration; delete MANIFEST, upgrade.py, and copy lifecycle code.
- Prove independent per-repository versions and upgrade immutability against installed artifacts.
- Remove the stale manifest tool and documentation, decide whether instruction prefetch artifacts are project data, and close with the full suite.

## Decisions and evidence

- `green-suite/handoff.md` establishes full-suite completion; fixture ticks must drain project-level governance work.
- `worktree-isolation/handoff.md` establishes isolated section worktrees and safe merge-back.
- Cycle 003 is `GO`: the focused proof builds through a separate build venv populated from six pinned, hashed, repository-local wheels with index access disabled, then installs only the resulting pm-flow wheel into a clean runtime venv. Reviewer mutations caught a missing locked wheel, a wrong project-data root, and inherited selectors.
- Cycle 004 is `GO`: an installed-artifact dispatch composed packaged base and domain personas with a repository-local overlay and recorded matching provenance. Four mutations independently caught wrong configuration, a missing local layer, missing provenance, and reversed order.
- Cycle 005's data-only installation and lossless migration implementation passed both focused runs, the ordinary full suite, and all four mutation probes. Its review was `NO_GO` only because the hostile full suite hit the pre-existing flaky consultant timing assertion once; the implementation is present on `main`.
- Cycle 006 is `GO`: the timing inference was replaced with a direct two-seat rendezvous. The ordinary suite and three hostile-environment runs emitted the same ten PASS groups, and serializing the seats failed at the concurrency assertion with both proposals and the adjudication prompt present.
- Cycle 007 is `GO`: two disposable source copies produced real `0.7.1` and `0.7.2` wheels installed into separate repository venvs. Both installed commands reported their own versions and advanced their data-only projects; upgrading the existing older venv changed its running version without changing its complete `.agentic/` tree, then continued the existing cycle. Both focused runs emitted the ten prior groups plus two new groups, both full-suite runs emitted the same ten groups, and reviewer mutations caught a shared venv, an old-version upgrade, and a post-upgrade project-data edit at their intended assertions.
- A fresh install contains mutable project data and repository instructions, not engine scripts, packaged defaults, MANIFEST, or upgrade.py. A migrated copied install preserves status, configuration, cost, attempts, state, domains, plans, overlays, and history, then continues through the wheel-installed command.
- Cycle 008 is `GO_WITH_CHANGES` (2026-08-23): `tools/manifest.py` is deleted, the README's install/upgrade/run/layout passages now route through `.venv/bin/pm-flow` and `pip install --upgrade`, and a thirteenth focused group extracts the README's fenced commands, refuses retired names, and actually runs the documented `version`, `status` and `tick` through the installed wheel. Three corrections are owed: the Install block says `cd /path/to/repo` and then `./install.sh /path/to/repo`, but `install.sh` lives in the pm-flow checkout and is not in the wheel; the overlay path should be spelled `.agentic/pm_flow/<project>/roles/<role>.md` (catalog.py resolves `<project_dir>/roles/<role>.md`); and the checkout-wide `find`/`grep` for manifest tooling should prune `.venv`, `dist` and `build`, since `agent_exec.sh` activates a checkout `.venv` when one exists.
- Review-side harness gap, observed 2026-08-23 in the first Claude-backed PM review: the scoped tier's default bash allow-list (`DEFAULT_SCOPED_BASH` in `agent_exec.sh`, no `access.scoped_bash` override in config) lists only pytest spellings of a test runner, and this repository's runners are `zsh tests/pm_flow_test.sh` and `zsh tests/packaged_layout_test.sh`. Every form was denied (relative, absolute, via a subagent, via `python3 -c`), and `/tmp` reads are sandbox-blocked, so the 008 acceptance and mutation runs could not be reproduced here; the verdict rests on the harness access log proving the developer executed all four commands and both mutations, on the pasted outputs matching the test's assertion order, and on static review. Until `zsh tests/*` (and `/tmp` reads for disposable copies) are granted to `pm`, no PM review in this project can produce its own test output.
- Installation still leaves `*.pm-flow.template.md` instruction prefetch artifacts. Decide whether those are required project data before closing the section.
- `install.sh` is not shipped in the wheel and `pm-flow` has no `init` subcommand, so a user with only `pip install pm-flow` cannot create project data without a checkout. Pre-existing, outside this cycle; worth naming in the handoff.

## Current assignment

- Cycle 008 is accepted with changes. Next: apply the three README/test corrections above, then decide on the instruction-prefetch artifacts and close with the full suite.

## Dependencies

- green-suite: done; full suite completion is established.
- worktree-isolation: done; section work and accepted merge-back are isolated.
