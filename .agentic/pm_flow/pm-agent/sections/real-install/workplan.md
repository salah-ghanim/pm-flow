# real-install workplan

## Design summary

Two halves, in order: a real-layout regression suite built here, then the
golden-grid migration evidenced against it.

The suite is a sibling of `tests/packaged_layout_test.sh`, not an extension of
it. It reuses that file's harness wholesale — the `mktemp` guard and cleanup
trap (lines 14-32), `fail`/`assert_contains`/`assert_equals`/`expect_failure`
(29-75), the `PM_FLOW_*` unset sweep (82-86), the offline two-venv wheel build
against `tests/packaging-build-wheelhouse` (104-200), the `ZDOTDIR` isolation
(160-161), `tests/fixtures/stub_success.zsh` as the deterministic child, and
the legacy-fixture construction pattern at 888-1010 (copy `template/.agentic/
pm_flow/.` into the flow dir, `chmod +x` the shebang files, plant `.pm-flow/
MANIFEST` and `upgrade.py`, take `digest_tree.py` preservation digests before
migrating). What it adds is the *shape* the existing legacy fixture does not
have and golden-grid does: the flow dir rooted at `agentic/` rather than
`.agentic/`, several project workspaces instead of one, no `.project-key`, no
`projects.md`, pre-sections `start.md`/`resume.md`, and a legacy
`runs/cost_ledger.tsv` per workspace.

That shape is chosen because it is where the shipped migration is provably
thin, not to be exotic:

- `remove_copied_engine` (`install.sh:334`) protects a workspace only when the
  repository *named* it — `selected_key`, `.project-key`, or `projects.md`
  (339-349). It runs at `install.sh:675`, before `projects.md` is written at
  697. A legacy install has none of the three, so on a many-workspace tree the
  only protected key is the one passed on the command line, and any workspace
  whose directory name collides with `COPIED_ENGINE_DIRS` (`install.sh:74-84`:
  `roles`, `domains`, `tasks`, `topologies`, `project`, `tests`, `cards`) is
  deleted outright by `rm -rf` at 367. `install.sh:329-333` states the
  recognition rule as a deliberate decision; it just has no input on this
  layout. The structural scan already in `resolve_install_project_key`
  (448-455 — a directory with `task_contract.md` and `project_state/`) is the
  fix's raw material.
- `projects.md` is rendered fresh when absent (697-706) and then appended to
  for the selected key only (810-811), so migrating a ten-workspace install
  produces a registry naming one of ten.
- `resolve_install_project_key` hard-fails on several workspaces with no
  persisted key (460-463). Passing `--project-key` short-circuits that at
  428-441, so the operator path exists; the suite pins it and the failure
  message both.

The second half never substitutes the fixture for golden-grid. `docs/
real-install.md` carries the exact command block the operator runs there and
the captured output of each run, committed in this repository. Independent
arithmetic for A4 is computed from the TSV bytes by a formula written in the
doc, never by reading `cost.py`'s own answer back.

Cycle 003 settles *how* that operator run happens, because the sandbox question
is now answered in code rather than by probe. A dispatched role is granted
`--work-root` plus `DISPATCH_EXTRA_DIRS`, and the only caller,
`driver.zsh:1476`, passes exactly one extra directory — the section directory
(`begin_worktree_dispatch "$(basename "$section_dir")" "$section_dir"`). There
is no configuration that adds another path, so no dispatched developer will ever
reach `/Users/salah/code/personal/golden-grid` without a change to `driver.zsh`,
which this section does not own. The brief's second route is therefore the route:
an operator-run probe whose output is committed. What makes that honest evidence
rather than prose is that the operator runs a *script this repository ships and
tests* — the runbook in `docs/real-install.md`, extracted and executed by the
suite against the fixture, so the doc cannot drift from what actually runs. The
fixture proves the runbook executes; only the operator's captured golden-grid
transcript settles A2.

## Interfaces and data changes

- New: `tests/real_install_test.sh`, `tests/fixtures/real_install/**`,
  `docs/real-install.md`. No change to any existing test's contract.
- `docs/real-install.md` is two things at once from T3 on: the evidence record,
  and the executable runbook the suite extracts and runs. Its extraction markers
  are therefore load-bearing text, not formatting.
- `install.sh` behaviour change expected under T1: which workspaces migration
  treats as named, and what `projects.md` lists afterwards. Both are additive
  — a single-workspace install with a `.project-key` must behave exactly as it
  does today, which is what keeping `tests/packaged_layout_test.sh` at 13 PASS
  checks.
