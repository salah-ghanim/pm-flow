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

- Status: complete (cycle 003, GO_WITH_CHANGES).
- Outcome: export from A and install into B is lossless; two same-name
  different-author personas list distinctly and are separately addressable;
  the card each arm of a `compare --report` actually ran is resolvable from
  the rows the report reads.
- Paths: `src/pm_flow/persona_card.py`, `template/.agentic/pm_flow/catalog.py`,
  `tests/persona_cards_test.sh`.
- Acceptance IDs: A3, A4.
- Depends on: T2.

### The identity rule, settled

- Card identity is `(key, card author)`; an uncarded persona's identity is
  `(key, no card)`. Group in SQL on
  `COALESCE(json_extract(p.metadata,'$.card.author'), '')`, not on
  `p.author`. `p.author` holds the *pack* author for an uncarded row, so
  grouping on it would split two versions of one uncarded persona the moment a
  pack changed hands — and `sections/persona-packs/cycles/011/assertions.py:188`
  asserts `persona list` omits the superseded `H1`. The `COALESCE`-to-`''`
  form keeps every uncarded persona grouped exactly as it is today, which is
  what protects A5 and that harness.
- `persona list` (`catalog.py:1692-1725`) currently collapses on
  `MAX(id) … WHERE b.key = p.key`, so two same-key personas show as one row and
  the table has no author column at all. One row per identity, newest version
  within it, plus an `AUTHOR` column printed as stored — claim label intact.
- `persona show` (`catalog.py:1728`) and `persona swap`
  (`swap_seat_persona` → `newest_persona`, `catalog.py:329-337`) both resolve a
  bare key to the newest row. With two card identities under one key that is a
  silent wrong answer, so both take `--author` and refuse an ambiguous key by
  naming the candidates. A key with one identity resolves exactly as it does
  now, so no existing behaviour moves and A1's evidence stands.

### Export, and why the round trip is lossless by construction

- `persona export <key> [--author A] --out <dir>` writes an installable pack:
  `persona-pack.json`, `personas/<key>.md` carrying the stored `body` verbatim,
  and `cards/<key>.card.json` from `persona_card.export`, which validates on the
  way out. An uncarded persona exports without a `card` entry.
- `content_hash` is `store.content_hash(key, layer, body)` (`catalog.py:120`) —
  body only, not the file text and not the frontmatter. So the exported pack
  reinstalls into project B under the identical hash, and A4's "identical in
  every field" is a comparison of two store rows rather than of a row against
  the fixture that produced it.

### The compare half of A3, and the gap it leaves

- `compare.py:arm_personas` (`compare.py:509-525`) prints `role=key` from
  `attempts.persona_stack`, and `telemetry.py:573-580` writes that stack as
  `{key, layer, content_hash}`. Neither file is in this section's owned paths,
  so the report's printed column cannot be made to say the card here. The brief
  lists `topology-compare`'s report persona field under *Interfaces consumed*,
  which is the same reading.
- What is reachable is the whole substance: `personas` is
  `UNIQUE (key, content_hash)` (`store.py:99`), so the `(key, content_hash)` the
  stack already records addresses exactly one row and therefore exactly one
  card. T3 delivers that resolution in `catalog.py` and proves on a real
  two-arm report that the two arms resolve to different cards. Naming the card
  in the column itself is a one-line change to `arm_personas` for whichever
  section owns `compare.py` — recorded the same way as the missing
  `pm_flow.sh persona` wrapper, not silently dropped.

### Carried from T2, now that `persona_card.py` is writable

- Attach the rejected field's path to `PersonaCardError` in
  `_reject_forbidden_fields` (`persona_card.py:35-49`) — the message itself is
  unchanged, because brief A2 pins it — and delete
  `catalog.py:forbidden_card_field_path` (`catalog.py:953-971`), which
  re-implements the same depth-first walk only to produce the install
  diagnostic. Two walks that must agree on which field was refused is the drift
  risk.
- Rename the `persona_card(raw_metadata)` accessor (`catalog.py:1228`); it
  collides by name with the module object `read_pack` binds locally
  (`catalog.py:1038`).
- Settle `persona show`'s shape before A3 compares two personas side by side:
  it prints `tags:` for an uncarded persona and omits it for a carded one.
- Take A1's no-dispatch counts against the store with real attempts that this
  task's compare fixture produces, rather than the `0`/`0` T2 could observe.

### Validation

- `zsh tests/persona_cards_test.sh`: two-project export/install round trip
  compared field by field with set-equality guards; a same-key
  different-author matrix through `persona list`, `show` and `swap`; and a real
  two-arm `compare report` whose arms resolve to distinct cards.
