# topology-compare section PM state

## Current task

- None. T5 was accepted at cycle 006 and it was the last task in the workplan.
  Every brief acceptance ID (A1-A6) now has current evidence through the
  installed entry point. What remains is the handoff, and in it two disclosures:
  the `fail`-path open run below, and the brief's owned-paths correction
  (engine Python lives under `template/.agentic/pm_flow/`, not `src/pm_flow/`).

- Post-merge verification, cycle 007 scoping, 2026-08-24. Every figure above was
  taken in the section worktree; the accepted work is now on `main` (`a81a9a0`,
  `b5e667a`) and the PM re-ran the gate against the merged tree rather than
  trusting the merge:
  - `zsh tests/topology_compare_test.sh` → exit 0,
    `PASS: topology compare reports literal metrics, limits, personas, and copy retention`.
  - `zsh tests/pm_flow_test.sh` → exit 0, 10 `PASS:` lines.
  - `zsh tests/packaged_layout_test.sh` → exit 0, 13 `PASS:` lines including
    `a copied-engine repository migrates losslessly and keeps running`.
  - The T5 `cost.py` edit survived the merge: `template/.agentic/pm_flow/cost.py`
    carries `tp.key AS topology` and the `topologies` join in `stored_attempts`
    (`:234`, `:237`) and the appended `present(row["topology"])` in
    `report_store` (`:264`); `tests/topology_compare_test.sh` holds the wheel
    block (95 `wheel` matches).
  So A6 holds on `main`, not only on the developer's tree, and A1-A5 are
  re-observed through the gate suite that asserts them.

## Completed tasks and evidence

- T1 — topology documents, the CLI model registry, and validation. Accepted
  cycle 002. Acceptance IDs: A4, plus the A6 regression gate.
  - `zsh tests/topology_compare_test.sh` → exit 0,
    `PASS: topology documents validate, overlay read-only, and refusals precede dispatch`.
    `lean` and `heavy` validate; their overlays differ from `config.json` in
    exactly the developer model and the consultant seat count
    (`gpt-5.6-sol`/`gpt-5.1-codex`/`gpt-5.6-sol`, seats `2`/`1`/`3`, with every
    other role and every non-`roles` key asserted equal); `validate missing`
    exits non-zero naming the key and `$FLOW/topologies/missing.json`; the
    `gpt-not-a-model` document exits non-zero naming `developer`, `codex` and
    the model; `attempts` is unchanged across both refusals.
  - The byte-identity `cmp` is now capable of failing. It sits at
    `tests/topology_compare_test.sh:125`, after every topology command and
    before the suite's own rewrite of `config.json` at `:133`. Reviewer
    mutation, 2026-08-24: a copy of the suite with one line inserted
    immediately above the `cmp` appending `corrupted` to `config.json` exits 1
    with `FAIL: topology commands changed config.json`; the unmutated suite
    exits 0. Cycle 001's placement passed under the same corruption.
  - `install.sh` names the new engine file and directory:
    `topology.py` in `COPIED_ENGINE_FILES`, `topologies` in
    `COPIED_ENGINE_DIRS`. `zsh tests/packaged_layout_test.sh` → exit 0, all 13
    `PASS:` lines, with the migrated flow directory reading exactly
    `.gitignore .project-key config.json local_env.sh.example projects.md salvage-legacy`.
    Reviewer negative check, 2026-08-24: with those two entries stripped, the
    same suite exits 1 —
    `FAIL: the migrated flow directory holds project data only: … got '… salvage-legacy topologies topology.py '`.
    `install.sh` was restored byte-identical afterwards.
  - `zsh tests/pm_flow_test.sh` → exit 0, all 10 `PASS:` lines. The `models`
    lists added to `clis.capabilities` do not change how `config.json`'s
    `gpt-stub` and `fixture-model` bindings resolve.

