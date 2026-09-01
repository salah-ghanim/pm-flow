# real-install section PM state

## Current task

- T4 — golden-grid surveyed, backed up and migrated. T1-T3 are accepted; A1 is
  complete and A2's method is fixed and executable. T4 is not dispatchable in the
  role sandbox by construction (see Blockers); it needs the operator to run the
  published runbook and paste the transcript back into `docs/real-install.md`.

## Completed tasks and evidence

- T3 (A2's method — the transcript format and the checks A2 will be read from;
  A2 itself still needs T4's real output) — accepted cycle 003.
  - `zsh /Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/real-install/tests/real_install_test.sh`
    exits 0 with 13 PASS, adding four to T2's nine: `runbook survey reports the
    legacy layout and independent ledger arithmetic`; `extracted runbook backs
    up, migrates, and verifies the fixture end to end`; `runbook survey counts
    empty legacy response fields without importing them`; `runbook negative
    controls reject unmigrated verification and unbacked migration`.
  - `zsh …/tests/packaged_layout_test.sh` exits 0 with 13 PASS.
  - The published text is the executed text, proved by mutation rather than by
    reading the extraction line (`sections/real-install/probe_doc_coupling_003.zsh`):
    one string changed inside the fence of a *copy* of `docs/real-install.md`
    (`print 'verify=ok'` → `print 'verify=PROBE_MUTATION'`) drops the suite from
    13 PASS to 10 and exits 1 with `FAIL: the runbook completes all migration
    verification: expected to find 'verify=ok'`. Drift between the published and
    the executed commands now breaks the build.
  - `verify` has teeth, proved by three mutations against throwaway fixtures
    (`sections/real-install/probe_runbook_003.zsh`):
    - Data loss: rewriting `alpha/project_state/plan.md` between `backup` and
      `migrate` makes `verify` exit 1 with `ERROR: surveyed project data was lost
      or rewritten: alpha/project_state/plan.md`.
    - Surviving engine: replanting `pm_flow.sh` in the *migrated* flow dir makes
      `verify` print `copied_engine_remaining=pm_flow.sh` and exit 1 with
      `copied engine survives migration`. The suite's own negative control covers
      the unmigrated tree.
    - `migrate` with a fresh `--out` exits 1 with `ERROR: missing verified backup
      manifest`.
  - `survey` is read-only under `--repo`, measured rather than asserted: a
    sha256 manifest of every file in the fixture repository, taken by the probe
    before and after the survey phase, compares equal. `verify` proves the same
    property about itself in-band, digesting `--repo` at its start and end and
    failing on any difference.
  - The survey reads the copied-engine names out of `install.sh` and restates
    none: `copied_engine_present=` printed all 22 files and 10 dirs including
    `export.py` and `schemas`, with `collision=project` naming the workspace key
    that shadows a `COPIED_ENGINE_DIRS` entry. `git_worktree=true` comes from the
    printed `rev-parse` value, not its exit status.
  - The fixture's shared ledgers are untouched — T2's `rows=3 total=7.5000`
    parity block still passes, and the two empty-response rows are appended to a
    throwaway clone inside the suite, which reports
    `workspace=alpha ledger=present rows=5 total=10.5000 empty_response_rows=2`.
  - `docs/real-install.md` states no golden-grid figure as observed; every value
    is marked a placeholder pending T4, and the suite never names the real path.

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
    one empty-response row. This is escalated through `handoff.md` and must be
    settled before T6; the runbook's survey phase (T3) counts empty response
    fields per ledger, so T4's run reports the exposure instead of T6 meeting it
    as a surprise over real money.

- Carried into T4 from cycle 003, not a defect in the runbook but a limit of it:
  `verify`'s status step does not exercise golden-grid's own path resolution.
  `pm-flow status` imports legacy costs and writes the store at
  `runs/pm_flow.db` (`src/pm_flow/paths.py:46,161`), which is under `--repo`, so
  a phase that must leave `--repo` byte-identical cannot run it there. The
  runbook resolves this honestly and says so in a comment: cwd is `$repo`, but
  `PM_FLOW_REPO_ROOT` (`src/pm_flow/paths.py:82`) points at an exact copy of the
  migrated flow dir under `--out`. That proves the venv's binary reads the
  migrated data; it does not prove scenario 1 in place. T4 must therefore record
  a separate, direct `.venv/bin/pm-flow status` run in golden-grid *after*
  `verify` returns `verify=ok` — a legitimate write under the brief's
  golden-grid constraint — or A2 is settled only for a copy.

- Two smaller hazards to watch when the runbook first meets real data, neither
  worth a change against the fixture:
  - `empty_response_rows` counts every ledger line with `NF < 6`, so a genuine
    blank line inside a legacy TSV inflates the count by one. It cannot deflate
    it, so it stays a safe over-report of the `cost.py` exposure.
  - `verify` exempts the refreshed `task_contract.md`, `start.md` and
    `resume.md` only when `--project-key` is passed. Run standalone without it,
    `verify` would report the selected workspace's own refreshed files as lost.
    The documented path (`all` with `--project-key`) is unaffected.

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
  the brief's first open question. The runbook enforces it: `migrate` refuses to
  run unless a verified backup manifest exists.
- The operator's commands live in `docs/real-install.md` as one extractable
  script, and `tests/real_install_test.sh` extracts and runs *that text* against
  the fixture. A runbook nobody executes rots; this way an edit that breaks it
  breaks the suite. Running it over the fixture proves the script works and
  proves nothing about golden-grid — A2 stays settled by the committed real
  transcript alone.
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

- None external, and the reachability question is now closed rather than open.
  The driver's extra-dir grant is not configurable: `dispatch_role` passes
  `--work-root` and each `DISPATCH_EXTRA_DIRS` entry (`driver.zsh:1076-1082`),
  and the only caller that populates them, `driver.zsh:1476`, passes the section
  directory and nothing else. No dispatched developer can be granted
  `/Users/salah/code/personal/golden-grid` without editing `driver.zsh`, which
  this section does not own and will not touch. Re-probed for the record this
  cycle: `ls /Users/salah/code/personal/golden-grid` refused with "Claude Code
  may only list files in the allowed working directories for this session:
  '/Users/salah/code/personal/pm-flow'".
- Consequence, and the reason for the re-cut: A2, A3, A4 and A5 are settled by
  an operator run, which is the brief's own second route ("an operator-run probe
  whose output is committed"). T3 is fully executable in the sandbox and makes
  that run one tested command; T4-T6 then need the operator, not a code change.
  This is escalated through `handoff.md` as a request for an operator run, not
  as an external blocker.

## Open questions

- Which golden-grid workspace hosts the real cycle (T5). Answered by T4's survey
  output, not by guessing from here.
- Whether golden-grid's ten workspaces include a name colliding with
  `COPIED_ENGINE_DIRS` (`install.sh:75-86`). T4's survey settles it; T1 assumes
  at least one collision and proves the workspace survives regardless.
- Whether golden-grid is a git work tree with `agentic/` tracked. If it is not,
  `migrate_legacy_flow_dir` falls to plain `mv` (`install.sh:279-284`) and
  scenario 2's "recorded rename" cannot be produced; the survey must report this
  before `migrate` runs, not after.

## Next eligible task

- T4 — golden-grid surveyed, backed up and migrated. Nothing in this sandbox
  advances it: the work is one operator command, already published and tested.
  From a pm-flow checkout, extract the script between the `runbook:begin` /
  `runbook:end` markers of `docs/real-install.md` and run it as
  `<script> all --repo /Users/salah/code/personal/golden-grid --project-key
  <key> --name "Golden Grid"`, then commit the transcript into that document's
  `Golden-grid evidence` section, replacing the placeholders. `migrate` refuses
  without a verified backup, so a single `all` run cannot skip the rollback copy.
  The survey answers all three open questions below before `install.sh` touches
  anything, and T4 must add the direct in-place `pm-flow status` run named under
  Carried defects.
