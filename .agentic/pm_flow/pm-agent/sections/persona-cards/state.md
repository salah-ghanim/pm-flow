# persona-cards section PM state

## Current task

- None. T1–T4 are complete; T4 was accepted in cycle 004 (GO). Every brief
  acceptance ID has evidence below and every carried item is closed.

## Completed tasks and evidence

- T4 — closeout. Acceptance IDs A7, plus the brief deliverable "cards for the
  packaged personas" and A1/A5 re-observed against shipped cards rather than
  fixtures. Delivered in `template/.agentic/pm_flow/cards/**`,
  `template/.agentic/pm_flow/catalog.py` and `tests/persona_cards_test.sh`;
  `git status --short` in the developer worktree lists exactly six new
  `<role>.card.json` files plus those two modified files, so `store.py`,
  `compare.py`, `telemetry.py`, `FORBIDDEN_KEYS` and
  `src/pm_flow/persona_card.py` are untouched.
  - A7, both suites under both interpreters, all four runs by the reviewer
    against the developer worktree. `zsh tests/persona_cards_test.sh` exit 0
    with `.venv/bin/python3` first on PATH and exit 0 with it removed
    (`/opt/homebrew/bin/python3`), 18 `PASS:` lines each.
    `zsh tests/pm_flow_test.sh` exit 0 under both, ten `PASS:` lines each
    (`summary venv_on=0 venv_off=0`).
  - Packaged cards, end to end. A real
    `python3 <worktree>/template/.agentic/pm_flow/catalog.py --db <fresh> sync
    --flow <engine> --engine <engine>` printed `synced 6 personas, 7 bindings,
    14 rules, 7 seats, 8 edges`. `persona show maintenance_engineer` and
    `persona show consultant` each printed the authorship notice, then
    `author: unverified claim: pm-flow contributors`, that role's own `purpose`
    and both of its skills as JSON, and `version: 1.0.0`. `persona list` showed
    all six roles on one row each under `AUTHOR (CLAIMED)`.
  - A1 re-observed on shipped cards. `SELECT COUNT(*)` on `attempts` and
    `spans` after both `persona show` calls: `attempts: 0 spans: 0` — no
    dispatch. The suite additionally asserts equal before/after counts.
  - The six cards are role-specific, checked against `roles/*.md` line by line
    rather than by file existence: the 10x developer's card is about rescuing a
    failed section by replacing its diagnosed assumption, the maintenance
    engineer's about repairing a harness without changing the deliverable or
    bypassing a gate, the consultant's about diagnosing without implementing,
    the CPO's about portfolio governance and treating handoffs as claims. No
    two `purpose` strings match; the suite asserts six distinct purposes.
  - Cards reach an already-synced store. Reviewer hand-run: sync an engine copy
    with `cards/pm.card.json` removed, restore the card, sync again — `pm` keeps
    row id 6 and hash `161a7945ab6d`, gains `metadata.card`, and takes
    `author: unverified claim: pm-flow contributors` and `version: 1.0.0`.
  - `cards/` is not scanned. Base rows are exactly the six role keys and no
    card among them carries `reviewer.card.json`'s `name`. The assignment asked
    for the reviewer *author* instead; that assertion is not discriminating,
    because `reviewer.card.json` carries the same
    `unverified claim: pm-flow contributors` author every shipped card must
    carry. The developer said so and substituted the name check — accepted.
  - Fail closed before any write. Reviewer hand-run against an engine copy with
    `skills[0].endpoint` added to `pm.card.json`: exit 1, `sync: card field
    "endpoint" is not allowed on a persona`, `card field path:
    skills[0].endpoint`, `card file: cards/pm.card.json`, and every one of the
    eleven `sync`-written tables at zero rows.
  - Carried items closed. `cardless_persona_list_rows` is gone and one identity
    query survives; `cmd_persona_export` frames a `PersonaCardError` as
    `persona export: persona card is missing required field "purpose"` with no
    traceback; the `assert set(entry).issubset(...)` guard is a real `PackError`
    check; the suite asserts `specVersion`/`sourceUrl`/`retrievedOn` instead of
    the literal `"Transcribed"`; the schema's `acquisition` now gives the
    structural reason and no other schema field moved.
  - Regressions. `sections/persona-packs/cycles/011/acceptance.sh` exit 0
    (`assertions_exit=0`) and `regressions.sh` exit 0 (`cycle_008/009/010_exit=0`),
    both run by the reviewer from the developer worktree, so `assertions.py:188`'s
    "list omits H1" survives the `AUTHOR (CLAIMED)` header and the collapsed
    query. Their own internal mutants still fail
    (`mutant_b/c/d_assertions_exit=1`), so the harness is still discriminating.
  - All four required mutations reproduced by the reviewer on throwaway copies
    under `$TMPDIR`; the tree under review was never edited. (1) `register_clis`
    moved back above the pre-pass — the same refused sync leaves `clis: 3`
    instead of an all-zero store, so validation really precedes the first write.
    (2) the card write reverted to leaving `upsert_persona`'s found row alone —
    the `pm` row is still present with id 6 but `has metadata.card: False` and
    `author: None`, failing on the card and not on a missing row. (3) a shipped
    card's `provenance.origin` stripped of `unverified claim: ` — `sync` exits 1
    with `provenance.origin must be labelled with "unverified claim:"` and
    `card file: cards/pm.card.json`. (4) `cmd_persona_list` reverted to key-only
    grouping — suite exit 1 at `persona list identity rows: expected 2 reviewer
    rows, got 1`, so the surviving query is the identity one. `md5 -q` of
    `catalog.py` after every mutation matched the pre-mutation copy
    (`45bc386d652e54afcbda9d5d9f7d15e0`).
  - The hermeticity pin, which the developer could not demonstrate. With the
    venv `python3` first on PATH, `PYTHONPATH=<worktree>/src python3 -c 'import
    pm_flow.persona_card'` resolves to the worktree's file, not the venv's
    editable install of the main checkout. Decisive check: on a copy of the
    worktree with `url` removed from that copy's `FORBIDDEN_CARD_KEYS`, the
    suite exits 1 (`AssertionError: ('url', 'card field "url" is not part of the
    persona vocabulary', …)`) under the venv interpreter — so the tree under
    test is what gets validated. The main checkout's `persona_card.py` was never
    edited; its md5 is unchanged (`ebe8d7e8156701a132f74032a686d79a`) and equal
    to the worktree's, which is the condition that hid the T3 skew.

