# store-ledger section PM state

## Current task

- T1 — implement deterministic, idempotent legacy TSV import into the store.

## Completed tasks and evidence

- None in this section. The attempts/store schema already exists and is reused.

## Active decisions

- SQLite attempts are the only runtime accounting source after import.
- Cost and watch consume the same query contract.
- Codex JSONL is parsed by codex-usage; this section reads completed attempts.
- Import never sums TSV and an already represented attempt twice.

## Blockers

- None. The previous trace-commands dependency was a false sequencing edge and
  is removed in this rebaseline.

## Next eligible task

- T1 with golden totals, TSV-only, mixed-source dedupe, idempotence, and a
  duplicate-detection mutation.