- T2 — run two arms from one commit. Accepted cycle 003 with changes.
  Acceptance IDs: A1, A5, plus the A6 regression gate.
  - `zsh tests/topology_compare_test.sh` → exit 0,
    `PASS: topology compare runs isolated arms and imports topology/persona provenance`.
    After `pm-flow compare lean heavy --max-ticks 5` on the stub project,
    `SELECT t.key || '|' || p.key FROM runs r JOIN topologies t … JOIN projects p … ORDER BY t.key`
    returns exactly `heavy|topology-project` / `lean|topology-project` — the
    asserted two-line string, not a count. Both arms' `copy_path` values are
    read from the command's own stdout, differ from each other and from the
    origin checkout; `starting_commit=` appears exactly once and equals the
    origin's `git rev-parse HEAD`; each copy's `config.json` `cmp`s equal to its
    arm's overlay and the origin `config.json` `cmp`s unchanged.
  - A5 is asserted in both directions and is capable of failing. The store query
    over `attempts.persona_stack` for `role_key='pm'`, base layer, returns
    `heavy|pm` and `lean|cpo`. Reviewer mutation, 2026-08-24: replacing
    `compare.py:363` `swap_first_arm(arms[0], engine, project)` with `pass`
    turns the suite red —
    `FAIL: persona swap is confined to the first arm: expected 'heavy|pm\nlean|cpo', got 'heavy|pm\nlean|pm'`.
    `compare.py` was restored byte-identical (`cmp` clean) and the suite re-run
    green afterwards.
  - The import is idempotent at the run-key boundary: re-importing arm one's
    store through `compare.py`'s own `import_store` leaves the `runs`/`attempts`
    counts unchanged.
  - Developer mutations, each reversed: both arms at one checkout →
    `ERROR: topology 'heavy' produced no run`; validation dropped →
    `FAIL: compare accepted a missing topology`; second import skipped →
    `FAIL: compare imports both topology runs under one project: expected 'heavy|topology-project\nlean|topology-project', got 'lean|topology-project'`.
  - `install.sh` names `compare.py` in `COPIED_ENGINE_FILES`.
    `zsh tests/packaged_layout_test.sh` → exit 0, 13 `PASS:` lines;
    `packaged_layout_test.sh` itself is untouched, so the exact migrated-directory
    listing at `:1018-1020` is what proves it.
    `zsh tests/pm_flow_test.sh` → exit 0, 10 `PASS:` lines.

- T3 — the report and its limits. Accepted cycle 004 with changes.
  Acceptance IDs: A2, A3, A5, plus the A6 regression gate.
  - `zsh tests/topology_compare_test.sh` → exit 0,
    `PASS: topology compare reports literal metrics, limits, personas, and copy retention`.
  - A2. `compare --report lean-fixture-1 heavy-fixture-1` on the seeded
    `report-project` store prints, as exact strings, `cost_usd 4.0000 2.5000`,
    `tokens 310 250`, `cycles_to_done 2.00 2.00`, `rescue_rate 0.33 0.00`,
    `abandon_rate 0.33 0.00`, `escalation_depth 1 1`, `wall_clock_s 30.0 12.5`,
    `n_runs 2 1`, under the header `metric lean heavy` — every expected value
    written literally in the suite, not recomputed by it. The fixture is seeded
    through `telemetry.py run-start|attempt-start|attempt-end|outcome`, so each
    figure is hand-computable: lean is `lean-fixture-1` (1.25+0.25+0.50+0.75+0.25)
    plus `lean-fixture-2` (0.50+0.50) = 4.00 over 3 sections, one rescued
    (`10x_developer` on `alpha`) and one abandoned (`beta`).
  - A2 reconciliation, the one-accounting check: `python3 cost.py total
    <report-project>` → `6.5000`, equal to `4.0000 + 2.5000`.
  - A3. The report's last line is
    `Limits: lean n=2; heavy n=1. No difference between the arms can be inferred.`
    on the two-run fixture and
    `Limits: lean n=1; heavy n=1. No difference between the arms can be inferred.`
    on the driven compare — different sizes from different data, so the sizes
    are read from the store rather than printed.
  - A5. After `compare lean heavy --max-ticks 5 --persona lean:pm=cpo`, the
    per-arm block reads `arm lean / personas pm=cpo` and `arm heavy /
    personas pm=pm`, and the store query over `attempts.persona_stack` still
    returns `heavy|pm` and `lean|cpo`. Asserted in both directions.
  - T2's carried defect is cleared and the clearing is observed, not asserted
    from source: a second compare with no `--persona` leaves both arms on the
    base persona — `heavy|pm` / `lean|pm`.
  - Copy retention is observed from the command's own stdout:
    `--keep-copies` prints `copy_status=retained` on both arm lines, the default
    prints `copy_status=removed` on both.
  - A6. `zsh tests/pm_flow_test.sh` → exit 0, 10 `PASS:` lines;
    `zsh tests/packaged_layout_test.sh` → exit 0, 13 `PASS:` lines.
  - Reviewer mutations, 2026-08-24, each applied to the developer's tree, run,
    and reversed (`git status` clean to the four expected files afterwards);
    harness at `cycles/004/review_mutations.zsh`. All eleven the assignment
    required reproduce their failure line: `n_runs`→1, `escalation_depth`→0,
    `tokens`→`input_tokens`, `cycles_to_done`→`MAX`, rescue role→`developer`,
    `abandon_rate`→`complete`, `wall_clock_s`→`COUNT(*)`, limits sentence
    deleted (`got 'personas pm=pm'`), `--persona` dropped from the test
    (`got 'heavy|pm\nlean|pm'`), `outcomes` import skipped
    (`cycles_to_done` `expected '1.00 1.00', got '- -'`), and `do_abandon`'s
    record removed.
  - The `cost_usd`→`topology_comparison` mutation is caught by a source grep,
    not by output, and the developer said so. Verified: with the mutation
    applied *and* the grep guard removed, the suite still passes — the view
    (`store.py:422-437`) sums `COALESCE(a.cost_usd, 0)` per run over a LEFT
    JOIN, which is arithmetically the same number. The behavioural guard on
    "one accounting" is the `cost.py total` reconciliation above, and it holds.
  - `import_store` carries `topology_edges` and `outcomes` and is idempotent.
    Reviewer probe (`cycles/004/review_edges_probe.zsh`): a source store with 8
    edges and two runs imports to 8 edges; a second `import_store` returns `[]`
    and leaves 8. `topology_edges` has `UNIQUE (topology_id, from_role,
    to_role, kind)`, so the `INSERT OR IGNORE` is sound.

