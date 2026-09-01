## Objective

Reject a corrupt handoff.

## Scope

Failure behavior.

## Priority

- must-have: invalid input must not reach stdout.

## Owned paths

- `tests/corrupt_handoff.json`

## Dependencies

- None.

## Acceptance

- A1: The malformed handoff is rejected.

## Rejection conditions

- Emitting partial JSON.