- T3 — identity across projects and in comparisons. Acceptance IDs A3, A4, plus
  A1 re-observed against a store with real attempts. Delivered in
  `src/pm_flow/persona_card.py`, `template/.agentic/pm_flow/catalog.py` and
  `tests/persona_cards_test.sh`; `git diff --stat HEAD` in the developer
  worktree lists exactly those three paths, and the persona-packs harness's own
  guard independently printed the same three, so `compare.py`, `telemetry.py`,
  `store.py` and `FORBIDDEN_KEYS` are untouched.
  - `zsh tests/persona_cards_test.sh` re-run by the reviewer against the
    developer worktree — exit 0, every A3/A4/A1 assertion passing, when
    `python3` is not the repo venv's. Under the venv's `python3` the same tree
    exits 1 on the carried-debt diagnostic only; cause and fix are recorded
    under `Carried into later tasks` and in the workplan under T4.
  - A3, listing and addressing. Two packs each install a `reviewer` with a
    different card author; `persona list` prints two `reviewer` rows carrying
    `unverified claim: Alice Example` and `unverified claim: Bob Example`, and
    the uncarded `plain-persona` still occupies exactly one row.
    `persona show reviewer` exits non-zero naming both candidates and pointing
    at `--author`; `--author 'Alice Example'` (unlabelled) and
    `--author 'unverified claim: Bob Example'` (labelled) each print that
    author's card and never the other's. `persona swap` behaves the same way on
    a real seat, and `persona export` refuses the ambiguous key before creating
    the output directory.
  - A3, comparison. A real two-arm `compare report` over two topologies in one
    project store, driven by real ticks against `tests/fixtures/stub_success.zsh`
    installed as `claude`. The test reads each arm's base `(key, content_hash)`
    out of `attempts.persona_stack` and resolves each through `catalog.py`:
    `resolved=reviewer|fbd35c7e…|unverified claim: Alice Example|1.4.0` and
    `resolved=reviewer|57069211…|unverified claim: Bob Example|2.7.0` — same
    key, different hash, author and version. The report's own line reads
    `pm=reviewer` on both arms, asserted rather than implied, so the
    `arm_personas` gap is evidenced.
  - A1 re-observed. `SELECT COUNT(*)` on `attempts` and `spans` against that
    compare store: `2 4` before `persona show` and `2 4` after. Non-zero and
    equal, which is what cycle 002's `0`/`0` could not show.
  - A4. `persona export reviewer --author 'Alice Example'` from store A, then
    `persona add` of that directory into store B, with no hand-editing:
    `metadata.card` compared field by field with top-level and per-skill
    set-equality guards, skill order asserted by `id` sequence, and
    `content_hash` identical across the two stores. An uncarded persona exports
    with `tags` present and no `card` entry.
  - Carried debt closed. `forbidden_card_field_path` is gone from `catalog.py`;
    `_reject_forbidden_fields` attaches the child path to `PersonaCardError` and
    `read_pack` reads it, with the contract message byte-identical. The
    `persona_card(raw_metadata)` accessor is renamed `stored_persona_card`, so
    it no longer collides with the module `read_pack` binds. `persona show`
    prints `tags:` in both branches above the card block, so the two arms of A3
    compare like for like.
  - Regressions. `sections/persona-packs/cycles/011/regressions.sh` exit 0
    (`cycle_008/009/010_exit=0`) and `acceptance.sh` exit 0
    (`assertions_exit=0`), both run by the reviewer with the developer worktree
    as `git rev-parse --show-toplevel`, so `assertions.py:188`'s "list omits H1"
    still holds with the new `AUTHOR` column in place. `zsh tests/pm_flow_test.sh`
    exit 0, ten `PASS:` lines.
  - All four required mutations reproduced by the reviewer on throwaway copies
    under `$TMPDIR`, so no implementation source was edited in place. (1)
    grouping reverted to key-only in `persona list` — exit 1, `persona list
    identity rows: expected 2 reviewer rows, got 1`. (2) the ambiguity refusal
    replaced by the newest row in `persona show` — exit 1, `ambiguous persona
    show returned the wrong card:` followed by Bob's full card, so the assertion
    binds the returned card and not merely a missing message. (3) `persona
    export` dropping `provenance` — exit 1, `AssertionError: round-trip
    top-level card fields changed`, so the comparison is not shallow. (4)
    `_reject_forbidden_fields` attaching the parent path — exit 1, `forbidden
    endpoint refusal omitted its field path: … card field path: skills[0]`, so
    the single walk is what produces the diagnostic. `md5 -q` of both source
    files in the worktree after all mutation runs matched the pre-run values
    (`b118bd4d214988aba6a1bc92b2324075`,
    `ebe8d7e8156701a132f74032a686d79a`).

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
- Card identity is `(key, card author)`, and the grouping key in SQL is
  `COALESCE(json_extract(p.metadata,'$.card.author'), '')` — never `p.author`,
  which holds the pack author on an uncarded row. Every uncarded persona
  therefore groups exactly as it does today, which is what keeps A5 and
  `persona-packs` cycle 011's "list omits H1" assertion true.