- T4 — the command outside the fixture's flow directory. Accepted cycle 005.
  Acceptance IDs: A1, A2, A3, A4, plus the A6 regression gate.
  - `zsh tests/topology_compare_test.sh` → exit 0,
    `PASS: topology compare reports literal metrics, limits, personas, and copy retention`.
    The suite gains a second work tree whose `.agentic/pm_flow/` is asserted to
    hold exactly `.project-key config.json data-topology-project local_env.sh` —
    no `topologies/`, `roles/`, `domains/`, no engine files — driven with
    `PM_FLOW_ENGINE_ROOT` at the engine copy. Every prior assertion is kept
    (177 insertions, 0 deletions in the test), so the `cmp` at `:125` and T1's
    `$FLOW/topologies/missing.json` refusal still stand where they were.
  - A4, from the data-only tree. `compare heavy missing` exits non-zero, writes
    nothing to stdout, and leaves `attempts` unchanged. Reviewer read the actual
    stderr, 2026-08-24:
    `ERROR: topology 'missing' is missing; expected document at <data-only>/.agentic/pm_flow/topologies/missing.json; also looked at <engine>/topologies/missing.json`
    — the flow path first, the engine path named after it.
  - A1, from the data-only tree. `SELECT DISTINCT t.key || '|' || p.key …`
    returns exactly `heavy|data-topology-project` / `lean|data-topology-project`.
    Both `copy_path` values are read from the command's own stdout, differ from
    each other and from the origin checkout.
  - A2. Reviewer read the driven report off the command's stdout, 2026-08-24:
    the `wall_clock_s` row is `4.4` / `702.4`, both greater than zero, where
    cycle 004 could only ever print `0.0 0.0`. Both imported runs have a
    non-NULL `ended_at` and a status other than `running`
    (`heavy|1` / `lean|1`). The seeded fixture's literal values are unchanged.
  - A3. Each arm dispatches twice — two sections, each with a `COMPLETE`
    decision — and the store reads `heavy|1|2` / `lean|1|2` (runs|attempts),
    while the report's last line is
    `Limits: lean n=1; heavy n=1. No difference between the arms can be inferred.`
    The sentence is therefore shown to count runs, not dispatches.
  - Edge import. `topology_edges` for `lean` in the origin store equals the
    retained arm store's set and is non-empty.
  - A6. `zsh tests/pm_flow_test.sh` → exit 0, 10 `PASS:` lines;
    `zsh tests/packaged_layout_test.sh` → exit 0, 13 `PASS:` lines;
    `zsh tests/store_ledger_test.sh` → exit 0, `store ledger tests passed`;
    `zsh tests/trace_commands_test.sh` → exit 0, `trace command tests passed`.
    The developer could not run the trace suite — its loopback receiver could
    not bind in their sandbox — and reported the cycle PARTIAL for that reason.
    The reviewer ran it against the same tree and it is green, so the run's
    changed scope regresses neither store suite.
  - Reviewer mutations, 2026-08-24, each applied to the developer's tree, run,
    and reversed (the worktree diff is byte-identical to the reviewed state
    afterwards). All five the assignment required reproduce a failure line:
    engine fallback out of `load_document` →
    `FAIL: data-only refusal omitted the flow topology path`; out of the persona
    lookup → `FAIL: data-only persona swap could not resolve a packaged persona`;
    `telemetry_end_run` call sites neutralised →
    `FAIL: data-only compare wall clocks are not both greater than zero`;
    the two parent `telemetry_begin_run` calls removed →
    `FAIL: data-only arm size counts one run containing two attempts: expected 'heavy|1|2 lean|1|2', got 'heavy|2|2 lean|2|2'`
    — the `n_runs` assertion goes red, not merely `wall_clock_s`;
    the edge SELECT disabled → `FAIL: data-only import omitted topology edges`.