- No change to `template/.agentic/pm_flow/**` (not owned here; see Risks).

## Task T1 — a many-workspace legacy install migrates without losing a workspace

- Status: done (cycle 001, accepted with a required follow-up carried into T2:
  `resolve_install_project_key` must stop returning an empty key when the flow
  directory exists with no workspace — see Risks and `state.md`)
- Outcome: `tests/real_install_test.sh` builds a golden-grid-shaped legacy
  install and migrates it with `install.sh --project-key`, and every workspace
  survives with its data byte-identical and listed in `projects.md`.
- Paths: `tests/real_install_test.sh`, `tests/fixtures/real_install/**`,
  `install.sh`.
- Reuse: `tests/packaged_layout_test.sh` harness and legacy-fixture pattern as
  named in the design summary; `resolve_install_project_key`'s candidate scan
  (`install.sh:448-455`); `COPIED_ENGINE_FILES`/`COPIED_ENGINE_DIRS`
  (`install.sh:47-84`); `tests/fixtures/stub_success.zsh`.
- Acceptance IDs: A1 (fixture shape and migration half).
- Validation: `zsh tests/real_install_test.sh` exits 0, and
  `zsh tests/packaged_layout_test.sh` still prints 13 PASS lines and exits 0.
- Depends on: None.

## Task T2 — the migrated install drives a tick and its legacy TSVs import

- Status: done (cycle 002; the carried empty-key fix landed, cost parity and the
  installed tick are asserted, and the copied-engine expectation is now read out
  of `install.sh`. The `cost.py` empty-`response_path` drop was probed read-only
  and confirmed — escalated, not fixed here; see `state.md`.)
- Outcome: the same suite continues past migration: for each fixture workspace
  `cost.py import` then `cost.py total` matches arithmetic computed from the
  TSV bytes with a re-run printing `imported=0`, and afterwards the venv's
  `pm-flow` drives one tick in the migrated fixture that leaves every
  `cost_ledger.tsv` byte-identical.
- Paths: `tests/real_install_test.sh`, `tests/fixtures/real_install/**`,
  `install.sh` (only if the tick forces it, plus the T1 follow-up below).
- Carried from T1 (must land in this cycle): `resolve_install_project_key`'s
  candidate array is now built with `("${(@f)$(discover_project_workspaces …)}")`
  (`install.sh:477`), and zsh expands empty command output to one empty element.
  A flow directory that exists with no workspace therefore resolves to an empty
  key instead of the repo-basename default: project files land at the flow root
  and `.project-key` is written blank, after which the next install fails with
  `invalid persisted project key`. Filter the empty element and pin the case
  with an assertion in the suite.
- Order is forced, not stylistic: `cost.py total` calls `import_legacy` itself
  (`cost.py:275`) and `import_legacy` ingests response envelopes as well as TSV
  rows (`cost.py:195-203`). A tick writes envelopes, so the parity block must
  run *before* the tick or the `imported=0` re-run claim is false for reasons
  that have nothing to do with the TSVs.
- The tick doubles as the completion-criterion probe: no engine path writes
  `cost_ledger.tsv` any more (grepped `driver.zsh`, `pm_flow.sh`,
  `agent_exec.sh` — no hit), so "the host repository absorbs no per-dispatch
  writes" is checkable here by digesting the TSVs across the tick.
- Reuse: the packaged suite's installed-tick block
  (`tests/packaged_layout_test.sh:483-534`) for the deterministic stubbed child
  and the `PATH`-injected `claude`; its minimal dispatchable section shape
  (296-325), which the fixture workspaces already match;
  `pm_flow/engine/cost.py` in the installed package, located as
  `trace_commands_test.sh:709-716` locates `trace_export.py`.
- Acceptance IDs: A1 (installed-tick half; completes A1), plus the fixture half
  of the arithmetic method A4 later applies to golden-grid.
- Validation: `zsh tests/real_install_test.sh` exits 0 and its output names the
  ticked section and one `imported=` line per fixture workspace;
  `zsh tests/packaged_layout_test.sh` still 13 PASS.
- Depends on: T1.

## Task T3 — the golden-grid runbook, executable by the operator and tested here

