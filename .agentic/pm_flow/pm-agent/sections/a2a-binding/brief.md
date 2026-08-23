## Objective

- Let a seat bind an agent that is not a process on this machine, and let
  pm-flow present itself as an agent to somebody else's client, both over A2A.

## Scope

`agent-bindings` makes a seat bind a local agent over the Agent Client Protocol
and exposes pm-flow's commands as MCP tools. Both halves stop at this machine:
ACP spawns an agent as a subprocess and speaks JSON-RPC over its stdio, and MCP
hands tools to something already running here. A2A is the horizontal case — two
opaque agents, on different hosts, owned by different people, over HTTP.

**Read this before touching the brief.** Three protocols use the acronym ACP,
and conflating them will send this section at the wrong target:

- **Agent Client Protocol** (Zed, with JetBrains) — editor-to-agent, JSON-RPC
  over a subprocess's stdio. This is what `agent-bindings` means, and it is
  current.
- **Agent Communication Protocol** (IBM Research / BeeAI) — merged into A2A on
  29 August 2025 and no longer exists separately.
- **Agentic Commerce Protocol** (OpenAI and Stripe) — unrelated to either.

A2A absorbed the second one, not the first. It does not replace `agent-bindings`
and must not be retargeted at local dispatch.

Two halves, independent enough to sequence:

- **Inbound.** A seat binds a remote A2A agent, so a team can include an agent
  this machine could not run: somebody else's, on their hardware, under their
  key. The three access tiers must survive the boundary or be reported as
  unenforceable on that binding, exactly as codex's scoped tier already is.
- **Outbound.** pm-flow publishes an Agent Card and serves the A2A task
  lifecycle, so another client can hand it work and watch it without a shell.
  The lifecycle maps closely onto the one pm-flow already has — `submitted` and
  `working` onto `planned` and `active`, the terminal states onto `done` and
  `cancelled`, `rejected` onto a `NO_GO` — and `input-required` is the standard's
  name for the moment an escalation needs a person. Use their names where they
  fit; do not invent a parallel vocabulary.

Recorded because it will come up and is not this section's work: running seats
through a model router such as OpenRouter is a *binding* question, not an A2A
one. Nothing here should foreclose it, and nothing here should start it.

## Priority

- nice-to-have. Everything pm-flow measures today it can measure with local
  seats; without this, a team simply cannot contain an agent somebody else runs.

## Owned paths

- `src/pm_flow/a2a.py`
- `tests/a2a_binding_test.sh`

New paths only. The seat and transport abstraction this builds on belongs to
`agent-bindings`; extend it from here and hand that section a bounded change if
its interface has to move, rather than editing it from two sections at once.

## Dependencies

- agent-bindings

Real, not habitual. This section's whole premise is that a seat is already a
persona on a binding rather than one of three hardcoded CLIs. Built first, it
would add a fourth arm to the `case` it is supposed to remove.

## Acceptance

Stable IDs `A1`–`A7` refer to the bullets below in order.

Stated as outcomes in the running system, because a criterion that names a
mechanism can be satisfied by a stub while the feature does nothing.

- A seat bound to a remote A2A agent completes a cycle end to end, and its
  result is scoped, reviewed and accepted by the same path a local seat's is.
- The store records that attempt's binding and transport distinguishably from a
  local CLI or ACP seat, so a topology comparison can separate the two arms
  without a human annotating the run.
- A third-party A2A client, given only pm-flow's published Agent Card, drives a
  project to a terminal task state without a shell and without reading this
  repository.
- Work that needs a human decision reaches that client as `input-required` and
  can be answered, rather than surfacing as a failure or a silent stall.
- An A2A binding that cannot enforce a section's access tier says so, per
  binding, before it is dispatched to — not after it has written something.
- The local CLI bindings and the ACP binding still work, unchanged in behaviour.
- The suite still passes.

## Rejection conditions

- A2A is used for local dispatch, putting an HTTP hop between two processes on
  the same machine.
- The A2A surface bypasses the budget ceiling, the driver lock, or a section's
  owned-path boundary.
- An Agent Card is served without authentication, so anything that can reach the
  port can spend model budget.
- A persona names a transport, a vendor or a model.
- A remote binding silently gets more access than its tier allows.
- The task lifecycle is given pm-flow's own names where A2A already defines one.
