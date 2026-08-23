# persona-cards workplan

## Design summary

- Add a portable identity document beside persona content: author claim,
  purpose, skills, version, provenance, and optional signature metadata. Reuse
  the identity/skills vocabulary of A2A Agent Cards, but reject endpoint,
  runtime, vendor, model, and transport fields.

## Interfaces and data changes

- `persona_card.py` validates, normalizes, exports, imports, and maps skills.
- Cards remain optional; catalog identity becomes `(author, name, version)` when
  present and keeps current behavior when absent.

## Task T1 — Define and validate the portable card schema

- Status: pending.
- Outcome: valid cards round-trip losslessly; runtime-specific fields fail with
  field-level errors; provenance is explicitly a claim unless verified.
- Paths: `src/pm_flow/persona_card.py`,
  `template/.agentic/pm_flow/cards/**`, `tests/persona_cards_test.sh`.
- Reuse: persona-pack manifest identity and A2A identity/skills vocabulary.
- Acceptance IDs: A2, A4, A5.
- Validation: canonical round trip, forbidden-field table, missing/extra field
  behavior, unsigned provenance label, and uncarded persona case.
- Depends on: persona-packs (complete).

## Task T2 — Integrate cards with install and display

- Status: pending after catalog ownership transfer from completed persona-packs.
- Outcome: install validates an optional card and list/show displays author,
  purpose, skills, and version without model dispatch.
- Paths: T1 paths plus `template/.agentic/pm_flow/catalog.py` after ownership
  amendment.
- Reuse: persona-pack install transaction and immutable version/provenance rows.
- Acceptance IDs: A1, A2, A5.
- Validation: install carded/uncarded packs, assert display from store only, and
  prove invalid-card installation rolls back atomically.
- Depends on: T1 and ownership transfer.

## Task T3 — Preserve identity through export/import

- Status: pending.
- Outcome: export from project A and install in project B returns every card
  field unchanged and keeps two same-name/different-author personas distinct.
- Paths: `persona_card.py`, `catalog.py`, `tests/persona_cards_test.sh`.
- Reuse: pack Git/local acquisition and content-versioning paths.
- Acceptance IDs: A3, A4.
- Validation: two-project round trip and collision matrix over author/name;
  mutation dropping author or version must fail.
- Depends on: T2.

## Task T4 — Carry card identity into comparisons

- Status: waiting on topology-compare's result schema.
- Outcome: comparison arms report stable card identity, not only a local persona
  name, so same-name personas remain attributable.
- Paths: card/catalog paths; topology-owned code is changed only by that section.
- Reuse: stored persona IDs/card fields and topology comparison output contract.
- Acceptance IDs: A3.
- Validation: compare two same-name/different-author personas and assert each
  metric arm names the correct card.
- Depends on: T3 and topology-compare.

## Task T5 — Validate A2A skill compatibility

- Status: pending.
- Outcome: persona skills map deterministically into the pinned A2A Agent Card
  skill schema without adding endpoint/runtime fields to the persona card.
- Paths: `persona_card.py`, `tests/persona_cards_test.sh`.
- Reuse: an independent A2A schema/client validator; no pm-flow A2A service is
  required for schema compatibility.
- Acceptance IDs: A6, A7.
- Validation: independent schema validation, documented lossy/incompatible
  fields, forbidden endpoint mutation, and full suite.
- Depends on: T1.

## Integration and end-to-end validation

- T1 is next. T2 requires a validated ownership transfer; T4 is verification
  against topology output and must not make persona-cards edit compare code.

## Risks and rollback

- Do not present author/provenance as verified identity without verification.
  Cards are optional, so disabling card parsing preserves existing personas.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1, A2, A5 | T1, T2 | Stored display, forbidden-field refusal, uncarded fallback |
| A3 | T3, T4 | Distinct identity in catalog and comparison |
| A4 | T1, T3 | Cross-project lossless round trip |
| A6 | T5 | Independent A2A skill-schema validation |
| A7 | T5 | Full suite completes |
