# persona-cards workplan

## Design summary

- A small schema module with the identity half of the Agent Card vocabulary;
  the catalog validates an optional card inside its existing install
  transaction and stores its fields on the persona row; display and export
  read the store.

## Interfaces and data changes

- `persona_card.parse|validate|export`; `persona show <key>`, a new subcommand —
  `main` registers `persona add|list|update|swap` only (`catalog.py:1710-1731`),
  and the top-level `show` (`catalog.py:1707`) is a different command.
- A `card` key on a manifest persona entry, naming a pack-relative `.json` file
  the way `file` names the persona's Markdown. Not an inline object:
  `reject_local_fields(manifest, PACK_MANIFEST)` (`catalog.py:947`) walks the
  whole manifest before any entry is read, and `model` is in `FORBIDDEN_KEYS`
  (`catalog.py:848`), so an inline card carrying `model` would be refused in the
  pack's wording rather than brief A2's. A referenced file never enters the
  manifest, so the card vocabulary is the only thing that judges it, and the
  same file shape is what T3 exports and T4 packages.
- No store DDL change. `personas` already carries `author`, `license`,
  `version`, `tags` and a JSON `metadata` column (`store.py:80-99`); the whole
  validated card is stored verbatim under one `metadata.card` key, alongside the
  existing `metadata.git_commit` (`catalog.py:1113`), and `author`/`version`
  take the card's values while the pack's own author and licence stay on the
  `persona_packs` row. Storing it verbatim is what makes T3's export lossless by
  construction. `store.py` is outside this section's owned paths, so a schema
  bump is out of scope by construction.
- Card validation is its own vocabulary, not the pack's. `FORBIDDEN_KEYS`
  (`catalog.py:848`) already refuses `model`, `binding`, `tool`, `access` and
  friends with a pack-level message; the card additionally refuses `vendor`,
  `transport`, `url` and `endpoint`, and says `card field "<name>" is not
  allowed on a persona`. `PERSONA_ENTRY_KEYS` (`catalog.py:856`) rejects unknown
  entry fields, so `card` has to be added there in T2.
- `catalog.py` runs as a standalone script under a plain interpreter —
  `python3 "$SCRIPT_DIR/catalog.py"` (`driver.zsh:735`), with only its own
  directory on `sys.path` (`catalog.py:42-43`) — so `pm_flow.persona_card` is
  not importable there, and a sibling `template/.agentic/pm_flow/persona_card.py`
  is outside this section's owned paths. The card module is therefore loaded by
  file path with `importlib.util.spec_from_file_location`, the pattern already
  used at `src/pm_flow/quality.py:94-105`, preferring an importable
  `pm_flow.persona_card` when there is one.
- The file-path candidates are fixed by the two layouts the engine actually
  ships in, both probed this cycle. Installed, the wheel force-includes
  `template/.agentic/pm_flow` as `pm_flow/engine` (`pyproject.toml:47-51`), so
  `catalog.py` sits at `<site-packages>/pm_flow/engine/catalog.py` and the module
  is `Path(__file__).resolve().parent.parent / "persona_card.py"`. From a
  checkout `catalog.py` sits at `<repo>/template/.agentic/pm_flow/catalog.py`
  and the module is `parents[3] / "src" / "pm_flow" / "persona_card.py"`. These
  are the same two branches `paths.engine_root` (`paths.py:51-72`) already walks
  in the opposite direction; nothing is copied into a repository
  (`tests/pm_flow_test.sh:221-234` asserts the installer ships no engine), so
  there is no third location to search.
- Loading fails closed. If no candidate resolves, a pack carrying a `card` is
  refused with a message naming the missing module, and an uncarded pack
  installs exactly as it does today. Installing a card unvalidated because the
  validator could not be found is the one outcome that would let brief A2
  through, and silently skipping cards would make A5 pass for the wrong reason.

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

- Status: complete (cycle 002, GO_WITH_CHANGES).
- Outcome: `persona add` validates an optional card while reading the pack and
  stores it on the persona row; a new `persona show <key>` prints author,
  purpose, skills and version from the store alone; a card carrying a forbidden
  field is refused in the card's wording and leaves no rows; an uncarded pack is
  unaffected.
- Paths: `template/.agentic/pm_flow/catalog.py`, `tests/persona_cards_test.sh`.
- Reuse: `read_pack` (`catalog.py:924`) and `resolve_inside` (`catalog.py:903`)
  for pre-store validation; `install_pack` (`catalog.py:1214`) and
  `adopt_persona` (`catalog.py:1143`) for the metadata write;
  `persona_git_metadata` (`catalog.py:1116`) for the merge shape;
  `cmd_persona_list` (`catalog.py:1595`) for the display shape;
  `quality.py:94-105` for loading a module by file path.
- Acceptance IDs: A1, A2, A5.
- Validation: `zsh tests/persona_cards_test.sh` — a carded pack installs and
  `persona show` prints its fields with no dispatch recorded; all five forbidden
  names, including one nested inside a skill, are refused at install in the
  card's wording and leave the store exactly as it was; an uncarded pack
  installs and lists unchanged. Plus `sections/persona-packs/cycles/011/
  acceptance.sh` exit 0 for A5's dispatch half through a real tick.
- "No dispatch" is a store observation, not an absence of output: `attempts`
  (`store.py:311`) and `spans` (`store.py:390`) are the tables a dispatch writes,
  so the test counts rows in both immediately before and after `persona show`
  and asserts the counts are equal. A `persona show` that reached a model would
  move at least one of them.
- Rollback is asserted the same way — the full row set of `personas`,
  `persona_packs` and `seat_personas` captured before a refused install and
  compared after, not just a count. `install_pack` (`catalog.py:1234-1281`)
  opens `BEGIN IMMEDIATE` and rolls back on any exception, so card validation
  placed in `read_pack` never opens the store at all, and card validation placed
  inside the transaction rolls back; the point of the assertion is to prove which
  one the implementation actually got.
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
- Also carried from T2, because `persona_card.py` is writable again here:
  return the rejected field path from `_reject_forbidden_fields`
  (`persona_card.py:35-49`) — as an attribute on `PersonaCardError`, so the
  contract message is unchanged — and delete
  `catalog.py:forbidden_card_field_path`, which currently re-implements the
  same depth-first walk purely to produce the install diagnostic. Two walks
  that must agree on which field was rejected is the drift risk. Rename the
  `persona_card(raw_metadata)` accessor (`catalog.py:1228`) at the same time;
  it collides by name with the module object `read_pack` binds locally.
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
