# persona-cards section PM state

## Current task

- T3 — identity across projects and in comparisons. T2 accepted cycle 002.

## Completed tasks and evidence

- T2 — install and display. Acceptance IDs A1, A2 (install half), A5.
  Delivered in `template/.agentic/pm_flow/catalog.py` and
  `tests/persona_cards_test.sh`; `git status --porcelain` in the developer
  worktree lists those two paths and nothing else, so `store.py`,
  `FORBIDDEN_KEYS` and `persona_card.py` are untouched.
  - `zsh tests/persona_cards_test.sh` re-run by the reviewer against the
    developer worktree — exit 0.
  - A1, observed directly rather than through the test's `PASS:` lines. A real
    `persona add` of a carded pack, then
    `python3 <flow>/catalog.py --db <db> persona show probe-reviewer` printed
    `author: unverified claim: pm-flow contributors`, `purpose: Review a
    bounded implementation against its stated contract and evidence.`,
    `version: 1.0.0` and both skills as JSON. `SELECT COUNT(*)` on `attempts`
    and `spans` was `0`/`0` before and after. The row carries the card under
    `metadata.card` and takes the card's `author`/`version`, while
    `persona_packs` keeps `Pack Publisher` / `CC-BY-4.0`.
  - A2 install half. The nested case run by hand — a card with
    `skills[0].endpoint` — printed exactly
    `persona add: card field "endpoint" is not allowed on a persona` as its
    first line (`persona add: ` is the pre-existing `catalog.py:1612` framing
    on every `PackError`, not new wrapping), then two secondary lines
    `card field path: skills[0].endpoint` and `card file: cards/bad.json`.
    Full row sets of `personas`, `persona_packs` and `seat_personas` dumped
    before and after compared byte-for-byte with `cmp` — identical. The test
    drives all five of `model`, `vendor`, `transport`, `url`, `endpoint` the
    same way.
  - A5. An uncarded pack installs, lists with its own author and version, and
    `persona show` reports `card: this persona has no card`. The dispatch half:
    `sections/persona-packs/cycles/011/acceptance.sh` exit 0 through two real
    ticks (`tick1_exit=0`, `tick2_exit=0`, `assertions_exit=0`) and
    `regressions.sh` exit 0 (`cycle_008/009/010_exit=0`), both re-run by the
    reviewer from the developer worktree.
  - Fail-closed loading is proved, not asserted: `python3 -S` against a copy of
    `catalog.py` isolated from `pm_flow` refuses a carded pack with
    `persona add: cannot find pm_flow.persona_card to validate persona card`,
    while an uncarded pack still installs.
  - All three required mutations reproduced by the reviewer on an isolated copy
    of the tree, so no implementation source was edited to test it. (1) the
    `PackError` swallowed — exit 1, `refused model install left surviving or
    changed rows` plus a diff showing the `forbidden-model` persona row
    surviving; the rollback assertion really is row-set based, not count based.
    (2) the message prefixed — exit 1, `forbidden model message mismatch:
    'personas[0]: card field "model" …' != 'card field "model" …'`. (3) `card`
    removed from `PERSONA_ENTRY_KEYS` — exit 1,
    `persona add: personas[0] has unsupported field(s): card`, so the fixture
    really carries a card. Control run of the same copy: exit 0. `md5 -q` of
    the reverted copy matched the worktree original
    (`35d0820969ac34b00707f9d100fbb417`).
  - Drift guard beyond the assignment: `zsh tests/pm_flow_test.sh` exit 0
    against the developer worktree. `resolve_inside` gained a keyword `suffix`
    defaulting to `.md`, so its two call sites and every existing message are
    unchanged.

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
- How `catalog.py` reaches `persona_card` is settled, not left to T2's
  judgement: try `import pm_flow.persona_card`, then
  `Path(__file__).resolve().parent.parent / "persona_card.py"` (wheel:
  `pm_flow/engine/catalog.py` beside `pm_flow/persona_card.py`), then
  `parents[3] / "src" / "pm_flow" / "persona_card.py"` (checkout). If none
  resolve, a pack carrying a `card` is refused naming the missing module and an
  uncarded pack is untouched — fail closed, because a card installed unvalidated
  is exactly brief A2's failure.

## Carried into later tasks

- T3 — the vestigial `path` in `_reject_forbidden_fields`
  (`persona_card.py:35-49`) is still vestigial. Cycle 002's assignment asked to
  resolve it but did not make `persona_card.py` writable, so the developer took
  the only reachable option and produced the field path a second time, in
  `catalog.py:forbidden_card_field_path`. That duplicate walk must stay in step
  with the module's own walk or the install diagnostic will name a different
  field from the one that was refused. T3 owns `persona_card.py`: attach the
  path to `PersonaCardError` — leaving the message itself unchanged, because
  brief A2 pins it — and delete the catalog copy. This was my drafting error,
  not the developer's; do not re-issue a rejection condition whose fix is
  outside the writable paths of the same assignment.
- T3 — `catalog.py:1228` defines an accessor `persona_card(raw_metadata)` while
  `read_pack` binds the *module* to the same name locally
  (`catalog.py:1038`). Both work today only because `read_pack` never calls the
  accessor. Rename the accessor when T3 touches the file.
