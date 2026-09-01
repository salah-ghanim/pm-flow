## Objective

Export an empty dependency list.

## Scope

Non-empty line handling.

## Priority

- must-have: empty files must not create empty strings.

## Owned paths

- `tests/empty_dependencies.json`

## Dependencies

- None.

## Acceptance

- Empty dependencies become an empty array.

## Rejection conditions

- Exporting an empty string dependency.