- A bare key that resolves to two card identities is refused by `persona show`
  and `persona swap` rather than answered with the newest row; `--author`
  selects. A key with one identity is unchanged, so no existing behaviour
  moves.
- A4's round trip goes through a real exported pack, not a hand-built fixture.
  `content_hash` is `store.content_hash(key, layer, body)` (`catalog.py:120`) —
  body only — so an exported pack reinstalls under the identical hash and the
  comparison is row against row.
- The comparison report's printed persona column stays `role=key` this section.
  `compare.py:arm_personas` and `telemetry.py`'s stack writer are outside owned
  paths. What is delivered is the resolution from the `(key, content_hash)` the
  stack already records to the card, and the one-line `arm_personas` gap is
  recorded for whichever section owns `compare.py`.
- The packaged personas are `template/.agentic/pm_flow/roles/*.md`, and they
  reach the store through `sync` (`catalog.py:698,766`), never through
  `persona add`. So a packaged card is `cards/<role>.card.json` resolved against
  `engine_dir`, attached to the base layer row only, written in place with the
  `adopt_persona` shape (same id, `author`/`version`/`metadata.card` refreshed,
  body and hash untouched) because `upsert_persona` returns a found row without
  touching provenance. Validation is a pre-pass before `sync` writes anything,
  and a bad or unvalidatable packaged card fails `sync` closed — the same rule
  install follows, applied to our own tree.
