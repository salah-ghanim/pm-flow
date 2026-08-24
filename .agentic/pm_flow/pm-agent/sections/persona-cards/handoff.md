## Outcome
- **A1** — `persona show <key>` prints author, purpose, skills, version from the store alone; `attempts`/`spans` counts unchanged across the call (`2 4 -> 2 4`). a0bb325, re-observed on shipped cards in ecc8dc3.
- **A2** — `model`/`vendor`/`transport`/`url`/`endpoint` refused with `card field "<name>" is not allowed on a persona`, nested `skills[0].endpoint` included; row sets of `personas`/`persona_packs`/`seat_personas` byte-identical after refusal. e7a30fb, a0bb325.
- **A3** — two `reviewer`s by different authors list as two rows; `show`/`swap`/`export` refuse a bare key, `--author` selects; a real two-arm `compare report` resolves each arm to a distinct card. 7db802e.
- **A4** — a real exported pack reinstalled into a second store; `metadata.card` compared field by field with set-equality guards, `content_hash` identical. 7db802e.
- **A5** — uncarded pack installs, lists, shows `no card`, and dispatches through two real ticks (persona-packs 011 `acceptance.sh` exit 0). a0bb325, ecc8dc3.
- **A6** — exported skills validate against the pinned A2A `AgentSkill` schema by a walker importing nothing from `persona_card`. e7a30fb.
- **A7** — both suites exit 0 under venv and non-venv `python3` (ecc8dc3), and again on merged `main` at cycle 005.

## Decisions
- Identity half of the Agent Card only; forbidden fields are refused by the card's own vocabulary, not the pack's `FORBIDDEN_KEYS`.
- No store DDL: the validated card is stored verbatim at `metadata.card`; `author`/`version` reuse existing columns.
- Identity is `(key, card author)`, grouped on `COALESCE(json_extract(p.metadata,'$.card.author'),'')`, never `p.author`; an ambiguous key is refused.
- No printed author is rewritten; the claim label is enforced at parse.
- Packaged cards attach during `sync`, base layer only, validated before any write, so a bad card stops every tick.

## Interfaces
- `src/pm_flow/persona_card.py`: `parse`/`validate`/`export`, `PersonaCardError`, `CLAIM_PREFIX`, `FORBIDDEN_CARD_KEYS`.
- `python3 <flow>/catalog.py --db <store> persona show|list|export|swap [--author]`; no `pm-flow persona` wrapper exists.
- Manifest `card:` key naming a pack-relative JSON file; `template/.agentic/pm_flow/cards/<role>.card.json` and the pinned `a2a-agent-skill.schema.json`.
- `personas.metadata.card`; the `(key, content_hash)` in `attempts.persona_stack` addresses exactly one card.

## Risks
- `compare.py:arm_personas` still prints `role=key`, so a reader trusting that column sees no card; one line for that file's owner fixes it.
- A change to `pyproject.toml`'s force-include, `load_persona_card_module` or `cards/` can stop every tick of an installed pm-flow with no suite failing.
- `cmd_persona_export` detects card errors via `"card_module" in locals()` — fragile to any refactor there.

## What is unproven
- `load_persona_card_module`'s wheel-layout branch: no test covers it since cycle 004 deleted the staging copy. Hand-probed at cycle 005 under `python3 -S` — `sync` and `persona show pm` both succeeded — so it works today; a staged-layout case in the suite would settle it.
- Otherwise none: every claim above ran against a real store, a real `sync` or real ticks.

## Next action
- None in this section. `compare.py`'s owner renders card identity in `arm_personas`; `pm_flow.sh`/`cli.py`'s owner adds the `persona` wrapper the brief's scenarios spell.
