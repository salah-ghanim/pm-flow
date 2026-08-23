## Objective

- A persona can carry a card — author, purpose, skills, version — so that
  two personas with the same name are distinguishable, a comparison says
  which one it measured, and the author can be credited.

## Current baseline

- `persona-packs` installs personas from a path or Git URL with source URL,
  commit and content hash as provenance, lists them, updates them and swaps
  one seat layer; a persona is a Markdown file and a pack has a JSON index.
- Nothing records who wrote a persona or what it is for; two personas named
  `reviewer` from different authors are indistinguishable once installed.
- A2A's Agent Card settles identity, skills, versioning and provenance for a
  deployed endpoint; a persona is a prompt and describes no runtime.

## Deliverables

- `src/pm_flow/persona_card.py`: the card schema (identity half of the Agent
  Card vocabulary, no endpoint or runtime fields), parse, validate, export.
- `catalog.py` validating an optional card on install and showing it on
  `persona list`/`persona show`.
- Cards for the packaged personas under `template/.agentic/pm_flow/cards/`.
- `tests/persona_cards_test.sh`.

## User-visible scenarios

1. `pm-flow persona add ./reviewer-pack` installs a persona with a card;
   `pm-flow persona show reviewer` prints author, purpose, skills and version
   without any model call.
2. A pack whose card names a model is refused at install with `card field
   "model" is not allowed on a persona`.
3. Two packs each install a `reviewer` by different authors; `persona list`
   shows both with their authors, and a `compare` report column names the
   card (author/name/version) rather than only `reviewer`.

## Interfaces produced

- The card schema; `persona show`; per-persona card fields in the store's
  `personas` rows and in the comparison report's persona identity.

## Interfaces consumed

- `persona-packs`' install transaction and version rows; the A2A Agent Card
  identity/skills vocabulary; `topology-compare`'s report persona field.

## Scope

- In: schema, validation, install/display integration, packaged cards,
  export/import round trip, skill-schema compatibility check, tests.
- Out: a registry, signing, model routing, any endpoint field.

## Non-goals

- Making cards mandatory.
- Presenting an unverified author as a trust signal.

## Priority

- nice-to-have: personas work uncredited; without cards a persona nobody can
  attribute is one nobody will publish.

## Owned paths

- `src/pm_flow/persona_card.py`
- `template/.agentic/pm_flow/cards/**`
- `template/.agentic/pm_flow/catalog.py`
- `tests/persona_cards_test.sh`

## Dependencies

- persona-packs

## Constraints and fixed decisions

- A card carries no model, vendor, transport, URL or endpoint; the validator
  refuses each by field name.
- Author and provenance are labelled as claims unless a later section
  verifies them.
- `catalog.py` is shared with `persona-packs` only on paper: the dependency
  means this section is not dispatched until that one is done.

## Acceptance

- A1: `pm-flow persona show <key>` prints a carded persona's author, purpose,
  skills and version from the store alone; the test asserts no dispatch
  occurred.
- A2: Installing a pack whose card carries `model`, `vendor`, `transport`,
  `url` or `endpoint` is refused, the message names the field, and the
  install rolls back atomically (no partial rows).
- A3: Two same-name, different-author personas both install and list
  distinctly; a `compare --report` fixture with one on each arm names each
  card in its column.
- A4: A card exported from project A and installed into project B reads back
  identical in every field.
- A5: A persona with no card installs, lists and is dispatched unchanged.
- A6: The card's skills serialise into the pinned A2A Agent Card `skills`
  schema and validate with an independent JSON-schema validator against that
  schema; fields the card deliberately lacks are documented in
  `persona_card.py`.
- A7: `zsh tests/persona_cards_test.sh` and `zsh tests/pm_flow_test.sh` exit 0.

## Rejection conditions

- A card with an endpoint, URL, model, vendor or transport field is accepted.
- An uncarded persona stops working.
- Author or provenance is rendered as verified.
- Card fields are proven only against a fixture the same cycle wrote.

## Open questions

- None.
