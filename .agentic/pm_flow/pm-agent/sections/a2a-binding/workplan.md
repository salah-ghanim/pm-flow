# a2a-binding workplan

## Design summary

- One module holds the pinned protocol revision, the lifecycle mapping and
  both directions of transport. Inbound reuses the `agent-bindings` interface;
  outbound is a small authenticated HTTP server over the installed command.

## Interfaces and data changes

- Binding `cli: a2a`, `cli_params.card`; served Agent Card and task endpoints.
  No schema change.

## Task T1 — Pin the revision and the lifecycle mapping

- Status: pending.
- Outcome: `a2a.py` declares the pinned revision, the Agent Card fields pm-flow
  serves, the state and error mappings, and the access-capability check.
- Paths: `src/pm_flow/a2a.py`, `tests/a2a_binding_test.sh`.
- Reuse: `agent-bindings`' result and access interfaces.
- Acceptance IDs: A5.
- Validation: `zsh tests/a2a_binding_test.sh` — table tests over every
  pm-flow↔A2A state pair, `input-required`, cancellation, unsupported auth
  scheme, and an agent that cannot honour the tier.
- Depends on: agent-bindings done.

## Task T2 — Inbound: a seat on a remote agent

- Status: pending.
- Outcome: a remote Agent Card is discovered, one seat completes a turn through
  the ordinary path, and the attempt is stored with `cli=a2a`.
- Paths: `src/pm_flow/a2a.py`, `tests/a2a_binding_test.sh`.
- Reuse: T1; the `agent-bindings` arm interface; a protocol-faithful local
  HTTP test agent shipped in the test.
- Acceptance IDs: A1, A2, A5, A6.
- Validation: `zsh tests/a2a_binding_test.sh` — turn completes; `pm-flow cost`
  shows `cli=a2a`; wrong credentials give the distinct `failure_reason`;
  timeout and cancel leave no completed attempt.
- Depends on: T1.

## Task T3 — Outbound: pm-flow as an A2A agent

- Status: pending.
- Outcome: the served Agent Card and task endpoints let an independent client
  submit a task, observe progress, answer `input-required`, and reach a
  terminal state; unauthenticated requests get 401.
- Paths: `src/pm_flow/a2a.py`, `tests/a2a_binding_test.sh`.
- Reuse: the installed `pm-flow` command and the escalation files the driver
  writes.
- Acceptance IDs: A3, A4, A6.
- Validation: `zsh tests/a2a_binding_test.sh` — the reference SDK client (or a
  conformance tool) drives a stub project to `done`; an escalation surfaces
  as `input-required` and the answer lands in the escalation directory; 401
  without credentials.
- Depends on: T1.

## Task T4 — End to end through the installed command

- Status: pending.
- Outcome: a packaged install runs scenarios 1–3 with all suites green.
- Paths: `tests/a2a_binding_test.sh`.
- Reuse: the harness in `tests/packaged_layout_test.sh`.
- Acceptance IDs: A1–A7.
- Validation: `zsh tests/a2a_binding_test.sh`, `zsh tests/agent_bindings_test.sh`,
  `zsh tests/pm_flow_test.sh` exit 0.
- Depends on: T2, T3.

## Integration and end-to-end validation

- Inbound and outbound are proven separately so neither can fake the other;
  the outbound client is never code from this repository.

## Risks and rollback

- Protocol and security drift are confined to `a2a.py`; the binding and the
  server can be disabled independently.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1, A2 | T2, T4 | Remote turn consumed; `cost` shows `cli=a2a` |
| A3, A4 | T3, T4 | Independent client reaches terminal state; input-required round trip |
| A5 | T1, T2 | Prompt-level record before dispatch |
| A6 | T2, T3 | 401 outbound; distinct failure inbound |
| A7 | T4 | Three suites exit 0 |
