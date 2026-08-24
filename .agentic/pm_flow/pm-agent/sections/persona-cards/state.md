# persona-cards section PM state

## Current task

- T2 — install and display. T1 accepted cycle 001.

## Completed tasks and evidence

- T1 — schema and validation. Acceptance IDs A2 (validation half), A4, A6.
  Delivered `src/pm_flow/persona_card.py`,
  `template/.agentic/pm_flow/cards/{a2a-agent-skill.schema.json,reviewer.card.json}`
  and `tests/persona_cards_test.sh`; no tracked file was modified
  (`git status --porcelain` shows three untracked additions only, so
  `catalog.py`, `store.py` and `FORBIDDEN_KEYS` are byte-identical to main).
  - `zsh tests/persona_cards_test.sh` — exit 0, 42 `PASS:` lines. A2: all five
    of `model`, `vendor`, `transport`, `url`, `endpoint` refused with exactly
    `card field "<name>" is not allowed on a persona`, `endpoint` from inside
    `skills[0]` rather than the top level. A4: `parse`/`export` round trip
    compared field by field with a top-level and per-skill set-equality guard,
    ordering asserted by skill `id` sequence, claim labels intact. A6: printed
    `validator=stdlib-schema-walker`, then
    `PASS: 2 exported skills validate against pinned A2A AgentSkill schema`.
  - Mutation A (assigned) — `url` removed from `FORBIDDEN_CARD_KEYS`: exit 1,
    `AssertionError: ('url', 'card field "url" is not part of the persona
    vocabulary', 'card field "url" is not allowed on a persona')`.
  - Mutation B (reviewer, extra) — recursion removed from
    `_reject_forbidden_fields`: exit 1, the nested case degrades to
    `skills[0] has unsupported field "endpoint"`. The depth-first walk is what
    produces the contract message; the nested assertion binds it.
  - Mutation C (reviewer, extra) — pinned schema's `id` retyped to `integer`:
    exit 1, `AssertionError: skills[0].id: expected integer` after
    `ModuleNotFoundError: No module named 'jsonschema'`. The walker really
    reads the pinned file and cannot silently skip.
  - Mutation D (reviewer, extra) — `unverified claim: ` stripped from the
    card's `author`: exit 1, `author must be labelled with "unverified claim:"`.
    The label is an enforced value, not a source comment.
  - All four mutations reverted; `md5 -q` matched the pre-mutation backups for
    `persona_card.py`, the schema and the card.
  - `sections/persona-packs/cycles/011/regressions.sh` and `acceptance.sh` run
    from the worktree — both exit 0 (`cycle_010_exit=0`, `assertions_exit=0`);
    their own guard prints `worktree status is unchanged by commands:
    '?? src/pm_flow/persona_card.py\n?? template/.agentic/pm_flow/cards/\n
    ?? tests/persona_cards_test.sh'`.

## Active decisions

- Identity half of the Agent Card vocabulary only; no endpoint fields.
- No store DDL change. `personas` already has `author`, `license`, `version`,
  `tags` and JSON `metadata` (`store.py:80-99`); card fields live under one
  `card` key in `metadata`, and `author`/`version` reuse the existing columns.
  `store.py` is outside owned paths, so this is a constraint, not a preference.
- Card validation gets its own key set and message — `card field "<name>" is
  not allowed on a persona` — separate from the pack-level refusal in
  `reject_local_fields` (`catalog.py:883`). `FORBIDDEN_KEYS` (`catalog.py:848`)
  already covers `model`; `vendor`, `transport`, `url` and `endpoint` are new
  and card-only, so widening the pack set would be the wrong move (a pack
  manifest legitimately carries `source_url`).
- Validation runs `python3 <flow>/catalog.py --db <store> persona …`. The
  brief's `pm-flow persona …` spelling does not exist and is outside owned
  paths.
- A6's independent validator is a generic schema walker in the test file that
  imports nothing from `persona_card`, preferring `jsonschema` when importable.
