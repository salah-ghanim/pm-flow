# topology-compare workplan

## Design summary

- A topology is a JSON document holding a `roles` block in `config.json`'s
  shape. It is never merged into the shared `config.json`: `topology.py`
  validates it, then emits an *overlay* — the merged config text — which the
  compare command writes into that arm's disposable copy of the repository.
  Each arm is driven with `PM_FLOW_TOPOLOGY=<key>` from the same starting
  commit, its store rows are imported back under its key, and the report is
  printed descriptively from `cost.py`'s totals plus the store's run and
  attempt records, always closing with the limits sentence.

## Where the code actually lives

The brief's owned paths name `src/pm_flow/topology.py` and
`src/pm_flow/compare.py`. That is not where this engine keeps Python. Probed
2026-08-24:

- `src/pm_flow/` holds only the packaging shim — `cli.py`, `paths.py`,
  `acp.py`, `semconv.py`. `cli.py:69-87` forwards every command it does not
  recognise to `zsh <engine>/pm_flow.sh`; it has no per-command logic and
  needs none for `compare`.
- The engine, and every engine-side Python module, lives in
  `template/.agentic/pm_flow/` — `catalog.py`, `cost.py`, `store.py`,
  `telemetry.py`, `watch.py`. `paths.py:67-69` resolves that directory as
  `engine_root()` in a source checkout.
- `store-ledger` shipped `cost.py` there, not under `src/`.

So this section's modules are `template/.agentic/pm_flow/topology.py` and
`template/.agentic/pm_flow/compare.py`, and the user-visible command is a case
in `pm_flow.sh`'s dispatcher (`:1912-1999`) calling a `cmd_compare` in
`driver.zsh`, exactly as `cost` does (`pm_flow.sh:1937`, `driver.zsh:466`).
`src/pm_flow/cli.py` stays untouched. The brief's document path
(`template/.agentic/pm_flow/topologies/**`) is already correct and is where the
documents go. This mapping is a correction to the brief's owned paths, not a
change of scope; every acceptance ID is unaffected.

## Interfaces and data changes

- `template/.agentic/pm_flow/topologies/<key>.json`: `{version, key, name,
  description, roles}` where `roles` has `config.json`'s shape — a binding
  object or a list of seat objects, each `{cli, model, difficulty}`.
- `topology.py` module CLI, in the style of `cost.py`: `validate <key>
  --flow <dir>`, `overlay <key> --flow <dir>` (prints merged config JSON to
  stdout), `list --flow <dir>`; T4 adds `--engine <dir>`, defaulting to the
  module's own directory, and every document, domain and persona lookup reads
  the flow directory first and the engine second.
- `cost.py report`'s `ATTEMPT` line gains one trailing field at T5, the
  attempt's run topology key. Nothing else about `cost.py` changes.
- `pm-flow compare <a> <b> [--max-ticks n]` and `pm-flow compare --report
  <run-a> <run-b>`; the column contract `cost_usd`, `tokens`,
  `cycles_to_done`, `rescue_rate`, `abandon_rate`, `escalation_depth`,
  `wall_clock_s`, `n_runs`.
- No SQL schema change. `runs.topology_id`, `topologies`, `topology_agents`
  and the `topology_comparison` view already exist (`store.py:200-243`,
  `:283-302`, `:422-437`). The one data addition is a `models` list per CLI
  inside the existing `clis.capabilities` JSON blob, written by
  `register_clis` (`catalog.py:218-278`) — a value change, not a column.

## Task T1 — Topology documents, their model registry, and validation

- Status: done (cycle 002). A4 met; the A6 regression gate holds.
- Outcome: `topology.py` loads `topologies/<key>.json`, validates it against
  the CLI registry and the engine's personas, refuses a missing document or a
  model the bound CLI does not list, and emits the merged overlay without
  touching `config.json`. Two documents ship: `lean.json` and `heavy.json`,
  differing in the developer model and the consultant seat count.
- Paths: `template/.agentic/pm_flow/topology.py`,
  `template/.agentic/pm_flow/topologies/lean.json`,
  `template/.agentic/pm_flow/topologies/heavy.json`,
  `template/.agentic/pm_flow/catalog.py` (the `models` lists only),
  `install.sh` (`topology.py` in `COPIED_ENGINE_FILES`, `topologies` in
  `COPIED_ENGINE_DIRS`),
  `tests/topology_compare_test.sh` (new).