- Card lookup is strictly by role key, so `cards/reviewer.card.json` — the
  contract example pinned at `tests/persona_cards_test.sh:10`, matching no role
  — stays inert. `cards/` is not a scanned directory.
- The claim label on display is settled: no printed value is rewritten. The
  `persona list` column is headed `AUTHOR (CLAIMED)` and `persona show` prints
  one line stating authorship is an unverified claim. Labelling a stored-bare
  pack author at display time would make `persona list` disagree with the store
  and with what `--author` matches; stripping a card's stored label is
  forbidden outright.
- How `catalog.py` reaches `persona_card` is settled, not left to T2's
  judgement: try `import pm_flow.persona_card`, then
  `Path(__file__).resolve().parent.parent / "persona_card.py"` (wheel:
  `pm_flow/engine/catalog.py` beside `pm_flow/persona_card.py`), then
  `parents[3] / "src" / "pm_flow" / "persona_card.py"` (checkout). If none
  resolve, a pack carrying a `card` is refused naming the missing module and an
  uncarded pack is untouched — fail closed, because a card installed unvalidated
  is exactly brief A2's failure.

## Carried into later tasks

- None. Every item carried from T2 and T3 landed in cycle 004 and its evidence
  is under T4 above: the suite's hermeticity pin, the collapsed `persona list`
  query, the widened `cmd_persona_export` except and its real manifest check,
  the `specVersion`/`sourceUrl`/`retrievedOn` assertion, and the schema's
  `acquisition` provenance correction.

## Facts worth keeping past this section

- The nested forbidden-field case is the only one uniquely produced by the
  card walk; a top-level `url` is also caught by the vocabulary allowlist with
  a different message (`card field "url" is not part of the persona
  vocabulary`). Any future forbidden-field assertion must keep a nested case.
- The suite pins `PYTHONPATH="$ROOT/src"` so the tree under test wins over the
  venv's editable install, and passes `-u PYTHONPATH` to the three `python3 -S`
  isolated invocations so the fail-closed cases still see no module. Delete
  either half and a worktree review silently validates the main checkout.
- `load_persona_card_module`'s wheel-layout branch
  (`Path(__file__).resolve().parent.parent / "persona_card.py"`) is no longer
  exercised by the suite: cycle 004 deleted the `/bin/cp` that staged that
  layout, which the assignment permitted. The checkout branch and the
  fail-closed branch are both still covered.

## Blockers

- None. `persona-packs` is complete: its handoff records A1–A5 with commits
  (`aaaf4b9`, `dc38523`, `e2eb511`, `2038254`, `39a1fe4`) and ten `PASS:` on
  `tests/pm_flow_test.sh`.

## Housekeeping for the driver

- Reviewer scaffolding accumulating in the main checkout, all untracked and
  none of it section state — drop rather than commit: from cycle 001,
  `sections/persona-cards/review_probe.sh` and
  `sections/persona-cards/.review_backup/`; from cycle 002,
  `sections/persona-cards/review_002_{run,probe,mutations,mut1_tail,suite}.sh`;
  from cycle 003, `sections/persona-cards/cycles/003/probe_*.sh` (six files) and
  `sections/persona-cards/scope_005_probe.sh` if it is still present. Cycles 002
  and 003 both mutated isolated copies under `$TMPDIR`, so no `.review_backup/`
  of implementation source was needed.
