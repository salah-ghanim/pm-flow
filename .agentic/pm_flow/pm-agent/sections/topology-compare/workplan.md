# topology-compare workplan

## Design summary

- Topologies are JSON documents validated against the configured CLIs. A
  compare run copies the checkout per arm, drives each with
  `PM_FLOW_TOPOLOGY=<key>` and the arm's overlay, imports each arm's store
  rows back under its key, and prints a descriptive table from
  `store-ledger`'s totals with a mandatory limits sentence.

## Interfaces and data changes

- `topologies/<key>.json`; `pm-flow compare`; report column contract. No
  schema change: `runs.topology` exists.

## Task T1 — Topology documents and validation

- Status: pending.
- Outcome: `topology.py` loads `topologies/<key>.json`, validates role
  bindings and seat counts against `config.json`'s CLIs and their model
  lists, and refuses a missing document or unreachable model before
  dispatch.
- Paths: `src/pm_flow/topology.py`, `template/.agentic/pm_flow/topologies/**`,
  `tests/topology_compare_test.sh`.
- Reuse: `catalog.py` topology and binding records; `config.json` role shape.
- Acceptance IDs: A4.
- Validation: `zsh tests/topology_compare_test.sh` — valid `lean` and `heavy`
  load; missing key and unknown model are refused with the name; the store
  holds no attempt after a refusal.
- Depends on: None.

## Task T2 — Run two arms from one commit

- Status: pending.
- Outcome: `pm-flow compare a b --max-ticks n` copies the checkout per arm,
  runs each under its topology key, imports rows back, and the store shows
  runs under both keys.
- Paths: `src/pm_flow/compare.py`, `src/pm_flow/cli.py`,
  `tests/topology_compare_test.sh`.
- Reuse: the stub harness from `tests/pm_flow_test.sh`; `PM_FLOW_TOPOLOGY`.
- Acceptance IDs: A1, A5.
- Validation: `zsh tests/topology_compare_test.sh` — two arms with a swapped
  persona on one seat; `runs` shows both keys; each arm's attempts carry its
  persona key; a mutation running both arms in one checkout fails.
- Depends on: T1.

## Task T3 — The report and its limits

- Status: pending.
- Outcome: `pm-flow compare --report` prints the column contract from the
  store via `cost.py` totals and the run/escalation records, with `n_runs`
  and the limits sentence.
- Paths: `src/pm_flow/compare.py`, `tests/topology_compare_test.sh`.
- Reuse: `store-ledger`'s `cost.py total`; escalation directories for depth.
- Acceptance IDs: A2, A3, A5.
- Validation: `zsh tests/topology_compare_test.sh` — a seeded store with
  hand-computed metrics matches the table exactly; one run per arm yields the
  no-inference sentence; removing the sentence fails; each metric formula has
  a mutation.
- Depends on: T2, store-ledger done.

## Task T4 — End to end through the installed command

- Status: pending.
- Outcome: scenarios 1–3 through `.venv/bin/pm-flow`.
- Paths: `tests/topology_compare_test.sh`.
- Reuse: the harness in `tests/packaged_layout_test.sh`.
- Acceptance IDs: A1–A6.
- Validation: `zsh tests/topology_compare_test.sh`, `zsh tests/pm_flow_test.sh`,
  `zsh tests/packaged_layout_test.sh` exit 0.
- Depends on: T3.

## Integration and end-to-end validation

- T4 is the gate; T2 is the first point at which the headline sentence is
  observable.

## Risks and rollback

- Small samples invite false claims; the limits sentence is an acceptance
  requirement. Rollback removes the `compare` command; stored runs stay.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1 | T2, T4 | Runs under both keys |
| A2, A3 | T3, T4 | Table equals fixture; limits sentence present |
| A4 | T1 | Refusal before dispatch |
| A5 | T2, T3 | Persona key per arm |
| A6 | T4 | Three suites exit 0 |