- Reuse:
  - `pm_flow.sh:504-546` (`cmd_config`) is the existing binding validator —
    seat shape, `cli` allowlist, `difficulty` allowlist, persona file present,
    domain title present. Apply the same rules to a topology document rather
    than writing new ones.
  - `agent_exec.sh:163-203` is the same validation at dispatch time; the
    refusal wording there is the register to match.
  - `catalog.py:218-278` (`register_clis`) is where each backend's facts are
    data; the model list belongs in the same `known` dict, inside
    `capabilities`.
  - `catalog.py:621-748` (`sync`) shows how a `roles` block becomes seats, so
    an overlay in that shape needs no new reader.
  - `cost.py`'s `main(argv)` is the module-CLI shape to copy.
- Acceptance IDs: A4.
- Validation: `zsh tests/topology_compare_test.sh` — `lean` and `heavy`
  validate and their overlays differ from `config.json` in exactly the
  developer model and the consultant seat count; `missing` exits non-zero
  naming the absent key and its expected path; a document naming
  `gpt-not-a-model` exits non-zero naming the role, the cli and the model;
  after both refusals `config.json` is byte-identical (`cmp`) and the store
  holds no new `attempts` row. The `cmp` must sit before the suite's own
  rewrite of `config.json`, so that corrupting the file makes it fail.
  `zsh tests/packaged_layout_test.sh` and `zsh tests/pm_flow_test.sh` exit 0:
  the new engine file and directory are named in `install.sh`, so a migrated
  flow directory still holds project data only.
- Depends on: None.

## Task T2 — Run two arms from one commit

- Status: done (cycle 003), with one carried defect that T3 must clear.
  A1 and A5 met; the A6 regression gate holds. Carried defect: `compare.py`
  performs the A5 persona swap itself — `swap_first_arm` at `:363` calls
  `catalog.py persona swap pm cpo` on `arms[0]` unconditionally — so every real
  `pm-flow compare a b` swaps the PM seat's base persona on the first arm only.
  That is a confound in the shipped command, not a feature the brief asks for.
  T3 removes it; see T3's first requirement.
- Outcome: `pm-flow compare a b --max-ticks n` validates both topologies
  first, makes one disposable copy of the checkout per arm at the same
  starting commit, writes each arm's overlay into that copy's `config.json`,
  drives each arm to completion under `PM_FLOW_TOPOLOGY=<key>`, and imports
  each arm's store rows back into the origin store under its own key.
- Paths: `template/.agentic/pm_flow/compare.py`,
  `template/.agentic/pm_flow/driver.zsh` (`cmd_compare`),
  `template/.agentic/pm_flow/pm_flow.sh` (the dispatcher case and `usage`),
  `install.sh` (`compare.py` in `COPIED_ENGINE_FILES`),
  `tests/topology_compare_test.sh`.
- Reuse: the stub-CLI harness in `tests/pm_flow_test.sh`
  (`install_driver_stub`, `:998-1010`, and `tests/fixtures/stub_success.zsh`);
  `cmd_cost` (`driver.zsh:466`) as the shape of a Python-backed command;
  `catalog.py sync --topology` for registering each arm's seats;
  `catalog.py persona swap --topology` (`catalog.py:1631`) for the swapped seat.
- Probed 2026-08-24, and settled for T2:
  - An arm needs no new dispatch path. `telemetry_begin_run`
    (`driver.zsh:679-690`) already reads `PM_FLOW_TOPOLOGY`, passes it to
    `catalog.py sync --topology` and to `telemetry.py run-start --topology`,
    and `run-start` (`telemetry.py:412-446`) inserts the `topologies` row and
    stamps `runs.topology_id`. So an arm is `PM_FLOW_REPO_ROOT=<copy>
    PM_FLOW_TOPOLOGY=<key> pm-flow run --max-ticks n`, and its own store
    already carries the key. `PM_FLOW_REPO_ROOT` is how `tests/pm_flow_test.sh`
    drives a second repository (`:1044-1046`).
  - Each arm's store is `<copy>/.agentic/pm_flow/<project>/runs/pm_flow.db`
    (`store.default_path`). The import is therefore store-to-store, and no such
    helper exists: nothing in `store.py`, `cost.py` or `telemetry.py` reads a
    second database. `cost.py import_legacy` (`:104`) is only TSV-to-store.
    Write the importer in `compare.py`, keyed on `runs.run_key` (UNIQUE,
    `store.py:287`) the way `cost.py` keys on `response_path`, re-pointing each
    imported `attempts` row at the new `run_id`.
  - `git worktree` is already taken for sections (`ensure_section_worktree`,
    `driver.zsh:2310`; `prune_section_worktrees` runs at the top of every
    `cmd_run`). An arm must not collide with that machinery, and the brief's
    non-goal is two arms in one checkout, so an arm copy is its own checkout.