- T5 — scenarios 1-3 through the installed wheel. Accepted cycle 006.
  Acceptance IDs: A1, A2, A3, A4, A5, plus the A6 regression gate.
  - `zsh tests/topology_compare_test.sh` → exit 0,
    `PASS: topology compare reports literal metrics, limits, personas, and copy retention`.
    Run twice by the reviewer, 2026-08-24, both green. The suite now builds the
    wheel itself: a build venv installs the pinned wheelhouse under
    `--require-hashes`, `pip wheel --no-index --no-build-isolation --no-deps`
    produces exactly one `pm_flow-*.whl`, and a separate runtime venv installs it
    `--no-index --no-deps`. The build reaches no index; the suite also refuses if
    an inherited `PIP_*`/`UV_*` setting survives into it.
  - The engine answers from the venv, not the checkout. `command -v pm-flow`
    under the fixture's `PATH` is asserted equal to `<runtime-venv>/bin/pm-flow`;
    `pm_flow.paths.engine_root()` is asserted to sit inside that venv; the
    runtime venv is asserted not to contain the build backend. No
    `PM_FLOW_ENGINE_ROOT`, `PM_FLOW_FLOW_DIR` or `PYTHONPATH` is set anywhere in
    the wheel block — `PYTHONPATH` is unset before it (`:561`) — so cycle 005's
    variables cannot be answering for the wheel.
  - The fixture repository holds project data only: its `.agentic/pm_flow/`
    is asserted, dotfiles included, to be exactly
    `.project-key config.json local_env.sh wheel-topology-project` — no
    `topologies/`, `roles/` or `domains/`. So the topology documents the compare
    resolves can only have come from the wheel.
  - A1. After `pm-flow --project wheel-topology-project compare lean heavy
    --max-ticks 6`, the store reads exactly
    `heavy|wheel-topology-project` / `lean|wheel-topology-project`. Both
    `copy_path` values are read from the command's own stdout, differ from each
    other and from the origin checkout, and `starting_commit=` equals the
    fixture's `git rev-parse HEAD`.
  - A2. The header is `metric lean heavy` and the eight contract rows print in
    order (`cost_usd tokens cycles_to_done rescue_rate abandon_rate
    escalation_depth wall_clock_s n_runs`), asserted as a string, from the wheel
    command's stdout. Both `wall_clock_s` values are `> 0`. The seeded fixture's
    literal values are untouched — the test file's diff is 264 insertions and 0
    deletions, so the `cmp` at `:125` and T1's `$FLOW/topologies/missing.json`
    refusal still stand where they were.
  - A3. The last line is
    `Limits: lean n=1; heavy n=1. No difference between the arms can be inferred.`
    and the store's own run count per topology is asserted separately as
    `heavy|1` / `lean|1`, so the sentence is shown to count runs.
  - A4, now against a non-zero baseline. `compare heavy missing` runs *after* the
    successful compare: the attempt count before it is asserted `> 0`, the
    command exits non-zero, writes nothing to stdout, names both
    `<fixture-flow>/topologies/missing.json` and
    `<venv>/…/pm_flow/engine/topologies/missing.json` on stderr, and leaves the
    attempt count equal to that non-zero baseline. Cycle 005's `0 == 0` is
    retired.
  - A5. The wheel report's per-arm block reads `lean|pm=pm` / `heavy|pm=pm` and
    the store's `attempts.persona_stack` base layer agrees in both directions.
    The differentiating case — a swap on one arm only — remains the
    mutation-tested `--persona lean:pm=cpo` block from T3.
  - Scenario 3. `pm-flow cost` immediately after the compare prints `ATTEMPT`
    lines of exactly 10 tab fields; field 10 read with `awk -F'\t'` and `sort -u`
    is exactly `heavy` / `lean` — an exact field match, not a substring. `TOTAL`
    equals `cost.py total` on the same project, so there is one accounting.
  - Reviewer negative check on field 10, 2026-08-24, at the data level rather
    than by editing source (`cycles/006/review_probe.zsh`): a throwaway store
    with three attempts — one on a `lean` run, one on a `heavy` run, one with no
    `run_id` — reports field 10 as `lean`, `heavy` and `-` respectively, and
    `TOTAL 1.2500` still includes the run-less attempt's `0.25`. The field is
    therefore data-derived and no topology filter reached any sum. Dropping the
    join would make every field 10 read `-`, which is the developer's reported
    mutation line (`expected 'heavy\nlean', got '-'`).
  - `cost.py`'s diff is 4 insertions and 1 deletion, confined to
    `stored_attempts`' SELECT (the two joins and `tp.key AS topology`) and one
    appended `present(row["topology"])` in `report_store`. `stored_totals`,
    `import_legacy` and every sum are untouched, and the first nine fields keep
    their order.
  - A6. `zsh tests/pm_flow_test.sh` → exit 0, 10 `PASS:` lines;
    `zsh tests/packaged_layout_test.sh` → exit 0, 13 `PASS:` lines including
    `a copied-engine repository migrates losslessly and keeps running`;
    `zsh tests/store_ledger_test.sh` → exit 0, `store ledger tests passed`;
    `zsh tests/prompt_quality_test.sh` → exit 0, 4 `PASS:` lines;
    `zsh tests/agent_bindings_test.sh` → exit 0, 17 `PASS:` lines. All five run
    by the reviewer against the developer's tree.
  - Suite runtime, measured by the reviewer (`cycles/006/review_timing.zsh`):
    `exit=0 elapsed_s=49` for the whole gate suite including the offline wheel
    build. Cycle 005's timeout risk did not recur.
  - The three environment mutations the developer reported were confirmed by
    reading the assertions rather than re-running them: the `PATH` mutation is
    caught by `assert_eq "$wheel_command_path" "$WHEEL_PM_FLOW"`, the removed
    `topologies` directory by `[[ -d "$WHEEL_ENGINE/topologies" ]] || fail "the
    installed wheel omits its topology documents"`, and the reordered refusal by
    `(( wheel_attempts_before > 0 ))` — each an unconditional `fail` under
    `set -euo pipefail`, and each matching the failure line reported verbatim.
    A PM does not edit source, so the source-side mutation was verified through
    the data probe above instead.