- T3 — mutation A (cycle 001) showed a top-level `url` is caught by the card
  vocabulary allowlist even with `FORBIDDEN_CARD_KEYS` emptied of it. The two
  checks overlap at the top level; only the nested path is uniquely the walk's.
  Keep the nested case in every future forbidden-field assertion.
- T3 — A1's no-dispatch observation currently reads `0`/`0` on both sides. It
  does detect a dispatch (a dispatch would move `attempts`), but it cannot tell
  a working count from an empty table. When T3 has a store with real attempts
  in it, take the counts there instead.
- T3 — `persona show` prints `tags:` for an uncarded persona and omits it for a
  carded one. A3 compares two same-name personas side by side, so settle one
  output shape before writing that assertion.
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

## Housekeeping for the driver

- Reviewer scaffolding accumulating in the main checkout, all untracked and
  none of it section state — drop rather than commit: from cycle 001,
  `sections/persona-cards/review_probe.sh` and
  `sections/persona-cards/.review_backup/`; from cycle 002,
  `sections/persona-cards/review_002_{run,probe,mutations,mut1_tail,suite}.sh`.
  Cycle 002's reviewer mutated an isolated copy of the tree under `/tmp`, so
  no `.review_backup/` of implementation source was needed this time.
- Running `sections/persona-packs/cycles/011/acceptance.sh` rewrites that
  cycle's own `transcripts/`, `prompt-v1.txt` and `prompt-v2.txt` in the main
  checkout (`acceptance.sh:348-352`). The reviewer's run left them
  byte-identical (`git status` on `sections/persona-packs/` is empty
  afterwards), but any run against changed behaviour will dirty another
  section's committed artifacts.
- `.last_error.txt` holds three `claude hit a usage limit; pausing 1800s`
  lines from the dispatch after cycle 001. A quarantine, not a section failure;
  no evidence in this file depends on it.

## Probes run this cycle (002 scope)

- `git status --porcelain` on the four owned paths — empty; `persona_card.py`,
  both card files and `tests/persona_cards_test.sh` are committed and on disk,
  and `catalog.py` is untouched. T1 is real, not worktree-local.
- `pyproject.toml:44-51` — `[tool.hatch.build.targets.wheel.force-include]` maps
  `template/.agentic/pm_flow` to `pm_flow/engine`, and `paths.py:51-72` reads the
  same two layouts back. `tests/pm_flow_test.sh:221-234` asserts the installer
  copies no engine file into a repository. So `catalog.py` only ever runs from
  one of the two locations recorded under Active decisions.
- `grep -n "sys.path\|import pm_flow\|find_spec" catalog.py store.py cost.py` —
  only `sys.path.insert(0, <own dir>)` in `catalog.py:42` and `cost.py:22`. No
  existing engine script imports the `pm_flow` package, so T2 introduces the
  first such edge and owns getting it right.
- `store.py:311,390` — `attempts` and `spans` are the tables a dispatch writes;
  they are what A1's "no dispatch" assertion counts.
- `catalog.py:1689-1735` — `main` registers `persona add|list|update|swap`; there
  is no `persona show`, and the top-level `show` (`catalog.py:1707` → `cmd_show`)
  is a different command. T2 adds a fifth `persona` subparser.
- `catalog.py:1214-1283` — `install_pack` wraps every write in `BEGIN IMMEDIATE`
  with `rollback()` on any exception; `read_pack` (`catalog.py:924-1006`)
  validates everything before the store is opened. Both are already atomic, so
  A2's rollback half is inherited if card validation lands in either place.
- `src/pm_flow/persona_card.py` re-read — public surface is `parse(text)`,
  `validate(card)`, `export(card)`, `PersonaCardError`, `CLAIM_PREFIX`,
  `FORBIDDEN_CARD_KEYS`, `CARD_KEYS`. `validate` returns the card unchanged, so
  storing the validated object verbatim needs no second pass.

## Probes carried from cycle 001

- `catalog.py:848-856` — `FORBIDDEN_KEYS` lacks `vendor`, `transport`, `url`,
  `endpoint`; `PERSONA_ENTRY_KEYS` is `{key, file, layer, title, summary,
  tags}`, so an unknown `card` entry field is currently refused
  (`catalog.py:966`).
- `store.py:80-99` — `personas` carries `author`, `license`, `source_url`,
  `version`, `tags`, `metadata`, `content_hash`.
- No `pm-flow persona` wrapper: `pm_flow.sh` and `src/pm_flow/cli.py` have no
  `persona` subcommand.
- `.venv/lib/python3.14/site-packages` holds `pm_flow` (editable, via
  `_editable_impl_pm_flow.pth`) and nothing else; `jsonschema` is not installed.
- `persona-packs` cycle 011 harness is on disk:
  `sections/persona-packs/cycles/011/{acceptance.sh,assertions.py,regressions.sh}`.

## Next eligible task

- T3 — identity across projects and in comparisons (A3, A4). T2 is complete, so
  its dependency is satisfied. Carry the four T3 items above into the
  assignment; `persona_card.py` must be writable this time.