- Acceptance IDs: A1, A5.
- Validation: `zsh tests/topology_compare_test.sh` — after a compare of two
  arms with a persona swapped on one seat of one arm, `runs` holds rows under
  both topology keys with one `projects.key`; each arm's attempts carry that
  arm's persona key; the two arms' working copies are distinct paths; and a
  mutation that points both arms at one checkout fails the suite.
- Depends on: T1.

## Task T3 — The report and its limits

- Status: done (cycle 004), with two gaps T4 carries. A2, A3 and A5 met; the A6
  regression gate holds. T2's carried defect is cleared: `swap_first_arm` is
  gone and `compare lean heavy` with no `--persona` leaves both arms on `pm`.
  Gaps for T4: (a) `wall_clock_s` reads `0.0` in every real compare, because
  `telemetry_end_run` (`driver.zsh:752`) has no call site anywhere in the
  engine, so `runs.ended_at` is NULL and `SUM(ended_at - started_at)` is NULL;
  the formula is right and the seeded fixture proves it, but the shipped column
  is inert. (b) `import_store`'s `topology_edges` half has no check behind it —
  the importer works, but disabling it leaves the suite green.
- First requirement, carried from T2: delete `swap_first_arm` and its call site
  from `compare.py`. `pm-flow compare` must run both arms with the seats their
  topology documents and the shared persona configuration give them, so the only
  difference between arms is the topology — unless the operator asks for more.
  A persona swap is therefore an operator argument, `--persona
  <topology>:<role>=<persona>` (repeatable), applied to the named arm after its
  `catalog.py sync` and before its run. Probed 2026-08-24: a swap is stored per
  `(project, topology, role)` in the project store (`catalog.py:400-430`,
  `seat_layer_overrides`), and an arm copy is a `git clone` (`compare.py:45-52`)
  whose store starts empty, so a swap made in the origin store cannot reach an
  arm and the arm's own store is the only place it can be made. Keep the
  existing two-directional store assertion (`heavy|pm`, `lean|cpo`); it is
  mutation-tested and must stay capable of failing when the swap is absent, and
  it now proves the flag rather than a hardcoded call.
- Outcome: `pm-flow compare --report <run-a> <run-b>` prints one row per
  metric in the column contract and one column per arm, then the per-arm block
  (`n_runs`, run keys and persona keys), then the limits sentence; `pm-flow
  compare <a> <b>` prints the same report over the runs it just imported, which
  is the brief's scenario 1. `cost_usd` comes from `cost.py`'s accounting;
  nothing in this section prices anything or adds a second sum of its own
  making.
- Metric definitions, settled here so the report describes something real. An
  arm is the set of runs named for it; every figure below is over that set.
  - `cost_usd` — `cost.py`'s accounting, restricted to the arm's runs:
    `cost.import_legacy(project_dir)` first, exactly as `cost.py total` does,
    then the same `SUM(COALESCE(a.cost_usd, 0))` over every status that
    `cost.stored_totals` (`cost.py:210-224`) uses. Not
    `topology_comparison.cost_usd`, which recomputes; not prices from tokens.
    Proven by reconciliation: both arms' figures sum to `cost.py total` on a
    store holding only those runs.
  - `tokens` — `SUM(COALESCE(a.total_tokens, 0))`.
  - `cycles_to_done` — the mean, over sections with a `section_status=complete`
    outcome in the arm, of that section's highest `attempts.cycle`; `-` when no
    section completed.
  - `rescue_rate` — sections with at least one `role_key='10x_developer'`
    attempt, over sections with any attempt. `do_rescue` (`driver.zsh:1903-1909`)
    is the only dispatch of that role, so a rescue always leaves an attempt.
  - `abandon_rate` — sections with a `section_status=abandoned` outcome, over
    sections with any attempt. An abandonment dispatches nothing
    (`do_abandon`, `driver.zsh:2070-2089`), so it leaves no attempt and must be
    recorded: `driver.zsh` gains a `telemetry_record_outcome` helper beside the
    other telemetry helpers, calling `telemetry.py outcome --metric
    section_status` at `do_abandon` and `do_complete`. The `outcomes` table and
    that subcommand already exist (`store.py:369-383`, `telemetry.py:753-777`)
    and nothing in the engine emits to them yet.
  - `escalation_depth` — the longest chain of `topology_edges` rows with
    `kind='escalates_to'` for the arm's topology whose every role recorded an
    attempt for one section; `0` when nothing escalated.
  - `wall_clock_s` — `SUM(r.ended_at - r.started_at)` over the arm's runs.
  - `n_runs` — the count of the arm's runs.
  - Formats, because A2 compares against a hand-computed fixture: `cost_usd`
    4 decimals, `tokens`/`escalation_depth`/`n_runs` integers,
    `cycles_to_done`/`rescue_rate`/`abandon_rate` 2 decimals or `-`,
    `wall_clock_s` 1 decimal.