- From cycle 004, five reviewer scripts under
  `sections/persona-cards/cycles/004/` — `review_no_venv_cards.zsh`,
  `review_pmflow_both.zsh`, `review_pp011.zsh`, `review_mutations.zsh`,
  `review_mutations2.zsh`, `review_show.zsh`. Scaffolding, not section state;
  drop rather than commit.
- Running `sections/persona-packs/cycles/011/acceptance.sh` rewrites that
  cycle's own `transcripts/`, `prompt-v1.txt` and `prompt-v2.txt` in the main
  checkout (`acceptance.sh:348-352`). Cycle 004's reviewer avoided that
  entirely by copying `acceptance.sh` and `assertions.py` to a scratch dir so
  `SCRIPT_DIR` pointed there; `git status` on
  `.agentic/pm_flow/pm-agent/sections/persona-packs` was empty afterwards. Use
  that shape, not a plain in-place run, whenever behaviour has changed.
- `.last_error.txt` holds three `claude hit a usage limit; pausing 1800s`
  lines from the dispatch after cycle 001. A quarantine, not a section failure;
  no evidence in this file depends on it.

## Probes run scoping cycle 004

- `ls template/.agentic/pm_flow/cards/` at scope time — only
  `a2a-agent-skill.schema.json` and `reviewer.card.json`, which is what made the
  brief's "cards for the packaged personas" deliverable T4's work. Cycle 004
  added the six `<role>.card.json` files; the deliverable is met.
- `ls template/.agentic/pm_flow/roles/` — `10x_developer.md`, `consultant.md`,
  `cpo.md`, `developer.md`, `maintenance_engineer.md`, `pm.md`. There is no
  `reviewer.md`, so `reviewer.card.json` is a contract example, not a packaged
  persona's card.
- `catalog.py:653-695,753-775` — `sync` walks `config.roles`, reads the base
  layer from `engine_dir/roles/<role>.md` and `upsert_persona`s it under the
  bare role key. Packaged personas never go through `persona add`, so T2's
  install-time card path does not reach them; `sync` is the only hook.
- `catalog.py:152-171` — `upsert_persona` returns the found row's id on a digest
  match and touches nothing else, so attaching a card to an already-synced store
  needs an explicit in-place write.
- `catalog.py:1285-1326` + `1256-1263` — `adopt_persona` already refreshes
  `author`, `version` and `metadata` in place on an identical-content row via
  `persona_pack_metadata(pack, card, existing)`. That is the shape to reuse; it
  is also why an in-place card write introduces no new rule about versions.
- `driver.zsh:735` — `catalog.py sync` runs at every run start. That is the
  blast radius of a `sync` change and the reason packaged-card validation is a
  pre-pass before any write.
- `sections/persona-packs/cycles/011/assertions.py:79-95,181-188` — every
  `persona list` assertion picks its line with `startswith("update-manager")`
  and then matches substrings, so a changed header line is safe. Re-run it
  anyway; it is the only external reader of that output.
- `tests/persona_cards_test.sh:9-16,203-215,639-654` — `ROOT="${0:A:h:h}"`, and
  line 16 already uses `PYTHONPATH="$ROOT/src"` for the direct `persona_card`
  import, so the hermeticity fix is the existing idiom applied to
  `run_catalog_db`. `python3 -S` skips `site` (and so the editable `.pth`) but
  still honours `PYTHONPATH`, which is why `-u PYTHONPATH` is needed at
  `:639-654`.
- `catalog.py:998-1021`, `1743-1774`, `1904-1928` re-read — the module loader,
  the two list queries and the export `except` are all where cycle 003's review
  said they were.

## Probes run reviewing cycle 003

- `python3` on PATH in this repo is `.venv/bin/python3`, and
  `from pm_flow import persona_card` there resolves to
  `/Users/salah/code/personal/pm-flow/src/pm_flow/persona_card.py` — the main
  checkout, not the worktree under review. That file carries no
  `error.path = child_path`, which is exactly why the worktree's suite loses the
  `card field path:` line under the venv interpreter and keeps it under
  `/opt/homebrew/bin/python3`. Same tree, two exits. Any future review of a
  change to `src/pm_flow/**` hits this.