## Active decisions

- Engine Python lives in `template/.agentic/pm_flow/`, not `src/pm_flow/`.
  `src/pm_flow/cli.py:69-87` forwards unrecognised commands straight to
  `pm_flow.sh`, and `store-ledger` shipped `cost.py` under `template/`. So
  `topology.py` and `compare.py` go beside `cost.py`, and `pm-flow compare` is
  a dispatcher case in `pm_flow.sh` with a `cmd_compare` in `driver.zsh`. The
  brief's owned paths are wrong on this point; the workplan carries the
  correction, and it is worth raising upward at handoff so other sections do
  not repeat it. No acceptance ID changes.
- A topology document never edits `config.json`. `topology.py overlay` prints
  the merged config; the compare command writes that text into the arm's
  disposable copy only. `agent_exec.sh:50` reads `$FLOW_DIR/config.json`, so a
  per-copy file is all that is needed to redirect an arm's bindings.
- No model list exists anywhere in the engine today. `register_clis`
  (`catalog.py:218-278`) records `thinking_levels` and `capabilities` per CLI
  and nothing about models; the `clis` table has no models column. A4's
  "a model the bound CLI does not list" therefore needs a list, and it goes
  inside the existing `capabilities` JSON blob — a value change, no schema
  change. Deterministic and offline; the alternative, probing the live CLI,
  would make the acceptance check depend on the network.