- The two-arm fixture reuses proven machinery rather than seeding rows:
  `tests/topology_compare_test.sh:159-181` installs `tests/fixtures/stub_success.zsh`
  as the `claude` on PATH and drives real ticks, and
  `sections/persona-packs/cycles/011/acceptance.sh` does the same for a single
  tick. `compare report <run-a> <run-b>` (`compare.py:660-666`) needs only two
  runs under two topologies in one project store.

## Task T4 — Closeout

- Status: complete (cycle 004, GO).
- Outcome: the personas this repository actually ships carry cards and
  `persona show <role>` prints them from a real synced store; both suites pass,
  and the suite validates the tree it is run from rather than whichever
  `pm_flow.persona_card` happens to be importable.
- Paths: `template/.agentic/pm_flow/cards/**`,
  `template/.agentic/pm_flow/catalog.py`, `tests/persona_cards_test.sh`.
- Reuse: T1–T3; `adopt_persona` (`catalog.py:1285`) and
  `persona_pack_metadata` (`catalog.py:1256`) for the in-place card write;
  `load_persona_card_module` (`catalog.py:998`); `read_pack`'s validate-before-
  any-write shape (`catalog.py:1024`).
- Acceptance IDs: A7, plus the brief deliverable "cards for the packaged
  personas", and A1/A5 re-observed against shipped cards rather than fixtures.
- Validation: `zsh tests/persona_cards_test.sh` and `zsh tests/pm_flow_test.sh`
  exit 0, run twice: once with the repo venv's `python3` on PATH and once
  without it. Both must agree. Plus a real `catalog.py sync` of the template
  engine directory followed by `persona show pm`, printing the packaged card.
- Depends on: T3.

### The packaged cards, and where they attach

- The packaged personas are `template/.agentic/pm_flow/roles/*.md` —
  `10x_developer`, `consultant`, `cpo`, `developer`, `maintenance_engineer`,
  `pm`. They are not installed by `persona add`: `sync` (`catalog.py:698`)
  walks `config.roles`, calls `read_persona_layers` (`catalog.py:653`) and
  `upsert_persona` (`catalog.py:766`) per layer, and the base layer's row is
  keyed by the bare role name. So `cards/<role>.card.json` is resolved against
  `engine_dir`, which `sync` already takes, and attaches to the base layer
  only. Domain (`<domain>/<role>`) and style (`<project>/<role>`) layers are
  not packaged and take no card.
- `upsert_persona` returns the found row's id without touching provenance, so a
  store synced before cards existed would stay uncarded forever. The card write
  is therefore the `adopt_persona` shape: same row id, `author`/`version`/
  `metadata.card` refreshed in place through `persona_pack_metadata`, body and
  `content_hash` untouched. In-place provenance refresh on an identical-content
  row is already the settled behaviour for path→Git adoption, so this
  introduces no new rule about what a version is.
- Validation is a pre-pass, before `sync` writes anything, mirroring `read_pack`
  validating a whole pack before the store is opened. A packaged card that is
  malformed, carries a forbidden field, or cannot be validated because the card
  module will not load makes `sync` exit non-zero naming the file and the field.
  `driver.zsh:735` runs `sync` at every run start, so this stops every tick —
  which is right for a defect in a card this repository ships, and is the same
  fail-closed rule install already follows. Skipping an unvalidated packaged
  card is the one outcome that reproduces brief A2's failure inside our own
  tree.
- `cards/reviewer.card.json` matches no role and stays the contract example the
  suite pins at `tests/persona_cards_test.sh:10`. Lookup is strictly by role
  key, so it is inert; the suite asserts it reaches no persona row, so nobody
  later reads `cards/` as a scanned directory.

### The claim label on display, settled

- `persona_card` enforces `CLAIM_PREFIX` on a card's stored `author`
  (cycle 001, mutation D), so a carded row prints `unverified claim: X` and an
  uncarded row prints a bare pack author. Beside each other the bare one reads
  as the verified case — brief non-goal 2.
- Settled: do not rewrite either value on display. `persona list` heads the
  column `AUTHOR (CLAIMED)`, and `persona show` prints one line above the
  identity block saying authorship is a claim from the persona's own source and
  nothing here verifies it. Values printed stay exactly as stored, so what
  `--author` matches is still what is printed, and `persona list` and
  `persona show` cannot disagree about what the store holds. Applying the label
  at display time to a value stored without one would break both.
- `sections/persona-packs/cycles/011/assertions.py:79-95,181-188` selects its
  lines with `startswith("<key>")`, so a changed header line is safe — prove it
  by re-running the harness, not by reading it.