- `PYTHONPATH="$ROOT/src"` alone is not the fix: it also reaches the two
  `python3 -S` invocations at `:639-654`, which then find the module and the
  fail-closed assertion silently stops holding. The fix needs `-u PYTHONPATH`
  there too.
- `git rev-parse --show-toplevel` from inside a worktree returns the worktree,
  so `sections/persona-packs/cycles/011/{acceptance,regressions}.sh` can be run
  against a developer worktree by `cd`-ing there first; `.agentic/` is not
  tracked, so the harness itself only exists in the main checkout.
- `grep` for `swap_seat_persona|newest_persona|forbidden_card_field_path` across
  `template/`, `src/` and `tests/` — every caller of the two changed signatures
  is inside `catalog.py`, and `forbidden_card_field_path` has no survivors.
- `SWAP_OVERRIDE_KEY` / `layer_overrides` have exactly three readers, all in
  `catalog.py` (`:453`, `:817`, and `override_persona`). The new
  `{"key", "author"}` override value therefore reaches nothing outside the file,
  and `layer_overrides` still accepts the legacy bare-string form, so stores
  written before this cycle keep swapping.

## Probes run scoping cycle 003

- `catalog.py:1692-1699` — `persona list` collapses on
  `MAX(id) … WHERE b.key = p.key` and selects no author column at all. Two
  same-key personas show as one row today; A3's listing half is real work, not
  a formatting change.
- `catalog.py:329-337`, `catalog.py:497` — `swap_seat_persona` resolves a bare
  key through `newest_persona`, which is `ORDER BY id DESC LIMIT 1`. With two
  card identities under one key an operator cannot choose which one a seat
  runs, and gets no warning.
- `catalog.py:120` — `content_hash` is `store.content_hash(key, layer, body)`.
  Body only: not the file text, not the frontmatter. An exported pack carrying
  the stored body reinstalls under the identical hash.
- `store.py:99` — `personas` is `UNIQUE (key, content_hash)`, so the pair the
  persona stack records addresses exactly one row and one card.
- `telemetry.py:563-580` — `persona_stack` is written as
  `{key, layer, content_hash}` per layer, from `seat_personas`.
  `compare.py:509-525` (`arm_personas`) reads it and prints `role=key` for the
  `base` layer only. Both files are outside owned paths.
- `compare.py:660-666` — `compare report <run-a> <run-b>` needs only two runs
  under two topologies in one project store; it drives no ticks itself.
- `tests/topology_compare_test.sh:159-181` — real compare arms run against
  `tests/fixtures/stub_success.zsh` installed as `claude` on PATH. That is the
  fixture pattern for T3's two-arm report, and it produces the store with real
  `attempts` that A1's no-dispatch counts need.
- `sections/persona-packs/cycles/011/assertions.py:79-95,181-188` — the only
  assertions anywhere that parse `persona list` output. They select a line by
  substring and assert the superseded `H1` is absent, so extra columns are
  safe but one-row-per-key must survive for uncarded personas.
- `grep` for `persona list` across `tests/` — only
  `tests/persona_cards_test.sh:285-292`, this section's own file.
- `persona_card.py:35-49` re-read — `child_path` is still computed after the
  forbidden-key check, so attaching it to the error means computing it first.

## Probes run in cycle 002 scope

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

- None. The workplan is exhausted: T1 (cycle 001), T2 (002), T3 (003) and T4
  (004) are all complete, and A1–A7 plus the packaged-cards deliverable have
  evidence above. The one thing the brief names that this section did not
  deliver is the comparison report's printed persona column — `compare.py`'s
  `arm_personas` renders `role=key` and both it and `telemetry.py` are outside
  owned paths. The resolution from the recorded `(key, content_hash)` to the
  card is delivered and proved; the one-line render change belongs to whichever
  section owns `compare.py`. Same for the `pm-flow persona` wrapper the brief's
  scenarios spell, which lives in `pm_flow.sh` / `src/pm_flow/cli.py`.
