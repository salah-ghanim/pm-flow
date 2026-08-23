## Objective

- A seat binds an agent on another host over A2A, and pm-flow serves itself
  as an A2A agent so another client can hand it work and watch it.

## Current baseline

- `agent-bindings` supplies the binding interface (`bindings.cli` plus
  `cli_params`), the ACP arm, and the MCP tool surface; all of it is local to
  this machine.
- Nothing in pm-flow speaks HTTP to another agent in either direction.

## Deliverables

- `src/pm_flow/a2a.py`: Agent Card discovery, authenticated HTTP transport,
  the A2A task lifecycle mapped onto pm-flow's, `input-required` for an
  escalation that needs a person, and the outbound server.
- The `a2a` binding arm (via the interface `agent-bindings` produced).
- `tests/a2a_binding_test.sh`.

## User-visible scenarios

1. `config.json` binds `consultant` to `{"cli": "a2a", "cli_params":
   {"card": "https://host/.well-known/agent.json"}}`; a panel seat on that
   binding returns a proposal that the adjudication reads like any other.
2. A third-party A2A client, given only pm-flow's Agent Card URL, submits a
   task, watches it move through `submitted`, `working` and a terminal state,
   and answers one `input-required` turn.
3. `pm-flow cost` shows the remote attempt with `cli=a2a`.

## Interfaces produced

- Binding `cli: a2a` with `cli_params.card` and credentials by reference.
- Served Agent Card at `/.well-known/agent.json`; A2A task endpoints.

## Interfaces consumed

- `agent-bindings`' binding/result/access interface and access-record
  convention; the escalation state the driver already exposes.

## Scope

- In: inbound remote seats, the outbound server, lifecycle and auth, tests.
- Out: local dispatch over HTTP; model routers; the Agent Client Protocol,
  which is a different protocol with a colliding acronym.

## Non-goals

- Serving the Agent Card unauthenticated.
- A parallel lifecycle vocabulary where A2A defines one.

## Priority

- nice-to-have: everything pm-flow measures today it measures with local
  seats; without this a team cannot contain an agent somebody else runs.

## Owned paths

- `src/pm_flow/a2a.py`
- `tests/a2a_binding_test.sh`

## Dependencies

- agent-bindings

## Constraints and fixed decisions

- Lifecycle mapping: `submitted`→`planned`, `working`→`active`, terminal
  states→`done`/`cancelled`, `rejected`→`NO_GO`, `input-required`→an
  escalation awaiting a person.
- The arm that dispatches an `a2a` binding lives in the interface
  `agent-bindings` produced; if that requires an `agent_exec.sh` edit, it is
  a boundary conflict to report, not an edit from here.
- Authentication is required on both directions; secrets are referenced from
  the environment, never stored.

## Acceptance

- A1: In `tests/a2a_binding_test.sh`, a seat bound to a protocol-faithful A2A
  test agent over local HTTP completes one panel or cycle turn whose result
  is consumed by the ordinary path.
- A2: `pm-flow cost` shows that attempt with `cli=a2a`, distinct from an
  `acp` or `claude` attempt on the same project.
- A3: An independent A2A client (the reference SDK client or a conformance
  tool, not code from this repository) discovers pm-flow from its served
  Agent Card and drives a disposable project to a terminal task state.
- A4: When the project reaches an escalation needing a person, that client
  receives `input-required` and its answer is recorded where the driver reads
  it.
- A5: A binding whose agent cannot honour the access tier is recorded as
  prompt-level before dispatch, as `agent-bindings` A3 records it.
- A6: A request without credentials to the served endpoints is refused with
  401; a remote agent rejecting pm-flow's credentials yields a distinct
  `failure_reason`.
- A7: `zsh tests/a2a_binding_test.sh`, `zsh tests/agent_bindings_test.sh` and
  `zsh tests/pm_flow_test.sh` exit 0.

## Rejection conditions

- A2A used between two processes on the same machine.
- The served surface bypasses the budget ceiling, the driver lock or a
  section's owned-path boundary.
- An Agent Card served without authentication.
- A persona names a transport, vendor or model.

## Open questions

- Which A2A protocol revision to pin; decided in T1 from the current
  specification and recorded in `a2a.py`.
