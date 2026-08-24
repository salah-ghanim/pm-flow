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

- Status: pending.
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
- Reuse: the stub-CLI harness in `tests/pm_flow_test.sh`; `cmd_cost`
  (`driver.zsh:466`) as the shape of a Python-backed command;
  `catalog.py sync --topology` for registering each arm's seats;
  `catalog.py persona swap --topology` for the swapped seat.
- Acceptance IDs: A1, A5.
- Validation: `zsh tests/topology_compare_test.sh` — after a compare of two
  arms with a persona swapped on one seat of one arm, `runs` holds rows under
  both topology keys with one `projects.key`; each arm's attempts carry that
  arm's persona key; the two arms' working copies are distinct paths; and a
  mutation that points both arms at one checkout fails the suite.
- Depends on: T1.

## Task T3 — The report and its limits

- Status: pending.
- Outcome: `pm-flow compare --report <run-a> <run-b>` prints one row per
  metric in the column contract and one column per arm, then the arm sizes,
  then the limits sentence. `cost_usd` is read from `cost.py total`; nothing
  in this section adds arithmetic over `attempts.cost_usd`.
- Paths: `template/.agentic/pm_flow/compare.py`,
  `tests/topology_compare_test.sh`.
- Reuse: `cost.py total <dir> [section]` for cost;
  `topology_comparison` (`store.py:422-437`) for attempts, tokens, duration
  and status — but not for `cost_usd`, which that view recomputes;
  `catalog.py:1662-1681` (`cmd_compare`) as the per-run table it aggregates.
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
- Paths: `tests/topology_compare_test.sh`.
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
