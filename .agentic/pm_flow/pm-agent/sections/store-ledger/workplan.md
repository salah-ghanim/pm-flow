# store-ledger workplan

## Design summary

- Make SQLite attempts the sole runtime accounting source. Import legacy TSV
  rows once with deterministic identity/deduplication, then make cost and watch
  views query the store. Never read both sources into one total.

## Interfaces and data changes

- `cost.py` imports legacy ledger data when required and reports store-backed
  totals by run/role/binding/model.
- `watch.py` reads the same store views for live summaries.

## Task T1 — Specify and implement idempotent legacy import

- Status: pending.
- Outcome: a TSV-only project imports to the existing store exactly once;
  records already represented by envelopes/attempts are not counted twice.
- Paths: `template/.agentic/pm_flow/cost.py`.
- Reuse: existing store schema, response-envelope identifiers, and money/token
  normalization.
- Acceptance IDs: A1, A3.
- Validation: golden TSV totals to the cent, TSV-only import, mixed TSV/envelope
  deduplication, second-run idempotence, and duplicate-key mutation.
- Depends on: None.

## Task T2 — Read cost and token totals from the store

- Status: pending.
- Outcome: `pm_flow.sh cost` reports stored attempts, including non-zero Codex
  tokens, and budget checks see prior spend.
- Paths: `template/.agentic/pm_flow/cost.py`.
- Reuse: existing `attempts` token/cost/status fields; no JSONL parsing here.
- Acceptance IDs: A1, A2, A3.
- Validation: compare legacy golden totals, Claude/Codex attempt rows, filters,
  failed attempts, and budget threshold behavior.
- Depends on: T1; codex-usage provides a completed Codex row for integration.

## Task T3 — Move watch summaries to the same source

- Status: pending.
- Outcome: `watch.py` and `cost` agree for the same run while watch preserves
  current liveness/progress behavior.
- Paths: `template/.agentic/pm_flow/watch.py`.
- Reuse: T2 query/result contract rather than a second accounting query.
- Acceptance IDs: A2.
- Validation: seeded live/completed runs, exact totals agreement, update refresh,
  and mutation that reintroduces TSV reads.
- Depends on: T2.

## Task T4 — Migration and full regression closeout

- Status: pending.
- Outcome: TSV-only, store-only, and mixed projects all report correct totals;
  budget enforcement never resets spend; the full suite passes.
- Paths: `cost.py`, `watch.py`.
- Reuse: packaging's migration fixture and T1–T3 focused cases.
- Acceptance IDs: A1–A4.
- Validation: `cost`/watch integration, double-count and zero-budget mutations,
  packaged legacy migration, and full suite.
- Depends on: T3.

## Integration and end-to-end validation

- Cost reporting and budget enforcement must consume the identical store-backed
  total. Codex usage is a consumer scenario, not a reason to parse events here.

## Risks and rollback

- Import ambiguity can overcharge. Keep import transactional/idempotent and
  retain the TSV as source evidence; rollback readers without deleting rows.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1 | T1, T2, T4 | Golden totals equal to the cent |
| A2 | T2, T3 | Cost and watch read identical store totals |
| A3 | T1, T4 | TSV-only project imports and reports correctly |
| A4 | T4 | Mutations and full suite pass |
