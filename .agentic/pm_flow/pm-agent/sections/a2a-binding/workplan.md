# a2a-binding workplan

## Design summary

- Extend the binding interface from agent-bindings with an HTTP A2A adapter.
  Keep inbound remote-seat dispatch separate from outbound pm-flow-as-agent
  serving, while sharing one task-state mapping and Agent Card implementation.

## Interfaces and data changes

- `a2a.py` owns Agent Card discovery, authenticated HTTP transport, A2A task
  lifecycle, artifact/result mapping, cancellation, and input-required turns.
- Store metadata distinguishes A2A from local CLI and ACP transports.

## Task T1 — Pin the A2A contract and state mapping

- Status: pending.
- Outcome: one module defines supported protocol revision, Agent Card fields,
  pm-flow↔A2A state mapping, error mapping, and access capability declaration.
- Paths: `src/pm_flow/a2a.py`, `tests/a2a_binding_test.sh`.
- Reuse: agent-bindings binding result and access-capability interfaces.
- Acceptance IDs: A4, A5.
- Validation: table tests cover every local/remote terminal state,
  `input-required`, cancellation, unsupported auth, and unenforceable access.
- Depends on: agent-bindings T1/T3 interfaces.

## Task T2 — Dispatch a seat to a remote A2A agent

- Status: pending.
- Outcome: a remote Agent Card is discovered and one seat completes a normal
  section cycle through A2A, with transport and binding persisted.
- Paths: `src/pm_flow/a2a.py`, `tests/a2a_binding_test.sh`; dispatch integration
  paths require ownership transfer after agent-bindings completes.
- Reuse: T1 mapping, existing assignment/review envelopes, attempt lifecycle.
- Acceptance IDs: A1, A2, A5, A6.
- Validation: protocol-faithful local HTTP server, access preflight, cycle E2E,
  store assertions, existing binding regressions, and timeout/cancel mutations.
- Depends on: T1 and agent-bindings completion.

## Task T3 — Serve pm-flow as an A2A agent

- Status: pending.
- Outcome: a third-party client discovers pm-flow from its Agent Card, submits a
  task, observes progress, answers `input-required`, and reaches a terminal state.
- Paths: `src/pm_flow/a2a.py`, `tests/a2a_binding_test.sh`; console/server
  registration path must be transferred before assignment.
- Reuse: installed CLI command semantics and the existing project state machine.
- Acceptance IDs: A3, A4.
- Validation: use an independent A2A client implementation or conformance tool;
  no repository knowledge or shell invocation is allowed in the client.
- Depends on: T1.

## Task T4 — Authentication and full regression closeout

- Status: pending.
- Outcome: inbound/outbound authentication failures are explicit, secrets are
  not persisted, all local bindings remain unchanged, and the full suite passes.
- Paths: `src/pm_flow/a2a.py`, `tests/a2a_binding_test.sh` plus approved
  integration paths.
- Reuse: existing secret/config handling and access observation.
- Acceptance IDs: A1–A7.
- Validation: authenticated E2E, wrong/missing credential cases, input-required
  round trip, full binding regression, and full suite.
- Depends on: T2, T3.

## Integration and end-to-end validation

- Keep inbound and outbound scenarios separate in tests so one cannot fake the
  other. At least one side of the E2E must use an independent implementation.

## Risks and rollback

- Protocol/security drift is isolated in `a2a.py`. Disable the A2A binding and
  server independently; local bindings remain the rollback path.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1, A2 | T2, T4 | Remote-seat cycle and distinguishable store record |
| A3, A4 | T3, T4 | Third-party client and input-required round trip |
| A5 | T1, T2 | Access caveat before dispatch |
| A6 | T2, T4 | CLI and ACP regressions unchanged |
| A7 | T4 | Full suite completes |