- Arm copies: deleted once the arm's rows are imported, unless `--keep-copies`
  is passed; the command says which it did. This settles the retention question
  the risks section booked — with the report printed, the clone is no longer
  the only way to see the arm.
- Paths: `template/.agentic/pm_flow/compare.py`,
  `template/.agentic/pm_flow/driver.zsh` (`cmd_compare`, and the outcome
  helper with its two call sites), `template/.agentic/pm_flow/pm_flow.sh`
  (`usage` and the `--report` spelling), `tests/topology_compare_test.sh`.
- Reuse: `cost.py`'s `import_legacy` and `stored_totals` as a module, unedited;
  `topology_comparison` (`store.py:422-437`) for attempts, tokens, duration
  and status — but not for `cost_usd`; `telemetry.py outcome`
  (`telemetry.py:753-777`, `:839-844`) for the abandonment record;
  `attempts.persona_stack` for the per-arm persona keys, the field cycle 003's
  A5 assertion already reads; `catalog.py:1662-1681` (`cmd_compare`) as the
  per-run table it aggregates; `telemetry.py attempt-start|attempt-end` as the
  way a fixture seeds priced attempts (`store-ledger` handoff).
- `import_store` must additionally carry `outcomes` and the topology's
  `topology_edges`, or two of the columns above read zero in the origin store
  no matter what an arm did.
- Acceptance IDs: A2, A3, A5.
- Validation: `zsh tests/topology_compare_test.sh` — a seeded store with
  hand-computed metrics reproduces every column exactly; one run per arm
  yields the sentence stating that no difference can be inferred; deleting the
  sentence from `compare.py` fails the suite; each metric formula has its own
  mutation; the swapped persona key appears in its arm's column.
- Depends on: T2.

## Task T4 — The command outside the fixture's flow directory

- Status: done (cycle 005). A1, A2, A3, A4 met from a data-only flow directory;
  the A6 regression gate holds across all four named suites. T3's two carried
  gaps are cleared: `wall_clock_s` reads a real elapsed time in a driven compare
  and the `topology_edges` import has a mutation-tested check. One residual,
  booked in `state.md`: a `fail`/`set -e` exit after `telemetry_begin_run` still
  leaves `runs.ended_at` NULL, because closing it needs a trap outside this
  task's writable fence.
- Outcome: `pm-flow compare` runs in a repository that holds project data only,
  resolving its topology documents, domain definition and persona files from the
  engine; a driven compare's `wall_clock_s` is the elapsed time of the arm's run
  and its `n_runs` counts runs rather than dispatch subshells; and the
  `topology_edges` half of `import_store` has a check behind it.
