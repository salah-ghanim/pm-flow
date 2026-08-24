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
  stdout), `list --flow <dir>`.
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

## Task T4 — End to end through the installed command

- Status: pending.
- Outcome: scenarios 1-3 driven through `.venv/bin/pm-flow`, including
  `pm-flow cost` after a compare showing attempts from both arms with their
  topology keys.
- Carried from T3, both to be closed here:
  - `wall_clock_s` is inert in the shipped command. `telemetry_end_run`
    (`driver.zsh:752`) is defined and never called, so a run's `ended_at` stays
    NULL and the column reads `0.0` after every real compare — observed
    2026-08-24 on the origin store after `compare lean heavy --max-ticks 5`:
    both imported runs read `status=running`, `ended_at` empty. That is the
    same defect class T3 cleared for `abandon_rate`, and it hits the brief's
    "how long each took" directly. Call `telemetry_end_run` where a run
    finishes, then assert a non-zero `wall_clock_s` from a driven compare, not
    only from the seeded fixture.
  - `import_store`'s `topology_edges` half is unchecked. The report fixture
    syncs its own topologies into its own store, so `escalation_depth` is
    asserted on rows that never crossed the importer. Assert `escalation_depth`
    (or the edge rows) on the imported arms, so disabling the edge import turns
    the suite red.
- Paths: `tests/topology_compare_test.sh`,
  `template/.agentic/pm_flow/driver.zsh` (the `telemetry_end_run` call site).
- Reuse: the installed-layout harness in `tests/packaged_layout_test.sh`.
- Acceptance IDs: A1-A6.
- Validation: `zsh tests/topology_compare_test.sh`,
  `zsh tests/pm_flow_test.sh` and `zsh tests/packaged_layout_test.sh` exit 0.
- Depends on: T3.

## Integration and end-to-end validation

- T4 is the gate. T2 is the first point at which the brief's headline
  sentence — the same project run under two named designs — is observable.

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
- Rollback removes the `compare` case, `compare.py` and `topology.py`; stored
  runs stay, since nothing about them is new.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1 | T2, T4 | Runs under both keys, one project key |
| A2 | T3, T4 | Every column equals the hand-computed fixture |
| A3 | T3, T4 | Limits sentence present; its removal fails |
| A4 | T1 | Refusal before dispatch; no new attempt row |
| A5 | T2, T3 | Persona key per arm, in the store and the column |
| A6 | T4 | Three suites exit 0 |