- Status: done (cycle 003; the runbook is published in `docs/real-install.md`
  between the extraction markers and executed from there by the suite, which is
  now at 13 PASS. One carried requirement into T4: `verify` runs `pm-flow
  status` against a snapshot copy under `--out`, so scenario 1 still needs a
  direct `.venv/bin/pm-flow status` in golden-grid — see `state.md`.)
- Outcome: `docs/real-install.md` exists and carries, between extraction
  markers, one runnable zsh script with four phases — `survey` (read-only),
  `backup` (copy and verify), `migrate` (`install.sh` only), `verify` —
  that an operator runs against `/Users/salah/code/personal/golden-grid` in one
  command and that prints a transcript fit to be pasted back into the same
  document as A2's evidence. `tests/real_install_test.sh` extracts that same
  script out of the document and runs it against a copy of the legacy fixture,
  so the published commands are the executed commands, plus a negative control
  showing `verify` fails on an unmigrated tree.
- Paths: `docs/real-install.md`, `tests/real_install_test.sh`,
  `tests/fixtures/real_install/**`, `README.md`.
- Reuse: the suite's `install_array_names` sed parse of `COPIED_ENGINE_FILES` /
  `COPIED_ENGINE_DIRS` (`tests/real_install_test.sh:284-301`) — the runbook
  reads the same arrays out of `install.sh` and never restates them; the
  `digest_tree.py` manifest and `assert_digest_lines_present` pattern (149-162,
  42-49) for the survive-the-migration comparison; the independent ledger
  arithmetic `awk -F '\t' 'NF >= 5 { count += 1; total += $5 }'` (308-310);
  the rename check against `git diff --cached -M --name-status` (245-249);
  `tests/fixtures/real_install/build_fixture.sh` for the tree to self-test on.
- Acceptance IDs: A2's method (the transcript format and the checks A2 will be
  read from). A2 itself is settled only by T4's real output.
- Validation: `zsh tests/real_install_test.sh` exits 0, with new PASS lines for
  the runbook survey, the full runbook run over the fixture, and the negative
  control; `zsh tests/packaged_layout_test.sh` still 13 PASS.
- Depends on: T2.

## Task T4 — golden-grid surveyed, backed up and migrated

- Status: pending (needs the operator to run T3's runbook; not dispatchable in
  the role sandbox — see Risks)
- Outcome: the runbook has run against `/Users/salah/code/personal/
  golden-grid`; a verified backup exists, `install.sh` has run, the flow dir
  holds no copied-engine name, its venv's `pm-flow` reports status, its ten
  workspaces and run history survive, and `docs/real-install.md` carries the
  verbatim transcript of all four phases.
- Paths: `docs/real-install.md`, `install.sh` (only if the real tree forces a
  fix the fixture did not), `tests/real_install_test.sh` and
  `tests/fixtures/real_install/**` (extend the fixture with any shape
  golden-grid turns out to have that T1-T3 did not reproduce, and re-run the
  suite over it).
- Reuse: T3's runbook verbatim; the `COPIED_ENGINE_*` arrays as the checklist.
- Acceptance IDs: A2.
- Validation: the committed transcript shows `removed_copied_engine=N`,
  `migrated=agentic -> .agentic` with the `R` rename lines from
  `git diff --cached -M --name-status`, `git -C golden-grid status --short`
  naming only migration paths, the before/after workspace manifests agreeing,
  and `.venv/bin/pm-flow status` naming the project.
- Depends on: T3.

## Task T5 — one real cycle in golden-grid

- Status: pending
- Outcome: a section cycle ran there through the installed command, and
  `docs/real-install.md` records the dispatch, the verdict, the driver's commit
  SHA in golden-grid's history, and the `pm-flow status` line showing the
  advanced cycle.
- Paths: `docs/real-install.md`.
- Reuse: `pm-flow run` / `run-detach` as shipped; `docs/run-detach.md` for the
  detached-run conventions.
- Acceptance IDs: A3.
- Validation: committed `git -C golden-grid log --oneline -n 3` showing the
  driver commit, and the `pm-flow status` output for the same section before
  and after.
- Depends on: T4.

## Integration and end-to-end validation

## Task T6 — parity and traces from the real install, scenarios 1-6 in one pass

- Status: pending
- Outcome: `docs/real-install.md` is complete evidence: per-workspace
  `cost.py import` / `total` figures against independently computed TSV
  arithmetic, a re-run showing `imported=0`, `pm-flow trace status` and a
  successful `trace export` containing golden-grid spans, and a final recorded
  pass of scenarios 1-6 in order. `README.md` points at the document.
