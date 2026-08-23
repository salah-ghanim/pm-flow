## Objective

- The same project runs under two named agent team designs and one command
  reports what each cost, where each escalated, and how long each took, with
  its inference limits stated.

## Current baseline

- A run is dispatched under a topology key: `PM_FLOW_TOPOLOGY`, else
  `telemetry.topology` in `config.json`, else `default`; `runs`, `attempts`
  and `spans` carry it.
- `config.json` `roles` binds each role to a CLI, model and difficulty;
  `consultant` is already a list of seats.
- No topology is a named document, nothing runs a project twice, and nothing
  puts two records side by side.

## Deliverables

- Topology documents under `template/.agentic/pm_flow/topologies/<key>.json`:
  role bindings and seat counts only, validated before dispatch.
- `pm-flow compare <topology-a> <topology-b> [--max-ticks n]`: runs the
  project from the same starting commit under each, in disposable copies,
  then prints the comparison.
- `pm-flow compare --report <run-a> <run-b>`: the table for two finished runs.
- `tests/topology_compare_test.sh`.

## User-visible scenarios

1. Two files, `topologies/lean.json` and `topologies/heavy.json`, differ in
   the developer model and the consultant seat count; `pm-flow compare lean
   heavy --max-ticks 6` runs both and prints one table with a row per metric
   and a column per arm, followed by the arm sizes and the limits sentence.
2. `pm-flow compare heavy missing` exits non-zero before any dispatch, naming
   the absent topology; so does a topology naming a model the configured CLI
   cannot reach.
3. `pm-flow cost` after a compare shows attempts from both arms, each with its
   topology key.

## Interfaces produced

- Topology document schema; `pm-flow compare`; the report's column contract
  (`cost_usd`, `tokens`, `cycles_to_done`, `rescue_rate`, `abandon_rate`,
  `escalation_depth`, `wall_clock_s`, `n_runs`).

## Interfaces consumed

- `runs`, `attempts` and their topology keys; `store-ledger`'s cost totals;
  `PM_FLOW_TOPOLOGY`.

## Scope

- In: topology documents and validation, running both arms, the report, the
  limits statement, tests.
- Out: statistical testing; persona identity in the report (`persona-cards`
  A3 consumes the report's per-arm persona fields); editing `config.json`.

## Non-goals

- Claiming a winner. The report describes; it does not infer.
- Running arms concurrently in the same checkout.

## Priority

- must-have: this is the plan's headline sentence.

## Owned paths

- `src/pm_flow/topology.py`
- `src/pm_flow/compare.py`
- `src/pm_flow/cli.py`
- `template/.agentic/pm_flow/topologies/**`
- `tests/topology_compare_test.sh`

## Dependencies

- store-ledger

## Constraints and fixed decisions

- A topology document never mutates shared `config.json`; the driver is
  pointed at it through `PM_FLOW_TOPOLOGY` and an overlay the document
  supplies.
- Each arm runs in its own disposable copy of the repository from the same
  starting commit; the store rows it produces are imported back under the
  arm's topology key.
- Cost figures come from `store-ledger`'s `cost.py`; no second accounting.

## Acceptance

- A1: `pm-flow compare a b` on a stub project in the test runs both arms and
  the store holds runs under both topology keys with the same project key.
- A2: `pm-flow compare --report` prints every metric in the column contract
  for both arms with values equal to a hand-computed fixture, plus `n_runs`
  per arm.
- A3: The report ends with the limits sentence naming the arm sizes; with one
  run per arm it states that no difference can be inferred, and a mutation
  removing the sentence fails the test.
- A4: A missing topology, or one naming a model the bound CLI does not list,
  fails before any dispatch: the store holds no new attempt.
- A5: A persona swapped on one seat in one arm appears in that arm's report
  column by persona key.
- A6: `zsh tests/topology_compare_test.sh`, `zsh tests/pm_flow_test.sh` and
  `zsh tests/packaged_layout_test.sh` exit 0.

## Rejection conditions

- A comparison that implies superiority without the limits sentence.
- A topology definition that edits `config.json` in place.
- Two arms run in one checkout at once.
- A second cost calculation.

## Open questions

- None.
