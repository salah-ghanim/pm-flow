## Outcome

Codex JSONL capture, event liveness, stderr isolation, trace propagation, and
attempt lifecycle storage are implemented on main. A developer host run stored
tokens exactly matching a real Codex `turn.completed.usage`; the reviewer could
not reproduce the authenticated call because nested Codex initialization was
sandbox-denied before any event was emitted.

## Decisions

- Preserve deterministic replay and a separate host-level authenticated canary.
- Keep cost presentation in store-ledger; codex-usage owns the stored data.
- Do not copy credentials or loosen the scoped sandbox to make a nested canary
  pass.

## Interfaces

- `<response>.events.jsonl` contains Codex events; stderr alone is the attempt
  log and failure-classifier input.
- `TRACEPARENT` reaches the child. Completed `attempts` rows contain backend,
  model, response path, status, and token columns.

## Risks

- Codex CLI/event schema drift is detected only when both tracked replay and the
  host canary are kept current.
- The cycle-005 probe is not yet a tracked regression test.

## What is unproven

- A reviewer-independent authenticated host canary after the current code.
- User-visible cost output from store-ledger for the completed Codex attempt.

## Next action

Implement workplan T3 as a tracked public-`tick` replay test, then run T4 on a
host that permits authenticated Codex and T5 after store-ledger lands.
