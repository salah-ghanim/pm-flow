# real-install section PM state

## Current task

- T2 — the migrated install drives a tick and its legacy TSVs import. T1 was
  accepted in cycle 001 with one carried change (below).

## Completed tasks and evidence

- T1 (A1, migration half) — accepted cycle 001.
  - `zsh /Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/real-install/tests/real_install_test.sh`
    exits 0 with three PASS lines: the fixture has four unnamed legacy
    workspaces and a copied engine; the no-key path names every discovered
    workspace; all four workspaces survive migration, are registered, and the
    wheel-installed `pm-flow status` reads the migrated tree.
  - `zsh …/tests/packaged_layout_test.sh` exits 0 with 13 PASS, so the
    widening did not regress the single-workspace path.
  - Negative control (`sections/real-install/probe_negative.zsh`): the
    pre-change `install.sh` from `main`, run against the same fixture, prints
    `removed_copied_engine=29` and then `old: workspace project LOST`, with
    `projects.md` listing only `` `beta` ``. The four-workspace survival is
    therefore produced by the change, not by the fixture or the command line.
  - `install.sh` now shares `discover_project_workspaces` between
    `resolve_install_project_key`, `remove_copied_engine` (used only when
    neither `.project-key` nor `projects.md` names anything) and the
    `projects.md` write. `export.py` and `schemas/` were added to the
    copied-engine registries; `pyproject.toml:47-51` force-includes the whole
    of `template/.agentic/pm_flow` into the wheel as `pm_flow/engine`, so both
    are engine artifacts and leaving them behind would leave a stale copy.

## Carried defects

- `install.sh:477` — `local candidates=("${(@f)$(discover_project_workspaces
  "$flow_dir")}")` expands empty output to one empty element, so a flow
  directory that exists with no workspace resolves to an empty project key
  where the pre-change code fell through to the repo-basename default.
  Observed (`sections/real-install/probe_empty_followup.zsh`): a repository
  holding only `.agentic/pm_flow/config.json` installs with `project_key=`,
  `task_contract.md` / `project_state/` / `runs/` / `sections/` written at the
  flow root, a `.project-key` containing one newline, and the second install of
  the same repository exiting 1 with `ERROR: invalid persisted project key`.
  The same probe against `main`'s `install.sh` yields `project_key=old-empty`
  and a proper workspace directory. Assigned into T2.

## Active decisions

- The suite is a new file, `tests/real_install_test.sh`, reusing
  `tests/packaged_layout_test.sh`'s harness rather than extending it. The brief
  forbids owning that file, and it must stay at 13 PASS.
- The fixture is rooted at `agentic/`, not `.agentic/`, because scenario 2
  requires a recorded rename — so `migrate_legacy_flow_dir` (`install.sh:262`)
  is exercised on a many-workspace tree and the `git mv` path at 279 must be
  reached from a git repository with `agentic/` tracked.
- Migration of the real layout is driven with `--project-key`.
  `resolve_install_project_key` short-circuits to the requested key at
  `install.sh:428-441`, so this is the shipped operator path, not a workaround;
  the suite also pins the no-key failure message from 460-463.
- A full backup of golden-grid is taken and verified before `install.sh` runs
  there, and its location is recorded in `docs/real-install.md`. This settles
  the brief's first open question.
- Independent arithmetic for A4 is computed from the TSV bytes by a formula
  written down in `docs/real-install.md`, never by reading `cost.py`'s own
  output back. Copying the tool's figure is a stated rejection condition.

## Blockers

- None external. golden-grid is not reachable from this role's sandbox — probed
  this cycle, `ls /Users/salah/code/personal/golden-grid` refused with "Claude
  Code may only list files in the allowed working directories for this session:
  '/Users/salah/code/personal/pm-flow'". T1 and T2 are fully executable here;
  the grant (`DISPATCH_EXTRA_DIRS`, `driver.zsh:2539-2557`) or an operator run
  is needed only before T3.

## Open questions

- Which golden-grid workspace hosts the real cycle (T4). Answered by the T3
  probe output, not by guessing from here.
- Whether golden-grid's ten workspaces include a name colliding with
  `COPIED_ENGINE_DIRS` (`install.sh:74-84`). The T3 listing settles it; T1
  assumes at least one collision and proves the workspace survives regardless.

## Next eligible task

- T2 on the same suite, carrying the empty-key fix above.