- The model check applies to topology documents only. `config.json` in the
  test suites binds `gpt-stub` and `fixture-model`; validating those would
  break `pm_flow_test.sh` and `packaged_layout_test.sh`.
- Cost comes from `store-ledger`'s `cost.py total`. The `topology_comparison`
  view (`store.py:422-437`) sums `attempts.cost_usd` itself; using it for
  `cost_usd` would be the second accounting the brief rejects. The view stays
  in use for attempts, tokens, duration and status.
- A persona swap is an operator argument, not something the command does.
  Probed 2026-08-24: a swap is stored per `(project, topology, role)` in the
  project store (`catalog.py:400-430`), and an arm copy is a `git clone`
  (`compare.py:45-52`) whose store starts empty — so a swap made in the origin
  store cannot reach an arm, and only the compare command can reach the arm's
  store between `sync` and `run`. Hence `--persona <topology>:<role>=<persona>`
  on `compare run`: no swap unless asked for, and the arms otherwise differ by
  their topology alone. This replaces cycle 003's hardcoded `swap_first_arm`.
- The report's columns are defined against facts the store actually holds; the
  formulas and their formats live in `workplan.md` T3. Two consequences worth
  keeping here: `rescue_rate` reads `role_key='10x_developer'`, because
  `do_rescue` (`driver.zsh:1903-1909`) is that role's only dispatch site; and
  `abandon_rate` needs a record that does not exist yet, because `do_abandon`
  (`driver.zsh:2070-2089`) dispatches nothing at all. The `outcomes` table and
  `telemetry.py outcome` (`store.py:369-383`, `telemetry.py:753-777`) are built
  for exactly this and no engine code emits to them, so T3 emits
  `section_status` at `do_abandon` and `do_complete`. A column that can only
  ever read zero would be a report that describes nothing.
- `cost_usd` reuses `cost.py` as a module — `import_legacy` then
  `stored_totals`' own `SUM(COALESCE(a.cost_usd, 0))` restricted to the arm's
  runs — and `cost.py` is not edited. The reconciliation assertion (both arms
  summing to `cost.py total`) is what makes "one accounting" checkable rather
  than a matter of style.
- Arm copies are deleted once imported, unless `--keep-copies`. Settled at T3;
  before the report existed, the clone was the only way to inspect an arm.
- Packaged assets resolve flow-first, engine-second, and are never copied into a
  repository. The flow directory is the repository's own data; `topologies`,
  `roles` and `domains` ship in the wheel, and migration removes them from any
  repository that still holds a copy. So the fix for the installed case is a
  fallback in the reader, never an install.sh entry that writes documents into a
  repository — that would put the engine back in the data directory and turn
  `packaged_layout_test.sh:1018-1020` red.
- A `runs` row is one invocation of `pm-flow run`/`tick`, not one dispatch.
  Settled at T4 scoping: the lazy `telemetry_begin_run` inside the dispatch
  subshell makes a run an accident of subshell scoping, which the report then
  prints as an arm size. The cost is that an invocation which dispatches nothing
  records a run; that is the honest reading of "n_runs".
- One disposable checkout per arm, from the same starting commit; rows
  imported back under the arm's key. Probed 2026-08-24: an arm needs no new
  dispatch path — `telemetry_begin_run` (`driver.zsh:679-690`) already reads
  `PM_FLOW_TOPOLOGY` into both `catalog.py sync --topology` and `telemetry.py
  run-start --topology`, and `run-start` (`telemetry.py:412-446`) stamps
  `runs.topology_id`. The import is store-to-store and has no existing helper;
  it belongs in `compare.py`, keyed on `runs.run_key`. An arm copy is a
  separate checkout rather than a `git worktree`, because worktrees are already
  the sections' mechanism and `cmd_run` prunes them at every start.

## Blockers

- Open residual, disclosed by the developer at cycle 005 and confirmed by the
  reviewer: an exit through `fail` or `set -e` after `telemetry_begin_run`
  leaves the run open. Every explicit `return` in `cmd_run` and `cmd_tick` now
  calls `telemetry_end_run` — including `cmd_run`'s deadlock and quarantine
  returns and `cmd_tick`'s `waiting`/`quarantined`/`idle` returns — but
  `assert_within_budget` (`cmd_tick:2811`, `cmd_run:2889`) exits the process
  through `fail`, so that invocation's `runs.ended_at` stays NULL and it drops
  out of `wall_clock_s`. Closing it needs an `EXIT` trap at driver top level,
  which was outside T4's writable fence (`driver.zsh`, the `cmd_run` and
  `cmd_tick` call sites only). Not a T5 acceptance; give it its own task if the
  budget-exhausted run has to be measurable.
