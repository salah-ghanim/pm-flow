# codex-usage section PM state

## Current task

- T3 — turn the cycle-005 real-stream probe into a tracked public-`tick`
  regression test. Do not spend another cycle trying to nest authenticated
  Codex inside the reviewer sandbox.

## Completed tasks and evidence

- T1 / A3–A5: cycles 001–002; adjacent JSONL, event liveness, stderr-only
  classification, trace propagation, and quiet supervisor output are on main.
- T2 / A1, A3, A6: cycles 004–005; lifecycle wiring and the schema correction
  stored tokens matching a real `turn.completed.usage`. Lifecycle-removal and
  schema-regression mutations produced no completed attempt. Full suite passed.

## Active decisions

- Deterministic replay and the authenticated canary are separate gates. Replay
  is tracked; the canary runs at host level with real credentials.
- `store-ledger` owns cost presentation. This section supplies complete attempt
  data and later verifies that downstream output, but does not edit `cost.py`.
- JSONL is never mixed into stderr or the response envelope.

## Blockers

- T4 cannot run inside the nested review sandbox: the in-process Codex app
  server is denied before emitting events. It is not a blocker for T3.
- T5 waits for store-ledger.

## Next eligible task

- T3. Its acceptance command is `zsh tests/codex_usage_test.sh`; the test must
  fail when lifecycle calls are removed or real usage fields are misread.
