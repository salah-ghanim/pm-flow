# topology-compare section handoff

## Outcome

Rebaselined into immutable definitions, persisted run identity, store-backed
metrics, inference limits, and installed-command E2E. No implementation exists.

## Decisions

- Topology definitions do not edit shared config.
- Compare consumes store-ledger metrics and always states sample limitations.
- Unavailable bindings/models fail before any dispatch.

## Interfaces

- Planned: `topology.py`, `compare.py`, and `pm-flow compare` CLI registration.

## Risks

- CLI ownership is transferred from completed packaging. T3 still waits for
  store-ledger's query contract.

## What is unproven

- All A1–A5 outcomes; nothing has been implemented.

## Next action

Scope workplan T1.