- Handoff obligation, not a blocker: this section edited `store-ledger`'s
  `cost.py` at T5. The `ATTEMPT` line is now ten fields, the tenth being the
  attempt's run topology key (`-` when the attempt has no run or the run no
  topology). The first nine keep their positions and `stored_totals`,
  `import_legacy` and every sum are unchanged, so it is a presentation change
  and not a second accounting. Six call sites across four suites read those
  positions; all four suites are green. Name this in the handoff so
  `store-ledger` and any downstream reader of `pm-flow cost` know the shape
  changed.
- Standing note for anyone widening the `ATTEMPT` line again: its consumers are
  `tests/store_ledger_test.sh`, `tests/agent_bindings_test.sh:367-370`,
  `tests/prompt_quality_test.sh` (through
  `template/.agentic/pm_flow/tests/transitions.zsh:196`, `:318` and
  `tests/on_demand.zsh:172`), and `driver.zsh:887` (`dispatch_count`, a
  `^ATTEMPT` count). All read fields 1-7 or a count, which is why a trailing
  tenth field broke none of them. A change to fields 1-9 would break all four.
- Arm wall clock still varies and nothing bounds an arm's run. Cycle 005 saw a
  `heavy` arm take 702.4s against `lean`'s 4.4s and exceed a 600s suite timeout.
  Cycle 006 did not reproduce it: three reviewer runs of the gate suite, now
  including an offline wheel build, all finished green, one timed at 49s. The
  variance is real elapsed time and not a reporting defect; if the suite starts
  timing out, bound the arm rather than loosening `wall_clock_s > 0`.
- The migration rule stays open as a standing rule
  for the rest of the section: every task that adds a file under
  `template/.agentic/pm_flow/` must add its name to `install.sh`'s
  `COPIED_ENGINE_FILES` or `COPIED_ENGINE_DIRS` in the same cycle, or
  `packaged_layout_test.sh` turns red. `install.sh:40-46` states those lists are
  "the whole of what migration removes". `compare.py` reintroduces this at T2;
  its T2 path list already names `install.sh`. `install.sh` is an owned path for
  this section that the brief does not list.
- `store-ledger` is not a blocker. Its handoff records A1-A5 with evidence and
  four suites exiting 0 on `main` `75462bd`, so its `cost.py total` interface
  is available to T3. T1 and T2 never needed it.

## Verified, to be carried rather than re-derived

- `topology.py`'s A4 behaviour is sound and mutation-tested by the reviewer at
  cycle 001: removing the model-membership check, dropping the expected path
  from the missing-document refusal, and ignoring the document's `roles` in the
  overlay each turn `tests/topology_compare_test.sh` red. The model check is
  correctly scoped to roles the document names, so `config.json`'s fixture
  models still pass. Cycle 002 left `topology.py`, both documents and
  `catalog.py` untouched — their mtimes are cycle 001's, `12:41-12:42`, against
  `12:54` and `12:57` for `install.sh` and the test — so that evidence stands.
- `packaged_layout_test.sh` catches an unmigrated engine name two ways, and only
  one of them is live for new names. Its local `COPIED_ENGINE_FILES` /
  `COPIED_ENGINE_DIRS` mirror (`:670-675`) lists what *old* installs copied and
  deliberately does not track new engine files; what caught `topology.py` is the
  exact directory listing at `:1018-1020`. Do not "fix" the mirror when a future
  file fails migration — the failure is `install.sh`'s to answer.

## Next eligible task

- None. T5 was the workplan's last task and the section's gate; it was accepted
  at cycle 006 with A1-A6 evidenced through the installed entry point. The
  section is complete and the next step is the handoff, not another cycle.
- Three things belong in that handoff rather than in a new task: the `ATTEMPT`
  line's tenth field (`store-ledger`'s file, this section's edit), the
  brief's owned-paths correction, and the `fail`-path open run as a disclosed
  limitation. No acceptance ID depends on the last of those.
