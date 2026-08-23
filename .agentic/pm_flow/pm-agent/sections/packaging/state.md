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

- Cycle 004 is `GO`: installed-artifact dispatch and repository-local persona
  overlay provenance were proven from the wheel, which is what cycle 005 was
  waiting on before installer, migration and copy-lifecycle removal could start.

## Cycle 005: the work exists on this branch, unreviewed

**Read this before scoping or implementing anything.** Cycle 005's developer
completed its assignment and changed the worktree, then the dispatch ended
before writing `result.md`. The driver therefore never saw the work and recorded
only `orphaned_worktree.txt`. A later re-dispatch hit a 429 session limit and did
nothing at all, which is the empty result the cycle record shows. The
implementation was never lost - it was sitting uncommitted in the worktree.

It is now committed on this section's branch as `d415128`, and the branch was
brought up to `main` in `c10f76e`. Neither commit is an acceptance: the section
still owes a result, a review and a merge-back, and nothing here has been
through a section review.

The changed files are exactly cycle 005's allowlist and nothing else:
`pyproject.toml`, `src/pm_flow/paths.py`, `install.sh`, `MANIFEST` (deleted),
`template/.agentic/pm_flow/pm_flow.sh`, `template/.agentic/pm_flow/upgrade.py`
(deleted), `tests/pm_flow_test.sh`, `tests/packaged_layout_test.sh`,
`.gitignore`.

Verified against the merged branch, not against the state it was written in:

- `zsh tests/packaged_layout_test.sh` exits 0 with 10 PASS groups, including the
  three the assignment added - a fresh repository holding project data only, a
  copied-engine repository migrating losslessly and continuing to run, and
  initialisation and migration leaving the installed package untouched.
- `zsh tests/pm_flow_test.sh` exits 0 with 10 PASS groups.
- A fresh install is genuinely data-only: `config.json`, the project workspace,
  `task_contract.md`, `.project-key`, `projects.md`, `.gitignore` and
  `local_env.sh.example`. No engine script, no `MANIFEST`, no `upgrade.py`.

So the assignment does not need reimplementing. What it needs is a result that
reports what is there, and a review that judges it - including the mutations the
assignment names, which have not been run by anyone.

### What the sync merge settled, and what it left

The branch predated `agents-md`, so `c10f76e` merged `main` in. There was exactly
one conflict: `main` modified `MANIFEST`, this branch deletes it. It was resolved
as deleted because cycle 005's assignment asks for that deletion by name.
`install.sh` auto-merged.

`agents-md` closed while this branch was behind, and its handoff asks for its
contract to be re-checked after this merge. That check was run and passes: fresh
and pre-existing-`CLAUDE.md` installs from this branch both write the 58-line
`AGENTS.md` carrying the router and invariants, leave a `CLAUDE.md` that imports
it with `@AGENTS.md`, and preserve pre-existing content. Keep it that way - the
AGENTS-before-CLAUDE ordering, the managed markers and the one-time backups are
a contract another section closed on.

Left open, deliberately, because both paths are outside this section's allowlist:
`tools/manifest.py` and two `README.md` lines still expect a root `MANIFEST` that
no longer exists. Nothing in the suite or the installer calls the tool, so this
is an inconsistent checkout rather than a broken build, but the tool and the file
cannot both be right. Decide which goes and hand the change to whoever owns the
path rather than editing it from here.

Also inherited from `agents-md`: an install leaves `*.pm-flow.template.md`
prefetch artifacts in the target repository. That section asked this one to
decide whether release cleanup is required.

## Current assignment

- Cycle 005 is open with its implementation already on the branch. Do not
  reimplement it. Report what is on the branch, run the four exact acceptance
  commands and the mutations the assignment names, and review the result.

## Dependencies

- green-suite: done; full suite completion is established.
- worktree-isolation: done; section work and accepted merge-back are isolated.
