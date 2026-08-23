# persona-cards workplan

## Design summary

- A small schema module with the identity half of the Agent Card
  vocabulary; the catalog validates an optional card inside its existing
  install transaction and stores its fields on the persona row; display and
  export read the store.

## Interfaces and data changes

- `persona_card.parse|validate|export`; `persona show`; card columns on
  `personas` (author, purpose, skills JSON, card version) added by the
  catalog's existing schema-version mechanism.

## Task T1 — Schema and validation

- Status: pending.
- Outcome: `persona_card.py` parses a card, refuses forbidden fields by name,
  labels provenance as a claim, round-trips losslessly, and documents the
  Agent Card fields it omits.
- Paths: `src/pm_flow/persona_card.py`, `template/.agentic/pm_flow/cards/**`,
  `tests/persona_cards_test.sh`.
- Reuse: the pack index's identity fields; A2A Agent Card identity/skills
  names.
- Acceptance IDs: A2 (validation half), A4, A6.
- Validation: `zsh tests/persona_cards_test.sh` — round trip of a canonical
  card; forbidden-field table with the expected message per field; skills
  validate against the pinned A2A schema with an independent validator; a
  mutation accepting `url` fails.
- Depends on: persona-packs done.

## Task T2 — Install and display

- Status: pending.
- Outcome: `persona add` validates an optional card inside the install
  transaction and stores its fields; `persona show` and `persona list` display
  them from the store; an invalid card rolls the install back.
- Paths: `template/.agentic/pm_flow/catalog.py`, `tests/persona_cards_test.sh`.
- Reuse: `persona-packs`' install transaction and version rows.
- Acceptance IDs: A1, A2, A5.
- Validation: `zsh tests/persona_cards_test.sh` — carded and uncarded packs
  install; `show` prints the fields with no dispatch recorded; an invalid
  card leaves no rows; an uncarded persona dispatches through a stub tick.
- Depends on: T1.

## Task T3 — Identity across projects and in comparisons

- Status: pending.
- Outcome: export from A and install into B is lossless; two same-name
  different-author personas list distinctly; a `compare --report` fixture
  names each card per arm.
- Paths: `src/pm_flow/persona_card.py`, `template/.agentic/pm_flow/catalog.py`,
  `tests/persona_cards_test.sh`.
- Reuse: pack export; `topology-compare`'s report persona field (read only;
  if the field is absent the test asserts on the store rows the report reads).
- Acceptance IDs: A3, A4.
- Validation: `zsh tests/persona_cards_test.sh` — two-project round trip with
  field-by-field equality; author/name collision matrix; a mutation dropping
  author makes the two personas collide and fails.
- Depends on: T2.

## Task T4 — Closeout

- Status: pending.
- Outcome: packaged cards ship for the default personas; both suites pass.
- Paths: `template/.agentic/pm_flow/cards/**`, `tests/persona_cards_test.sh`.
- Reuse: T1–T3.
- Acceptance IDs: A7.
- Validation: `zsh tests/persona_cards_test.sh` and `zsh tests/pm_flow_test.sh`
  exit 0.
- Depends on: T3.

## Integration and end-to-end validation

- T3 is where scenario 3 is observable end to end.

## Risks and rollback

- Presenting provenance as verified is the failure to avoid; the label is an
  acceptance requirement. Cards are optional, so disabling parsing leaves
  every persona working.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1, A5 | T2 | Display from the store; uncarded persona runs |
| A2 | T1, T2 | Refusal names the field; atomic rollback |
| A3, A4 | T3 | Distinct listing; lossless round trip |
| A6 | T1 | Independent schema validation |
| A7 | T4 | Both suites exit 0 |
