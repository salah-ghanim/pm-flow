# topology-compare workplan

## Design summary

- Store immutable named topology definitions outside shared `config.json`.
  Each run records its topology identity. A compare command queries store-backed
  outcome metrics for two arms and always reports sample-size limitations.

## Interfaces and data changes

- `topology.py` validates/loads definitions and checks binding availability.
- `compare.py` queries cost, tokens, cycles, rescue, abandonment, and escalation.
- `pm-flow compare <a> <b>` is registered through the Python CLI.

## Task T1 — Define immutable topology documents

- Status: pending.
- Outcome: two topologies are created/validated independently, never mutate
  shared config, and fail before dispatch when a binding/model is unavailable.
- Paths: `src/pm_flow/topology.py`,
  `template/.agentic/pm_flow/topologies/**`, `tests/topology_compare_test.sh`.
- Reuse: catalog topology/seat/binding records and availability checks.
- Acceptance IDs: A1, A5.
- Validation: valid/invalid definitions, content identity, two simultaneous
  definitions, unavailable binding/model, and no-attempt-before-failure check.
- Depends on: None.

## Task T2 — Run and persist topology identity

- Status: pending; `src/pm_flow/cli.py` ownership transferred in the rebaseline.
- Outcome: the same project runs under topology A and B; attempts/runs remain
  distinguishable by stable topology identity.
- Paths: `topology.py`, `tests/topology_compare_test.sh`, and `src/pm_flow/cli.py`.
- Reuse: existing topology tables, CLI delegation, run/attempt lifecycle.
- Acceptance IDs: A1, A2, A5.
- Validation: two installed-command runs, immutable definitions, store joins,
  and mutation dropping topology identity.
- Depends on: T1.

## Task T3 — Compute the comparison table from the store

- Status: waiting on store-ledger's query contract.
- Outcome: one command reports cost, tokens, cycles-to-done, rescue rate,
  abandonment rate, and escalation depth for both topologies.
- Paths: `src/pm_flow/compare.py`, `tests/topology_compare_test.sh`, transferred
  CLI registration path.
- Reuse: store-ledger totals and existing run/escalation records; no TSV reader.
- Acceptance IDs: A3.
- Validation: seeded hand-computed dataset, missing/failed runs, exact table
  assertions, and mutation of each metric formula.
- Depends on: T2, store-ledger.

## Task T4 — State inference limits in every output

- Status: pending.
- Outcome: comparison output includes arm sizes, descriptive differences, and a
  plain statement of what the sample can/cannot support; empty/one-run arms do
  not imply superiority.
- Paths: `src/pm_flow/compare.py`, `tests/topology_compare_test.sh`.
- Reuse: T3 aggregate counts; no invented significance test.
- Acceptance IDs: A4.
- Validation: zero/one/many-run snapshots and mutation removing the limitation
  text or sample size.
- Depends on: T3.

## Task T5 — Installed-command E2E closeout

- Status: pending.
- Outcome: define two topologies, run both, compare them through installed
  `pm-flow`, and retain distinguishable store rows; full suite passes.
- Paths: all owned topology/compare paths plus approved CLI path.
- Reuse: packaged-layout harness and T1–T4 fixtures.
- Acceptance IDs: A1–A5.
- Validation: `zsh tests/topology_compare_test.sh`, installed artifact E2E,
  metric/topology-identity mutations, and full suite.
- Depends on: T4.

## Integration and end-to-end validation

- T1 is next. CLI ownership is now transferred from completed packaging. T3
  consumes the store-ledger contract; it must not create its own accounting layer.

## Risks and rollback

- Small samples invite false claims. Output limitation text is an acceptance
  requirement. Roll back compare presentation without altering stored runs.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1 | T1, T2, T5 | Independent immutable definitions and runs |
| A2 | T2, T5 | Store distinguishes both topology arms |
| A3 | T3, T5 | Complete store-backed metric table |
| A4 | T4, T5 | Sample size and inference limit in output |
| A5 | T1, T2 | Unavailable binding/model fails before dispatch |