- Three requirements, in the order they matter.

  1. **Packaged assets resolve from the engine.** Probed 2026-08-24:
     `topology.py` reads `flow/topologies/<key>.json` (`:101`, and `list` at
     `:225`), `flow/domains/<domain>.json` (`:135`), `flow/roles/<role>.md` and
     `flow/domains/<domain>/roles/<role>.md` (`:157-158`); `compare.py`'s
     `parse_persona_swaps` reads the same two persona paths (`:361-364`). None of
     those exist in an installed repository. `install.sh` lists `topologies`,
     `roles` and `domains` in `COPIED_ENGINE_DIRS` (`:72-81`), which the comment
     at `:40-46` calls the whole of what migration removes, and this repository's
     own `.agentic/pm_flow/` holds exactly `config.json`, `local_env.sh.example`,
     `pm-agent` and `projects.md`. The engine ships them instead: the wheel
     force-includes `template/.agentic/pm_flow` at `pm_flow/engine`
     (`pyproject.toml:47-51`). So each of those lookups takes the flow directory
     first and the engine root second — the precedence `catalog.py sync --flow …
     --engine …` already uses (`compare.py:328-332`), and the same rule
     `pm_flow.sh:558-559` applies to `roles` and `domains` for the shell engine.
     `topology.py`'s CLI gains `--engine`, defaulting to
     `Path(__file__).resolve().parent`; `validate`, `overlay` and `list` all
     honour it, and `list` unions both directories with the flow's copy winning
     by stem. Refusals keep naming the flow path and add the engine path, so
     T1's A4 assertion on `$FLOW/topologies/missing.json` stays green and still
     says where else the command looked.
  2. **A run is one invocation.** `telemetry_end_run` (`driver.zsh:752`) has no
     call site, so `runs.ended_at` stays NULL and `wall_clock_s` reads `0.0`.
     Calling it at the end of `cmd_run` is not enough on its own:
     `TELEMETRY_RUN_KEY` is set lazily by `telemetry_begin_attempt` (`:792`)
     inside the dispatch subshell `perform_action` opens deliberately (`:2642`),
     so the parent never sees it and each dispatching action opens a run of its
     own. That is why the fixture has to make the project finish in one PM
     dispatch to get one run per arm (`tests/topology_compare_test.sh:215-216`),
     and why a real project would report its dispatch count as the arm size in
     the limits sentence. Open the run in the parent instead: call
     `telemetry_begin_run` in `cmd_run` and `cmd_tick` once the lock is taken,
     and `telemetry_end_run ok|error` on the way out of each. A subshell inherits
     the variable, so the lazy call at `:792` becomes a no-op, every attempt of
     the invocation lands on one run, `n_runs` counts invocations and
     `wall_clock_s` measures them — which is what the report already claims.
  3. **The edge import gets its check.** `import_store` carries
     `topology_edges` and nothing observes it: the report fixture syncs its own
     topologies into its own store, and the driven compare's
     `escalation_depth` is not asserted at all. With `--keep-copies` the arm
     store survives, so assert the arm topology's edge set in the origin store
     equals the arm store's and is non-empty.
- Paths: `template/.agentic/pm_flow/topology.py`,
  `template/.agentic/pm_flow/compare.py`,
  `template/.agentic/pm_flow/driver.zsh` (the `cmd_run` and `cmd_tick` call
  sites only), `tests/topology_compare_test.sh`. No new engine file, so
  `install.sh` needs no entry. `cost.py` belongs to T5.
- Reuse: the `PM_FLOW_ENGINE_ROOT` idiom for a data-only repository
  (`tests/store_ledger_test.sh:326-329`, `tests/packaged_layout_test.sh:79-85`);
  this suite's own `install_driver_stub` (`:159-182`) and its
  `init-section`-plus-`COMPLETE`-decision fixture (`:184-219`).
- Acceptance IDs: A1, A2, A3, A4, plus the A6 regression gate.
- Validation: `zsh tests/topology_compare_test.sh` — a second work tree whose
  flow directory holds project data only drives `compare lean heavy` to a
  printed table and limits sentence; both arms' `wall_clock_s` columns are
  greater than zero and both imported runs have a non-NULL `ended_at`; an arm
  with two dispatching sections still reports `n_runs` 1; `compare heavy
  missing` there still refuses before dispatch, naming both searched paths; the
  arm topology's edge rows match between the retained arm store and the origin.
  `zsh tests/pm_flow_test.sh`, `zsh tests/packaged_layout_test.sh`,
  `zsh tests/store_ledger_test.sh` and `zsh tests/trace_commands_test.sh` exit 0
  — the last two because the run's scope changes what the store records.
- Depends on: T3.

## Task T5 — Scenarios 1-3 through the installed wheel

- Status: pending.
- Outcome: the brief's three user-visible scenarios driven through a `pm-flow`
  entry point installed from a built wheel, in a repository that holds project
  data only: `compare lean heavy --max-ticks 6` prints the table, the arm sizes
  and the limits sentence; `compare heavy missing` exits non-zero before any
  dispatch; `pm-flow cost` afterwards shows attempts from both arms, each
  carrying its topology key.