- Paths: `docs/real-install.md`, `README.md`.
- Reuse: the arithmetic formula fixed in T2 and re-published in T3's runbook
  survey; the survey's per-workspace empty-response row count, which says in
  advance where `cost.py`'s drop will make the two figures disagree;
  `pm-flow trace status|export` as proved by
  `tests/trace_commands_test.sh:825-860`.
- Acceptance IDs: A4, A5 (and the recorded re-pass of A1-A3).
- Validation: the committed block shows, per workspace, the TSV-derived total
  and the `cost.py total` figure agreeing; the export command exiting 0 with
  golden-grid span names in its output; `zsh tests/real_install_test.sh`
  exiting 0 on `main`.
- Depends on: T5.

## Risks and rollback

- golden-grid is unreachable from the dispatch sandbox, and this is now
  structural rather than incidental. `dispatch_role` grants `--work-root` plus
  `DISPATCH_EXTRA_DIRS` (`driver.zsh:1076-1082`); the only caller that sets
  those, `driver.zsh:1476`, passes the section directory and nothing else, and
  no configuration widens it. Re-probed this cycle for the record:
  `ls /Users/salah/code/personal/golden-grid` is refused with "Claude Code may
  only list files in the allowed working directories for this session:
  '/Users/salah/code/personal/pm-flow'". So T4-T6 are operator-run by
  construction, and T3 exists to make that run one tested command instead of a
  pasted sequence. Substituting the fixture for the real install remains a
  rejection condition, not a fallback.
- Data loss during T4 is the one irreversible risk. Rollback: a full copy of
  golden-grid taken and verified *before* `install.sh` runs — the runbook's
  `backup` phase, which `migrate` refuses to run without — with the copy's
  location and manifest recorded in `docs/real-install.md` (settles the brief's
  first open question: yes, always).
- A runbook that is published but never executed is the failure mode of every
  runbook. Guard: the suite extracts the script from `docs/real-install.md`
  itself and runs it, so an edit to the document that breaks the script breaks
  the build, and a `verify` phase that would pass on anything is caught by the
  negative control against an unmigrated tree.
- `cost.py`'s dedupe keys on `response_path` (`cost.py:176-203`), so several
  ledger rows with an empty response field collapse to the single key `""` and
  all but the first are dropped — a plausible shape in a legacy TSV, and it
  would make A4's independent arithmetic disagree. `template/.agentic/pm_flow/
  cost.py` is not an owned path: T2 probes it read-only against a throwaway
  workspace and records the figures; if the drop is real it is escalated
  through `handoff.md` and the fixture keeps distinct response paths, so the
  suite still exits 0 and the hazard is known before T5 meets real TSVs.
- The suite hardcodes its own `COPIED_ENGINE_FILES` list
  (`tests/real_install_test.sh:260-265`). It matches `install.sh` today, but the
  next engine file added to `template/` would be missed by both lists at once
  and silently left behind by every migration. T2 derives the expectation from
  `install.sh`'s own arrays instead of restating them.
- An `install.sh` fix that widens what counts as a named workspace could stop
  removing a genuine copied `roles/`. Guard: T1 asserts both directions on the
  same fixture — the workspace survives, the flow-level packaged copy goes.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1 | T1, T2 | `zsh tests/real_install_test.sh` exits 0 over a fixture with `agentic/`-rooted pre-sections `pm_flow.sh`, ≥3 workspaces, no `.project-key`, legacy TSVs; an installed tick after migration |
| A2 | T3 (method), T4 (evidence) | T3: the runbook in `docs/real-install.md` runs end to end over the fixture from the suite, and its `verify` phase fails on an unmigrated tree. T4: the operator's committed golden-grid transcript — `removed_copied_engine=N`, the recorded rename, no copied-engine name left, `pm-flow status` from golden-grid's venv, workspaces and history intact |
| A3 | T5 | Committed driver commit SHA in golden-grid's `git log` and the advanced-cycle `pm-flow status` |
| A4 | T6 | Per-workspace `imported=N`, `imported=0` on re-run, `cost.py total` equal to arithmetic computed from the TSV independently, with T3's survey having named the workspaces where empty response fields make disagreement expected |
| A5 | T6 | `pm-flow trace status` listing spans and a `trace export` exiting 0 with golden-grid spans in its output |
