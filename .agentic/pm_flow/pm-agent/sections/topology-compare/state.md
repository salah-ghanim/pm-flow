# topology-compare section PM state

## Current task

- T1 — define immutable topology documents and pre-dispatch availability checks.

## Completed tasks and evidence

- None. Existing catalog topology records are reuse targets, not completed
  comparison behavior.

## Active decisions

- Topology definitions never mutate shared `config.json`.
- Every run persists a stable topology identity.
- Compare reads store-ledger metrics and always prints arm size/inference limits.
- `src/pm_flow/cli.py` ownership is transferred from completed packaging.

## Blockers

- None for T1 or T2. T3 awaits store-ledger's query contract.

## Next eligible task

- T1 with immutable-definition, unavailable-model/binding, and
  no-attempt-before-validation tests.
