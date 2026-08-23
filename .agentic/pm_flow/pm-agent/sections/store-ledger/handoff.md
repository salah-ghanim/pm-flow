# store-ledger section handoff

## Outcome

Rebaselined into legacy import, store-backed cost, shared watch summaries, and
migration closeout. No implementation exists; T1 is immediately assignable.

## Decisions

- Store attempts are the sole runtime accounting source after one-time import.
- Cost and watch share a query contract; neither parses Codex events.
- The previous trace-commands dependency was false and is removed.

## Interfaces

- Planned: idempotent importer and store-backed reporting in `cost.py`, reused by
  `watch.py`.

## Risks

- Mixed TSV/envelope history can double-charge without deterministic identity.
  Import must be transactional and idempotent.

## What is unproven

- All A1–A4 outcomes; nothing has been implemented.

## Next action

Scope workplan T1.
