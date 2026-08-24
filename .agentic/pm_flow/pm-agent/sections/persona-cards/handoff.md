# persona-cards section handoff

## Outcome

- T1 delivered and accepted (cycle 001, GO). `src/pm_flow/persona_card.py`
  parses, validates and exports a card; forbidden runtime field names are
  refused at any depth with `card field "<name>" is not allowed on a persona`;
  author and provenance carry an enforced `unverified claim:` label; the pinned
  A2A 0.2.5 `AgentSkill` schema ships under
  `template/.agentic/pm_flow/cards/`. Brief A2's validation half, A4 and A6 hold
  on `zsh tests/persona_cards_test.sh` (exit 0, 42 `PASS:`) plus four mutations
  that each fail the suite.
- Install, display and comparison identity (A1, A2's install half, A3, A5, A7)
  are not delivered. `catalog.py` is untouched so far.

## Decisions

- Identity half of the A2A Agent Card only; no endpoint, URL, model, vendor or
  transport field, refused by name.
- No store DDL change: the validated card is stored verbatim under
  `metadata.card` on the `personas` row, and `author`/`version` reuse the
  existing columns. `store.py` is outside owned paths.
- Card validation is its own vocabulary and message, separate from the pack's
  `FORBIDDEN_KEYS` — a pack manifest legitimately carries `source_url`.
- A card is a pack-relative `.json` file named by a `card` key on a manifest
  persona entry, never an inline object.
- `catalog.py` reaches the module by import first, then by the two file-path
  layouts the engine ships in, and fails closed if neither resolves.

## Interfaces

- `persona_card.parse|validate|export`, `PersonaCardError`, `CLAIM_PREFIX`.
- Planned: a `card` key on a manifest persona entry; `metadata.card` on a
  `personas` row; `catalog.py … persona show <key>`.

## Risks

- An author field read as a guarantee. The label is enforced as a value, not a
  comment, and display must print it as written.
- At install a card arrives nested in a manifest entry, where pack-level
  refusals can fire before the card's own wording. T2 must assert the user sees
  the card message.

## What is unproven

- Everything that touches `catalog.py`: install-time refusal wording, atomic
  rollback with a real store, `persona show`, cross-project round trip, and
  distinct listing of two same-name personas.

## Next action

- T2 — install and display.