- Scenario 3 needs one field that does not exist. `cost.py` knows nothing about
  topologies (probed 2026-08-24: no match for `topology` in the file), and its
  `ATTEMPT` line is
  `ATTEMPT\t<started_at>\t<section>\t<role>\t<label>\t<cli>\t<cost>\t<in>\t<out>`
  (`cost.py:251-262`). Append one trailing field, the attempt's run topology key
  through `runs.topology_id → topologies.key`, `-` when a run has none. This is
  presentation only: `stored_totals`, `import_legacy` and every sum stay
  untouched, so it is not a second accounting. Every existing consumer reads
  positional fields 1-7 or a `grep -F` substring
  (`store_ledger_test.sh:173-176`, `:311`, `:397`, `:407`, `:417-419`;
  `agent_bindings_test.sh:367-370`), so a trailing field breaks none of them —
  which `zsh tests/store_ledger_test.sh` must prove. `cost.py` is `store-ledger`'s
  file and that section has handed off, so this edit is named in the handoff.
- Paths: `template/.agentic/pm_flow/cost.py` (the report join only),
  `tests/topology_compare_test.sh`.
- Reuse: `tests/packaged_layout_test.sh`'s wheel-and-venv harness (`:99-244`,
  `install_pinned_venv` at `:1158-1171`) for a real `<venv>/bin/pm-flow`; the
  stub-CLI harness for the arms.
- Acceptance IDs: A1-A6.
- Validation: `zsh tests/topology_compare_test.sh` drives all three scenarios
  through the venv entry point and asserts the printed report, the refusal, and
  `pm-flow cost` output carrying both arms' topology keys with the total
  unchanged; `zsh tests/pm_flow_test.sh`, `zsh tests/packaged_layout_test.sh`
  and `zsh tests/store_ledger_test.sh` exit 0.
- Depends on: T4.

## Integration and end-to-end validation

- T5 is the gate. T2 is the first point at which the brief's headline
  sentence — the same project run under two named designs — is observable, and
  T4 is the first at which it is observable outside a flow directory that
  happens to hold a copy of the engine.

## Risks and rollback

- Small samples invite false claims; the limits sentence is an acceptance
  requirement, mutation-tested at T3.
- The `topology_comparison` view already sums `attempts.cost_usd`. Reading
  cost from it would be the second accounting the brief rejects, so T3 reads
  `cost.py`.
- Existing suites bind stub models (`gpt-stub`, `fixture-model`). The model
  check therefore applies to topology documents only, never to `config.json`,
  or `pm_flow_test.sh` and `packaged_layout_test.sh` break.
- Every new file under `template/.agentic/pm_flow/` must be added to
  `install.sh`'s `COPIED_ENGINE_FILES` or `COPIED_ENGINE_DIRS` in the same
  cycle. Those lists are, by the comment at `install.sh:40-46`, the whole of
  what migration removes from a copied install, so an unlisted engine file
  survives migration and turns `packaged_layout_test.sh:1020` red. Observed in
  cycle 001 for `topology.py` and `topologies`; `compare.py` repeats it at T2.
- Arm copies were never deleted: `copy_checkout` uses `tempfile.mkdtemp` and
  nothing removed it, so each real compare left two full clones of the
  repository under `$TMPDIR`. Settled at T3: removed once the arm's rows are
  imported, kept only under `--keep-copies`, and the command says which.
- Every fixture so far copies the whole engine into the flow directory
  (`tests/topology_compare_test.sh:44`), which is the layout install.sh stopped
  writing. That is why nothing caught `topology.py` resolving documents,
  domains and personas from the flow directory alone. T4's fixture holds project
  data only; T5's is a built wheel. Any future check added to this suite should
  go in the data-only tree unless it is specifically about the copied layout.
- Opening the run in `cmd_run`/`cmd_tick` changes what a `runs` row means:
  one invocation rather than one dispatch subshell, and an invocation that
  dispatches nothing now records a run. That is the point — the limits sentence
  states arm sizes — but it moves rows other suites may count, so T4 runs
  `store_ledger_test.sh` and `trace_commands_test.sh` as well as the A6 three.
- Rollback removes the `compare` case, `compare.py` and `topology.py`; stored
  runs stay, since nothing about them is new.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1 | T2, T4, T5 | Runs under both keys, one project key |
| A2 | T3, T4, T5 | Every column equals the hand-computed fixture; `wall_clock_s` non-zero when driven |
| A3 | T3, T4, T5 | Limits sentence present; its removal fails; arm size counts runs |
| A4 | T1, T4, T5 | Refusal before dispatch; no new attempt row; both searched paths named |
| A5 | T2, T3 | Persona key per arm, in the store and the column |
| A6 | T4, T5 | The three named suites exit 0, plus `store_ledger_test.sh` |
