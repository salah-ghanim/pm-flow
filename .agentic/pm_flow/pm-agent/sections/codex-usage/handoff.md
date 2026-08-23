# codex-usage section handoff

## Outcome

- Engine work on `main`: Codex event capture, event-only liveness,
  stderr-only classification, attempt lifecycle, real `turn.completed` usage
  stored on `attempts`. Not yet complete: the tracked replay test (T3).

## Decisions

- Deterministic replay of a captured real stream is the regression gate; a
  live Codex developer dispatch is the A1 evidence.
- Cost presentation belongs to store-ledger.

## Interfaces

- `<response>.events.jsonl` beside every Codex response; stderr alone is the
  attempt log.
- `attempts` token columns for Codex dispatches.

## Risks

- Codex event-schema drift would pass replay and fail live; the reviewer's A1
  probe on a live dispatch is the detector.

## What is unproven

- A tracked regression test; the proof so far is an untracked probe.

## Next action

- Assign T3.