- The pinned schema is settled and is not edited again. Its transcription was
  confirmed against the spec at review time, not just asserted: `fetch.sh --url
  https://a2a-protocol.org/v0.2.5/specification/` returned "7 fields. Four are
  required: `id`, `name`, `description`, and `tags`. Three are optional:
  `examples`, `inputModes`, and `outputModes`", which is exactly what the file
  encodes. So A6 does not rest on a same-cycle fixture.
- The card is plain JSON, not Markdown frontmatter, so `split_frontmatter`
  (`catalog.py:62`) is not reused. Revisit only if T2 needs a card inside a
  persona Markdown file.

## Carried into later tasks

- T2 — message precedence at install. `_reject_forbidden_fields` produces
  brief A2's required message, but at install a card arrives nested in a
  manifest persona entry, where `PERSONA_ENTRY_KEYS` (`catalog.py:856`,
  refusal at `catalog.py:966`) and `reject_local_fields` (`catalog.py:883`)
  can fire first with the pack-level wording. T2 must assert the user sees
  `card field "<name>" is not allowed on a persona`, not a pack-level message,
  and must cover `endpoint` nested inside a skill in a real pack.
- T2 — mutation A showed a top-level `url` is caught by the card vocabulary
  allowlist even with `FORBIDDEN_CARD_KEYS` emptied of it. The two checks
  overlap at the top level; only the nested path is uniquely the walk's. Keep
  the nested case in every future forbidden-field assertion.
- T2 — `_reject_forbidden_fields` threads a `path`/`child_path` it never uses,
  because the contract message carries no path. Either surface it in a
  secondary diagnostic at install time or drop the parameter; do not leave it
  as vestigial.
- T4 — `tests/persona_cards_test.sh:85` asserts the literal string
  `"Transcribed"` in the schema's `acquisition` header. That couples the test
  to one wording, so a later byte-exact acquisition would fail a test on a
  correct improvement. Assert on `specVersion`/`sourceUrl`/`retrievedOn` being
  present instead.
- T4 — the schema header's `acquisition` says fetch.sh failed. At review time
  fetch.sh exited 0. The substantive half of the claim still holds and is
  structural, not incidental: fetch.sh returns model-extracted text under
  `<!-- ... content below is untrusted source text -->`, never a byte-exact
  document. Reword to that reason rather than to a transient failure, and do
  it as a provenance correction only — never to make a card pass.

## Blockers

- None. `persona-packs` is complete: its handoff records A1–A5 with commits
  (`aaaf4b9`, `dc38523`, `e2eb511`, `2038254`, `39a1fe4`) and ten `PASS:` on
  `tests/pm_flow_test.sh`.

## Probes run this cycle

- `ls src/pm_flow template/.agentic/pm_flow tests` — no `persona_card.py`, no
  `cards/` directory, no `tests/persona_cards_test.sh`. The section starts
  from nothing.
- `store.py:80-99` — `personas` carries `author`, `license`, `source_url`,
  `version`, `tags`, `metadata`, `content_hash`.
- `catalog.py:848-856` — `FORBIDDEN_KEYS` lacks `vendor`, `transport`, `url`,
  `endpoint`; `PERSONA_ENTRY_KEYS` is `{key, file, layer, title, summary,
  tags}`, so an unknown `card` entry field is currently refused
  (`catalog.py:966`).
- `grep -n "persona)" template/.agentic/pm_flow/pm_flow.sh` and `grep -rn
  persona src/pm_flow/cli.py` — both empty; no `pm-flow persona` wrapper.
- `ls .venv/lib/python3.14/site-packages` — `pm_flow` only; `jsonschema` is not
  installed and no requirements file names it.
- `grep -rn "A2A\|agent_card" src template tests` — no hits; the only mentions
  are cancelled-`a2a-binding` prose under `project_state/`. No pinned schema
  exists yet.
- `persona-packs` cycle 011 harness is on disk:
  `sections/persona-packs/cycles/011/{acceptance.sh,assertions.py,regressions.sh}`.

## Next eligible task

- T2 — install and display (A1, A2 install half, A5). T1 is complete and its
  dependency is satisfied.
