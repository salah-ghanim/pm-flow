# real-install section PM state

## Current task

- T3 — golden-grid migrated, with the run recorded. T1 and T2 are accepted; A1
  is complete. T3 cannot start until golden-grid is reachable (see Blockers).

## Completed tasks and evidence

- T2 (A1, installed-tick half — A1 complete; fixes the arithmetic method A4
  later applies to golden-grid) — accepted cycle 002.
  - `zsh /Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/real-install/tests/real_install_test.sh`
    exits 0 with nine PASS lines, adding to T1's three: the workspace-less flow
    defaults to its repository basename and reinstalls; `workspace=<key>
    imported=3 reimported=0 total=7.5000` for each of alpha, beta, gamma,
    project; and `installed tick section=beta-section action=scope -> ASSIGN;
    TSVs unchanged; completed pm attempt stored`.
  - `zsh …/tests/packaged_layout_test.sh` exits 0 with 13 PASS.
  - The carried empty-key defect is fixed by one line, `install.sh:478`
    (`candidates=("${(@)candidates:#}")`). Mutation check
    (`sections/real-install/probe_mutate_002.zsh`, mutation A): with that single
    line deleted from a throwaway copy of the tree, the suite fails at
    `a workspace-less flow uses the repository basename as its key: expected
    'empty-workspace', got ''`. The assertion is load-bearing, and the fix is a
    filter rather than a revert of what T1 widened — all four fixture
    workspaces still survive and `packaged_layout_test.sh` is still 13 PASS.
  - The cost total is computed from the TSV bytes, not copied from `cost.py`.
    Mutation B: changing the fixture's first ledger amount from `1.250000` to
    `9.000000` in the copy makes every workspace print `total=15.2500` and the
    suite still exits 0 — expected and actual moved together.
  - The tick reaches the migrated data through the installed engine. Mutation C:
    renaming the fixture's workspace overlay marker makes the suite fail at
    `the installed engine reads the migrated workspace's pm overlay: expected to
    find 'Beta workspace role marker'`, so the marker really arrives from
    `beta/roles/pm.md` and not from a packaged default.
  - The copied-engine expectation is read out of `install.sh` by
    `install_array_names`, which parses the `COPIED_ENGINE_FILES` /
    `COPIED_ENGINE_DIRS` array bodies. Verified independently: it yields all 22
    file names and all 10 dir names, `roles domains tasks topologies project
    tests __pycache__ .pm-flow cards schemas` — three more dirs than the list it
    replaced. Workspace keys are skipped in the dirs loop, which is what lets
    the fixture's real `project` workspace collide with the scaffold name.

- T1 (A1, migration half) — accepted cycle 001, now merged to `main`:
  `tests/real_install_test.sh` and `tests/fixtures/real_install/build_fixture.sh`
  exist in the checkout and `install.sh:335` defines `discover_project_workspaces`
  with callers at 374, 477 and 833.
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

Both defects carried out of T1 — the empty project key at `install.sh:477` and
the suite's restated `COPIED_ENGINE_FILES` list — were fixed and pinned in
cycle 002; evidence above. One new defect, in an unowned file, replaces them.

- `cost.py` drops legacy ledger rows whose response field is empty, and this is
  now confirmed, not suspected. `import_legacy` dedupes on `response_path`
  against a set seeded from the store (`cost.py:176-193`), and an empty field is
  a key like any other, so the first empty-response row is inserted and every
  later one is skipped. Observed
  (`sections/real-install/probe_empty_response_002.zsh`, read-only, against a
  throwaway workspace): a two-row TSV with empty response fields costing
  1.000000 and 2.000000 prints `imported=1`, and `cost.py total` prints
  `1.0000` where the TSV sums to 3.0000. Money silently disappears; nothing
  reports a discrepancy.
  - Not fixed here: `template/.agentic/pm_flow/cost.py` is not an owned path,
    and the fixture's TSVs carry distinct response paths, so the suite is
    honest and green either way.
  - Consequence for this section: A4's independent arithmetic will disagree with
    `cost.py total` on any golden-grid workspace whose legacy TSV has more than
    one empty-response row. This must be escalated through `handoff.md` and
    settled before T5, and golden-grid's real TSVs should be scanned for empty
    response fields as part of T3's survey rather than discovered at T5.

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
- The cost-parity block runs before the tick, not after. `cost.py total` calls
  `import_legacy` itself (`cost.py:275`) and that function ingests response
  envelopes alongside TSV rows (`cost.py:195-203`), so a tick's envelope would
  make the `imported=0` re-run false for a reason unrelated to the TSVs.
- No engine path writes `cost_ledger.tsv` any more — grepped `driver.zsh`,
  `pm_flow.sh` and `agent_exec.sh` this cycle, no hit. The brief's "the host
  repository absorbs no per-dispatch writes" is therefore a live assertion the
  fixture tick can make, by digesting the TSVs across it.

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

- T3 — golden-grid migrated, with the run recorded. Not dispatchable from this
  role's sandbox until the driver grants `/Users/salah/code/personal/golden-grid`
  via `DISPATCH_EXTRA_DIRS` (`driver.zsh:2539-2557`) or the operator runs the T3
  runbook and its output is committed. T3's survey must also record which
  golden-grid ledgers carry empty response fields (see Carried defects).