### Carried from T3 — the suite is not hermetic

- `run_catalog` (`tests/persona_cards_test.sh:207-215`) invokes plain `python3`
  and unsets only `PM_FLOW_*`. `load_persona_card_module`
  (`catalog.py:998-1021`) tries `import pm_flow.persona_card` first, so under
  the repo's own venv — an editable install rooted at the *main checkout* —
  a worktree's `catalog.py` validates the main checkout's `persona_card.py`.
  Every T3 assertion that depends on a `persona_card.py` change therefore
  passes or fails on which interpreter is first on PATH, not on the tree under
  review. Observed at cycle 003 review: exit 1 under the venv `python3`, exit 0
  under `/opt/homebrew/bin/python3`, same worktree.
- Fix inside owned paths: give `run_catalog`/`run_catalog_db` an explicit
  `PYTHONPATH="$ROOT/src"` so the tree under test wins, and add `-u PYTHONPATH`
  to the two `python3 -S` isolated invocations (`:639-654`) so the fail-closed
  case still sees no module. The line-474 copy of `persona_card.py` into the
  wheel-layout position is dead as long as the import branch wins; keep it only
  if the wheel layout is asserted separately.
- This is a review-environment trap, not a shipping defect: on merge the two
  copies of `persona_card.py` become one file and the skew disappears. It will
  recur for every future cycle that edits `src/pm_flow/**` and is reviewed in a
  worktree, which is every cycle.

### Carried from T3 — the three shape items and the provenance line

- `cmd_persona_list` (`catalog.py:1754-1774`) keeps two queries behind a
  `has_cards` probe, but `COALESCE(json_extract(…),'')` collapses to the legacy
  key grouping on an all-uncarded store, so the branches cannot differ. Collapse
  to the identity query and delete `cardless_persona_list_rows`
  (`catalog.py:1743`); `persona-packs` cycle 011 is the cardless case and must
  still pass on the surviving query.
- `cmd_persona_export` (`catalog.py:1925`) catches `(OSError, PackError)` but
  `card_module.export` raises `PersonaCardError`, a `ValueError`. Widen it so a
  failure is a `persona export: …` line rather than a traceback beside a
  half-written directory, and replace the
  `assert set(entry).issubset(PERSONA_ENTRY_KEYS)` developer check
  (`catalog.py:1910`) — an `assert` in a shipped path vanishes under `-O`.
- `tests/persona_cards_test.sh:89` asserts the literal `"Transcribed"` in the
  schema's `acquisition` header, coupling the test to one wording. Assert
  `specVersion`, `sourceUrl` and `retrievedOn` are present instead. Then reword
  the header itself (`cards/a2a-agent-skill.schema.json:10`): it says fetch.sh
  failed, but fetch.sh exited 0 at review time. The real, structural reason is
  that `fetch.sh` returns model-extracted text under an untrusted-source marker
  and never a byte-exact document. A provenance correction only — the schema's
  fields are settled and are not edited to suit a card.
- Cycle 001's mutation A showed a top-level `url` is caught by the card
  vocabulary allowlist even with `FORBIDDEN_CARD_KEYS` emptied of it. Only the
  nested path is uniquely the walk's, so keep the nested case in every
  forbidden-field assertion.

## Integration and end-to-end validation

- T3 is where scenario 3 is observable end to end, up to the ownership
  boundary recorded under T3: two same-name different-author personas install,
  list, show and swap distinctly, and a real two-arm `compare report` resolves
  to a different card per arm. The report's own `personas` column still prints
  `role=key`, because `compare.py` is not an owned path.
- T4 is where scenario 1 stops resting on a fixture: the personas this
  repository ships carry cards, a real `sync` attaches them, and
  `persona show pm` prints author, purpose, skills and version with no dispatch
  recorded.
- Both suites were re-run on merged `main` at cycle 005 scope, so the section's
  A7 evidence is against the tree that ships and not only against the developer
  worktree each cycle was reviewed in.

## Risks and rollback

- Presenting provenance as verified is the failure to avoid; the label is an
  acceptance requirement. Cards are optional, so disabling parsing leaves
  every persona working.
- The card cannot reach the comparison report's printed column from inside
  this section. `compare.py:arm_personas` renders `role=key` and
  `telemetry.py` writes the stack it reads; both are outside owned paths. The
  section delivers the resolution and records the one-line gap. This is an
  ownership boundary, not an external dependency: nothing waits on anyone.
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
| A7 | T4 | Both suites exit 0 under two interpreters |
| A1, A5 re-observed | T4 | Shipped cards on real synced role rows; uncarded layers unchanged |
