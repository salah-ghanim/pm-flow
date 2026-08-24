# persona-cards workplan

## Design summary

- A small schema module with the identity half of the Agent Card vocabulary;
  the catalog validates an optional card inside its existing install
  transaction and stores its fields on the persona row; display and export
  read the store.

## Interfaces and data changes

- `persona_card.parse|validate|export`; `persona show`; a `card` key on a
  manifest persona entry.
- No store DDL change. `personas` already carries `author`, `license`,
  `version`, `tags` and a JSON `metadata` column (`store.py:80-99`); the card's
  `purpose`, `skills` and card version land in `metadata` under one `card` key,
  and `author`/`version` reuse the existing columns. `store.py` is outside this
  section's owned paths, so a schema bump is out of scope by construction.
- Card validation is its own vocabulary, not the pack's. `FORBIDDEN_KEYS`
  (`catalog.py:848`) already refuses `model`, `binding`, `tool`, `access` and
  friends with a pack-level message; the card must additionally refuse
  `vendor`, `transport`, `url` and `endpoint`, and must say `card field
  "<name>" is not allowed on a persona`. `PERSONA_ENTRY_KEYS` (`catalog.py:856`)
  rejects unknown entry fields, so `card` has to be added there in T2.

## Task T1 — Schema and validation

- Status: complete (cycle 001, GO).
- Outcome: `persona_card.py` parses a card, refuses forbidden fields by name,
  labels provenance as a claim, round-trips losslessly, and documents the
  Agent Card fields it omits.
- Paths: `src/pm_flow/persona_card.py`,
  `template/.agentic/pm_flow/cards/a2a-agent-skill.schema.json`,
  `template/.agentic/pm_flow/cards/reviewer.card.json`,
  `tests/persona_cards_test.sh`.
- Reuse: the pack index's identity fields; `split_frontmatter`
  (`catalog.py:62`); the shape of `reject_local_fields` (`catalog.py:883`) for
  depth-first refusal, with the card's own message and key set.
- Acceptance IDs: A2 (validation half), A4, A6.
- Validation: `zsh tests/persona_cards_test.sh` — round trip of a canonical
  card; forbidden-field table with the expected message per field; skills
  validate against the pinned A2A schema with a validator that does not import
  `persona_card`; a mutation accepting `url` fails.
- Depends on: persona-packs done — satisfied, cycle 012 COMPLETE.

## Task T2 — Install and display

- Status: pending.
- Outcome: `persona add` validates an optional card inside the install
  transaction and stores its fields; `persona show` and `persona list` display
  them from the store; an invalid card rolls the install back.
- Paths: `template/.agentic/pm_flow/catalog.py`, `tests/persona_cards_test.sh`.
- Reuse: `persona-packs`' install transaction and version rows; `cmd_persona_list`
  (`catalog.py:1595`) for the display shape; `install_and_report`
  (`catalog.py:1538`).
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
- The brief spells the scenarios `pm-flow persona …`. That spelling does not
  exist: `pm_flow.sh` has no `persona` subcommand and neither does
  `src/pm_flow/cli.py`, and both are outside owned paths. Every validation in
  this section runs `python3 <flow>/catalog.py --db <store> persona …`, the
  spelling `persona-packs` proved. The wrapper stays a one-line gap for
  whichever section owns `pm_flow.sh`.
- `jsonschema` is installed nowhere: the repo venv holds only `pm_flow`
  (`.venv/lib/python3.14/site-packages`), and no requirements file names it.
  A6's independent validator is therefore a generic schema walker inside
  `tests/persona_cards_test.sh` that reads the pinned schema and imports
  nothing from `persona_card`; it uses `jsonschema` when importable and its own
  walker otherwise, and fails rather than skips when neither runs.
- Nothing in the repo mentions A2A (`grep -rn "A2A\|agent_card" src template
  tests` hits only cancelled-section prose in `project_state/`), and `fetch.sh`
  returns extracted text as an untrusted claim rather than a file, so the
  pinned schema cannot be downloaded byte-exact. It is transcribed once, with
  spec version, source URL and retrieval date in a header, and never edited to
  suit a card.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1, A5 | T2 | Display from the store; uncarded persona runs |
| A2 | T1, T2 | Refusal names the field; atomic rollback |
| A3, A4 | T3 | Distinct listing; lossless round trip |
| A6 | T1 | Independent schema validation |
| A7 | T4 | Both suites exit 0 |
