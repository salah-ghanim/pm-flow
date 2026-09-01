# real-install section PM state

## Current task

- T5 — golden-grid surveyed, backed up and migrated. T1-T4 are accepted and on
  `main` (`3ff45bd`), A1 is complete and A2's method is closed: the runbook
  provisions the venv offline and proves `status` in place, and an `all` run
  with no `--pm-flow` and no `--wheel` completes end to end. Everything this
  section can prove without the real tree is proved. No code change remains
  before T5; what is missing is access to the real tree, escalated in cycle 005.

## Completed tasks and evidence

- T4 (A2's method — the runbook now completes on a repository with no pm-flow
  venv; A1 not regressed. A2 itself still needs T5's real output) — accepted
  cycle 004.
  - `zsh /Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/real-install/tests/real_install_test.sh`
    exits 0 with 18 PASS, adding five to T3's 13: `runbook all provisions and
    uses the default target pm-flow entry point`; `runbook status reads
    beta-section in place within its store write budget`; `standalone provision
    builds and installs the checkout wheel offline`; `status rejects and names a
    mutated project-data path`; `verify names a missing pm-flow entry point
    before invocation`.
  - `zsh …/tests/packaged_layout_test.sh` exits 0 with 13 PASS; T2's
    `workspace=<key> imported=3 reimported=0 total=7.5000` block and the
    `installed tick section=beta-section` line are unchanged.
  - The operator's *entire* default path is proved, not just the suite's
    (`sections/real-install/probe_status_budget_004.zsh`): the extracted runbook
    run as `all --repo <fixture> --project-key beta` with **neither `--pm-flow`
    nor `--wheel`** exits 0, building the wheel itself. Transcript in order:
    `=== phase: survey ===` (reporting `pm_flow_version=absent`, golden-grid's
    starting condition), `backup` → `backup_verified=yes`, `provision` →
    `pm_flow_wheel=pm_flow-0.2.0-py3-none-any.whl`, `pm_flow_version=0.2.0`,
    `provision=ok`, `migrate` → `migrated=agentic -> .agentic`,
    `removed_copied_engine=30`, `verify` → `renames_recorded=144`, `verify=ok`,
    `status` → `store=.agentic/pm_flow/beta/runs/pm_flow.db`,
    `status_in_place=ok`. The 127 that cycle 004 predicted for golden-grid
    cannot now happen on this path.
  - The `status` write budget has an exit-code consequence, proved by mutation
    rather than by reading the check. Same repository, same `--out`, two runs of
    the *same* extracted script differing in one injected `touch
    "$repo/stray-write.txt"` inside the status step: the unmutated re-run exits 0
    printing only `status_wrote=.agentic/pm_flow/beta/runs/pm_flow.db`; the
    mutated one exits 1 with `status_wrote=stray-write.txt` and `ERROR: status
    wrote outside the store: stray-write.txt`. The failure isolates to the extra
    write.
  - Nothing in `provision` reaches an index. All three pip invocations in the
    extracted script carry `--no-index`: the build venv's `-r
    build-requirements.txt`, the `pip wheel --no-build-isolation --no-deps`, and
    the target venv's `--force-reinstall <wheel>`.
  - `pm_flow_version` is compared, not printed. With the *expected* value alone
    forced to `9.9.9` in a copy of the script and nothing else changed
    (`sections/real-install/probe_provision_004.zsh`), `provision` exits 1 with
    `ERROR: installed pm-flow version 0.2.0 does not match wheel version 9.9.9`.
  - `backup` excludes only `.venv`, symmetrically: after the default `all` run
    the repository has an executable `.venv/bin/pm-flow`, the backup has no
    `.venv`, and its 341-line source manifest contains zero `.venv` paths, while
    `.git` and the whole flow dir are in the copy.
  - `status` runs golden-grid's own resolution: `(cd "$repo" && "$pm_flow"
    status)` with no `PM_FLOW_REPO_ROOT`. The only occurrence of that variable in
    the document is `verify`'s snapshot step, scoped to its single command
    (`docs/real-install.md:500-501`), so it cannot leak into the status phase.

- T3 (A2's method — the transcript format and the checks A2 will be read from;
  A2 itself still needs T5's real output) — accepted cycle 003.
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
    is marked a placeholder pending T5, and the suite never names the real path.

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
    settled before T7; the runbook's survey phase (T3) counts empty response
    fields per ledger, so T5's run reports the exposure instead of T7 meeting it
    as a surprise over real money.

- Both cycle-004 defects — nothing provisioned the target venv, so an operator
  `all` on golden-grid would have died at exit 127 after the irreversible phase;
  and `verify`'s status step proved scenario 1 only against a copy under `--out`
  — are fixed and pinned in T4; evidence above. Two residuals replace them, both
  about the new `status` phase and both carried into T5.

- The `status` write budget counts `.venv` bytecode as an out-of-store write.
  `status_phase` digests the whole of `--repo` with no exclusion, and its budget
  admits only `<flow>/<selected key>/runs/pm_flow.db` and its `-wal`/`-shm`
  siblings. Observed (`sections/real-install/probe_cold_venv_004.zsh`): purging
  the 55 `__pycache__` directories from the provisioned `.venv` and re-running
  `status` unchanged makes it exit 1 with `ERROR: status wrote outside the store:
  .venv/lib/python3.14/site-packages/pm_flow/__pycache__/__init__.cpython-314.pyc`
  — three `.pyc` writes, no project data touched.
  - Not a defect against the assignment, which specified exactly this budget, and
    it fails closed rather than open. But the message reads as a data-integrity
    alarm when the cause is harmless interpreter bytecode.
  - Why the documented path is safe: `pip install` byte-compiles, and `all` runs
    `verify`'s status step before `status`, so the venv is always warm by then.
    The default `all` run above passed with exactly one changed path. The
    exposure is a golden-grid `.venv` that pre-dates the run, a Python upgrade
    between provision and status, or a phase run standalone against a cold venv.
  - For T5: if the real transcript reports `status_wrote=.venv/…`, that is this,
    not data loss — re-run `status` and it passes. If it recurs, exclude `.venv`
    from the status manifest the way `backup` already excludes it.

- The budget admits only the *selected* workspace's store, not every workspace's
  `runs/`. Harmless on the fixture, where `pm-flow status` touched only
  `beta/runs/pm_flow.db` out of four workspaces. On golden-grid's ten workspaces
  any store write outside the selected key would fail the phase by name, which
  T5's transcript will show rather than hide.

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

- **External, as of cycle 005: the operator run.** A2, A3, A4 and A5 are settled
  only by a run against `/Users/salah/code/personal/golden-grid`, and no session
  in this loop can reach it. Probed again in cycle 005 from the PM's own
  session: `ls /Users/salah/code/personal/golden-grid` → "Claude Code may only
  list files in the allowed working directories for this session:
  '/Users/salah/code/personal/pm-flow'". The limit is the session grant, not the
  dispatch mechanism.
- The driver's extra-dir route — the brief's first option — is closed and not
  configurable: `dispatch_role` passes `--work-root` and each
  `DISPATCH_EXTRA_DIRS` entry (`driver.zsh:1084-1086`), `DISPATCH_EXTRA_DIRS` is
  set only by `begin_worktree_dispatch` (2574-2589), and both callers
  (`driver.zsh:1483` and the rescue path at 1971) pass the section directory and
  nothing else. Granting golden-grid would mean editing `driver.zsh`, which this
  section does not own and will not touch.
- So the brief's second route is the route, and as of this cycle the request is
  live rather than premature: cycle 004 held it back because the command would
  have died at exit 127 partway through, and T4 removed that. The runbook now
  completes end to end from a clean checkout with no overrides. What unblocks
  T5-T7 is either a session whose allowed working directories include
  `/Users/salah/code/personal/golden-grid`, or the operator running the command
  block at `docs/real-install.md:11-20` and pasting the transcript into the
  `Golden-grid evidence` section over `transcript=PLACEHOLDER` (line 709).

## Open questions

- Which golden-grid workspace hosts the real cycle (T6). Answered by T5's survey
  output, not by guessing from here.
- Whether golden-grid's ten workspaces include a name colliding with
  `COPIED_ENGINE_DIRS` (`install.sh:75-86`). T5's survey settles it; T1 assumes
  at least one collision and proves the workspace survives regardless.
- Whether golden-grid is a git work tree with `agentic/` tracked. If it is not,
  `migrate_legacy_flow_dir` falls to plain `mv` (`install.sh:279-284`) and
  scenario 2's "recorded rename" cannot be produced; the survey must report this
  before `migrate` runs, not after.
- Whether golden-grid has a `.venv` at all, and what it holds. `provision` must
  work either way — create it when absent, install the current wheel over
  whatever is there when present — so this does not gate T4; it only decides how
  much T5's transcript has to explain.

## Next eligible task

- T5 — golden-grid surveyed, backed up and migrated. It is one operator command,
  published verbatim at `docs/real-install.md:11-20`, and cycle 004 ran that
  exact shape against the fixture with no overrides. From a pm-flow checkout,
  extract the script between the `runbook:begin` / `runbook:end` markers and run
  `<script> all --repo /Users/salah/code/personal/golden-grid --project-key
  <key> --name "Golden Grid"`, then commit the transcript into that document's
  `Golden-grid evidence` section over the placeholder at line 709. No
  `--pm-flow` and no `--wheel`: `provision` builds the wheel from the checkout's
  wheelhouse offline and installs it into golden-grid's `.venv`. `migrate`
  refuses without a verified backup, so a single `all` run cannot skip the
  rollback copy, and `survey` answers the open questions above before
  `install.sh` touches anything.
- No role in this loop can run it — see Blockers. The section is stopped on that
  access, not on a code change.
