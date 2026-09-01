# boundary-schema section PM state

## Current task

- None. T1-T4 are all done, cycle 004 is merged (`50ec3b2`), and all five brief
  acceptance criteria are met on merged `main` — re-observed by the PM at cycle 005
  scoping rather than inherited from the cycle-004 review. The section is complete.

## Verified complete on merged main, cycle 005

Probes `sections/boundary-schema/probe_complete_005.zsh` (with
`probe_005_check.py`) and `probe_005_refuse.zsh`; outputs under
`sections/boundary-schema/probe_005/`. Run at head `50ec3b2` with no tracked
modification outside `.agentic/`.

- A1, the installed verb, no env override. `pm-flow export --json` typed in the
  repository exits 0 — the cycle-004 `unknown command: export` is gone now that the
  merge has landed. `export keys=22 dirs=22 identical=True` against the directory
  listing, `json-tool-exit=0`, `stable=YES` (`cmp` of two consecutive runs),
  `git-status-identical=YES`. Top-level keys are `['project', 'sections']`; each
  section carries `key, name, status, priority, owned_paths, dependencies,
  acceptance, handoff, summary, updated_at`.
- A1, spot-checked on a different section than cycle 004 used — this one.
  `boundary-schema`: `status active` = `status.txt`, `priority must-have` = line 1
  of `priority.txt`, `owned_paths` equal to the seven lines of `owned_paths.txt`,
  `dependencies []`, `acceptance` the five bare IDs `A1`-`A5` all `met`, and all six
  handoff fields present verbatim in `handoff.md` (plus `word_count`/`byte_count`).
- A2, end to end on a copy of the live project (`probe_005_refuse.zsh`): the copy
  exports clean (`sections=22 project=pm-agent`), then deleting `## What is
  unproven` from `otel-semconv/handoff.md` makes the same command exit 1 with
  `stdout bytes=0` and `export failed:
  export.sections[otel-semconv].handoff.What is unproven is required` — section and
  field both named. `export.py check --kind handoff` rejects the same file on its
  own (`handoff.What is unproven is required`, exit 1).
- A3, from the suite's own output on main: eleven markdown fixtures each with two
  agreeing verdicts (5 ACCEPT pairs, 6 REJECT pairs), two missing-schema rows
  showing the shell rejects with `cannot load … schema at …` rather than falling
  back, `project export: sections=3 stable=yes fields=fixture-matched`, and
  `handoff title mutation: export=REJECT stdout=empty` — the one-definition check
  now lives inside the suite, so a green suite is the proof.
- A4: `config_valid.json: pm-flow=ACCEPT topology=ACCEPT agent-exec=ACCEPT` (its
  `developer` role is bound to cli `acp`), `config_valid.json:
  store-clis=claude,codex,copilot topology-exit=0`, `config_unknown_cli.json:
  pm-flow=REJECT topology=REJECT agent-exec=REJECT`, and
  `config.schema.json missing: pm-flow=REJECT topology=REJECT agent-exec=REJECT`.
  The enum is still written once, at `config.schema.json:10`.
- A5, on the current checkout: `boundary_schema_test.sh`, `pm_flow_test.sh`,
  `topology_compare_test.sh`, `agent_bindings_test.sh` and
  `template/.agentic/pm_flow/tests/verdict_parser.zsh` (`pass=35 fail=0`) each
  exit 0.
- Live shape of the export, for whoever consumes it: 102 acceptance entries across
  the project, 74 `met` and 28 `open`; five sections emit `acceptance: []` —
  `agents-md`, `green-suite`, `installer`, `packaging`, `worktree-isolation` —
  because their legacy briefs carry no `A<n>` token to derive a state for. Faithful
  to the source; adding IDs belongs to those sections' owners.

## Completed tasks and evidence

- T4 — `pm-flow export --json`, the end-to-end scenario. Acceptance A1, A2, A5.
  Accepted cycle 004.
  - Delivered: `schemas/project_export.schema.json`; `export.py`'s `emit`
    subcommand plus `_resolve_reference`/`SchemaReferenceError`; the `export)` arm
    (`pm_flow.sh:2031`) calling `python3 "$SCRIPT_DIR/export.py" emit "$@"
    "$FLOW_DIR" "$PROJECT_KEY"` and the `usage()` line at `:48`; eight new suite
    cases and four fixture sections under
    `tests/fixtures/boundary_schema/project_export{,_invalid}/`.
  - A1, all 22 live sections. With the engine root pointed at the developer
    checkout and the flow directory at the live project,
    `zsh <checkout>/template/.agentic/pm_flow/pm_flow.sh export --json` exits 0,
    `python3 -m json.tool` parses it, and two consecutive runs are byte-identical.
    `export count = 22 / dir count = 22 / identical = True` against the directory
    listing under `.../pm-agent/sections/`.
  - A1, `otel-semconv` compared field by field against its own files, PM's own
    re-derivation in `review_004_spot.zsh`: `status done`, `priority must-have`
    (line 1 of a two-line `priority.txt`), `owned_paths` the three lines of
    `owned_paths.txt`, `dependencies []`, `acceptance` seven bare IDs `A1`-`A7`,
    and all six handoff fields MATCH the corresponding `## ` sections of
    `handoff.md` character for character (1023/700/335/421/588/164 chars), plus
    `word_count=465 byte_count=3346`.
  - A1, the command writes nothing. `git status --porcelain` on the live repo is
    byte-identical before and after. Stronger, `review_004_nowrite.zsh`: a shasum of
    all 4216 files under a copied flow directory is identical before and after a
    75 082-byte export, so nothing is written that git merely ignores either.
  - A2, three refusal paths, each with an empty stdout (`review_004_a2.zsh`):
    a section whose `handoff.md` lacks `## What is unproven`, injected into a copy
    of the live project, exits 1 with
    `export failed: export.sections[corrupt-handoff].handoff.What is unproven is
    required` — section and field both named;
    `export.py check --kind export project_export_illegal_state.json` exits 1 with
    `export.sections[illegal-state].acceptance[0].state must be one of ['met',
    'open'], got 'unknown'`;
    deleting `schemas/project_export.schema.json` exits 1 with
    `cannot load export schema at <path>`.
  - A2/A3, one-definition proof, PM's own (`review_004_mutation.zsh`): the suite is
    green on a disposable copy, then renaming `unproven`'s `title` in
    `handoff.schema.json` from `What is unproven` to `Loose ends` turns it red
    (exit 1). The suite's own `handoff title mutation` case does the same inside the
    export path. Grep confirms the mechanism rather than the symptom: none of the
    six handoff field names occur in `project_export.schema.json` or in `export.py`,
    and the acceptance-ID pattern is written exactly once, at
    `section_brief.schema.json:81`.
  - A2, the suite asserts values, not key presence. PM's own three reversible
    mutations of `export.py` (`review_004_negcheck.zsh`), each turning the suite
    red: keying acceptance state on the `completed tasks and evidence` heading →
    `AssertionError` on the `freeform` fixture; dropping the
    `Blockers`/`Next eligible task` exclusion → `AssertionError` on `complete`,
    whose `A2` is mentioned only under `Blockers`; keeping blank lines in
    `dependency_handoffs.txt` →
    `export failed: export.sections[empty-dependencies].dependencies[0] must match
    pattern '\S'`.
  - A5: in the developer checkout `boundary_schema_test.sh`,
    `agent_bindings_test.sh`, `pm_flow_test.sh`,
    `template/.agentic/pm_flow/tests/verdict_parser.zsh` (`pass=35 fail=0`) and
    `topology_compare_test.sh` all exit 0.

- T3 — one cli definition across the three config consumers. Acceptance A4, A5.
  Accepted cycle 003.
  - Delivered: `config.schema.json` hoists the seat object into `$defs.seat`, both
    `oneOf` arms `$ref` it, so the cli and difficulty enums are written once;
    `export.py`'s `validate_schema` carries the document root through the recursion
    and resolves local `#/` pointers; `cmd_config` (`pm_flow.sh:504`), the
    `role_binding` block (`agent_exec.sh:163`) and `topology.py`'s new
    `config_enums` (`:86`) all read those two enums and hard-fail with
    `cannot load config schema at <path>: <error>` when the file is missing or
    malformed. `validate_binding` (`topology.py:185`) now asks the schema for
    legality and the registry only for models (`registry.get(cli, [])`);
    `DIFFICULTIES` is gone and `FALLBACK_MODELS` gained `"acp": []`.
  - A4, three consumers agreeing: `zsh tests/boundary_schema_test.sh` exits 0 and
    prints `config_valid.json: pm-flow=ACCEPT topology=ACCEPT agent-exec=ACCEPT`
    (its `developer` role is bound to cli `acp`) and
    `config_unknown_cli.json: pm-flow=REJECT topology=REJECT agent-exec=REJECT`.
    The suite also asserts the checker column and that every rejection names the
    offending cli.
  - A4, with a store present: the suite seeds a `clis` table holding only
    `claude`, `codex`, `copilot` at `<flow>/<key>/runs/pm_flow.db` and prints
    `config_valid.json: store-clis=claude,codex,copilot topology-exit=0`.
    Reproduced by hand in `probe_msgs_003.zsh`:
    `stored_models: {'claude': [...], 'codex': [...], 'copilot': []}` and
    `topology acp exit=0`.
  - A4, definition not duplication: with `schemas/config.schema.json` deleted from
    an engine copy the suite prints
    `config.schema.json missing: pm-flow=REJECT topology=REJECT agent-exec=REJECT`
    and asserts all three outputs contain `cannot load config schema at <path>`.
  - A4, mutation proof, PM's own — `sections/boundary-schema/probe_mutate_003.zsh`,
    four independent single-consumer mutations on a disposable copy, baseline green
    (`mutation_baseline: suite exit=0`):
    removing `acp` from the schema enum → `FAIL: config_valid.json checker verdict`;
    restoring the literal set in `agent_exec.sh` → `FAIL: config_valid.json
    agent-exec verdict`; in `pm_flow.sh` → `FAIL: config_valid.json pm-flow verdict`;
    reverting `topology.py` to `cli not in registry` → `FAIL: config_valid.json
    topology verdict`. All exit 1. Every column therefore invokes a real consumer,
    and the topology one proves the seeded store is genuinely in play — the
    registry-based check rejects `acp` precisely because the store lacks it.
  - Messages unchanged, verified verbatim on the three sites:
    `role 'developer' seat 1 has an unsupported cli: 'unknown'` from both
    `pm_flow.sh:554` and `topology.py:215`, and
    `role {role!r} has an unsupported cli: {cli!r}` at `agent_exec.sh:214`.
  - A5: `boundary_schema_test.sh`, `agent_bindings_test.sh`, `pm_flow_test.sh` and
    `template/.agentic/pm_flow/tests/verdict_parser.zsh` (`pass=35 fail=0`) exit 0
    in the developer worktree. `topology_compare_test.sh` exited 1 at the time,
    from another section's breakage; it has since been fixed and exits 0 (cycle 004).

- T2 — shell validators derive from the schemas. Acceptance A3, A5.
  Accepted cycle 002.
  - Delivered: `validate_section_brief`, `validate_handoff`,
    `handoff_budget_report`, `markdown_verdict_parse`, `refresh_sections_index`'s
    index preamble and `cmd_init_section`'s handoff template all read
    `schemas/{section_brief,handoff}.schema.json` at call time;
    `markdown_verdict_parse` is now a pipe into `export.py verdict`;
    `parse_brief` returns `priority_loss` and the schema requires it.
    Three new fixtures: `brief_priority_missing_loss.md`,
    `brief_priority_unknown.md`, `handoff_over_bytes.md`.
  - A3: `zsh tests/boundary_schema_test.sh` exits 0 and prints eleven markdown
    fixtures with two agreeing verdicts each (5 ACCEPT pairs, 6 REJECT pairs),
    two missing-schema rows, and `driver verdict token sets: 12 literals use 9
    schema-defined sets`.
  - A3 (definition, not duplication): with `schemas/section_brief.schema.json`
    deleted from an engine copy the shell rejects with
    `ERROR: cannot load section brief schema at …/section_brief.schema.json`;
    same for `handoff.schema.json` and `validate_handoff`. No accept, no fallback.
  - A3 (comparison is not decorative), PM's own mutations,
    `sections/boundary-schema/probe_mutation_002.zsh`:
    stubbing `validate_handoff` to `return 0` in a copy →
    `FAIL: handoff_missing_unproven.md disagreement: checker=REJECT shell=ACCEPT`,
    exit 1; removing `priority_loss` from the schema's `required` →
    `FAIL: brief_priority_missing_loss.md disagreement: checker=ACCEPT
    shell=REJECT`, exit 1. Both columns can fail, and loosening the schema is
    caught rather than rewarded.
  - A5: `boundary_schema_test.sh`, `pm_flow_test.sh`, `topology_compare_test.sh`,
    `agent_bindings_test.sh` and
    `template/.agentic/pm_flow/tests/verdict_parser.zsh` (`pass=35 fail=0`)
    all exit 0 in the developer worktree.
  - No behaviour change, PM's own A/B (`sections/boundary-schema/probe_no_stricter.zsh`):
    `validate_section_brief`, `extract_section_priority`, `validate_handoff` and
    `handoff_budget_report` extracted from main's `pm_flow.sh` and from the
    worktree's, run over all 22 live section briefs, all 22 live handoffs and the
    nine fixtures — `diff` of the two result sets is empty, including the report
    strings (`It is 527 words; the cap is 500.`,
    `It is 8575 bytes; the cap is 8192.`).
  - Verdict contract byte-identical (`sections/boundary-schema/probe_verdict_contract.zsh`):
    on both engines an accepted verdict gives exit 0 and the two lines
    `GO_WITH_CHANGES` / `GO_WITH_CHANGES rewire the validator first`; a rejected one
    gives exit 1 and `response Decision must begin with one of ['GO',
    'GO_WITH_CHANGES', 'NO_GO'], got 'MAYBE not sure yet'`;
    `extract_markdown_decision_line` returns the same line and the same exit codes.

- T1 — schemas and the stdlib checker. Acceptance A2, A3 (checker side), A5.
  Accepted cycle 001.
  - Delivered: `schemas/{section_brief,handoff,verdict,config}.schema.json`,
    `template/.agentic/pm_flow/export.py` (317 lines, imports only
    `argparse`/`json`/`pathlib`/`re`/`sys`), `tests/boundary_schema_test.sh`,
    ten fixtures under `tests/fixtures/boundary_schema/`.
  - A2: `python3 <flow>/export.py check --kind handoff <fixture>` — valid handoff
    exit 0; `handoff_missing_unproven.md` exit 1 with
    `handoff.What is unproven is required`. Equivalent pairs observed for brief
    (`brief.headings.Scope is required`;
    `brief.acceptance_ids[0] must match pattern '^\`?A[0-9]+\`?\s*[:.—-]'`),
    verdict (`response Decision must begin with one of ['GO', 'GO_WITH_CHANGES',
    'NO_GO'], got 'MAYBE …'`) and config
    (`config.roles.developer.cli must be one of ['claude', 'codex', 'copilot',
    'acp'], got 'unknown'`).
  - A3: `zsh tests/boundary_schema_test.sh` prints all ten fixtures with their
    verdicts (5 ACCEPT / 5 REJECT) and exits 0. Mutation check: with
    `validate_schema` stubbed to `return payload` in a temp copy, the suite fails
    at `brief_missing_scope.md verdict: expected 'REJECT', got 'ACCEPT'` — the
    reject path is genuinely under test.
  - A5: in the developer worktree, `boundary_schema_test.sh`, `pm_flow_test.sh`,
    `topology_compare_test.sh` and `agent_bindings_test.sh` all exit 0. No tracked
    file was modified (`git diff --stat HEAD` empty); the four new paths are the
    only additions.
  - Runtime-loading proved: deleting `schemas/handoff.schema.json` from a copy makes
    `check --kind handoff` exit 1 with `cannot load handoff schema at …`, so the
    schema files are read, not embedded.

## Active decisions

- The checker lives inside `export.py`, not a separate module: the brief's owned
  paths grant the section one Python file plus `schemas/**`, and the export path and
  the tests are the only two callers.
- `schemas/` is the single definition; the shell validators read it rather than
  keeping a parallel list. A schema file that exists but is duplicated by hand in
  `pm_flow.sh` is a rejection condition in the brief, not a shortcut.
- Export field names are stable and never carry a cycle number:
  `sections[] {key, name, status, priority, owned_paths, dependencies,
  acceptance[] {id, state}, handoff {outcome, decisions, interfaces, risks,
  unproven, next_action}}`.
- Acceptance state is derived, not stored, and the derivation may not key on a
  heading name. Revised at cycle 004 after probing all 22 sections: an ID from
  `brief.md`'s Acceptance bullets is `met` when its bare token appears anywhere in
  `state.md` except under `Blockers` and `Next eligible task`, otherwise `open`. The
  earlier rule — "appears under the completed-evidence heading" — is wrong on this
  project, because `## Completed tasks and evidence` exists in only 18 of 22
  sections. The schema pins the two-value enum so no consumer invents a third.
- `acp` is valid everywhere (fixed by the brief), and cli legality is a schema
  question, not a registry question. `config.schema.json`'s `$defs.seat` enum decides
  which clis are legal; `FALLBACK_MODELS`/the store's `clis` table constrain models
  only, read as `registry.get(cli, [])` so an absent or empty list is unconstrained —
  `copilot`'s long-standing shape, now shared by `acp`. Closed in T3; seeding the
  store no longer decides legality.
- The export reads the per-section files directly (`status.txt`, `priority.txt`,
  `owned_paths.txt`, `dependency_handoffs.txt`, `brief.md`, `handoff.md`,
  `state.md`), not the generated `sections.md` table, which is a rendered view.

## Blockers

- None. The section's only long-standing blocker is closed.
- Closed at cycle 004 review: `tests/topology_compare_test.sh` **passes**. The
  `FAIL: abandonment does not emit section_status` entry that stood here through
  cycles 002-004 scoping is no longer true and has been deleted. Observed by the PM
  in `review_004_topology.zsh`, which runs the suite twice — once against a pristine
  `git archive main` at `6b81584` and once in the developer checkout — and gets
  `main-exit=0` and `wt-exit=0`, the single line
  `PASS: topology compare reports literal metrics, limits, personas, and copy
  retention` from both, with `diff` of the two runs empty on stdout and stderr.
  `outcome-record` reconciled the guard with `driver.zsh`'s new
  `telemetry_record_outcome` signature and it has since merged to `main`.
- The developer's `sync: cannot find pm_flow.persona_card to validate persona card`
  account did not reproduce for a **fourth** consecutive cycle. This cycle the PM
  also tested and ruled out the obvious environmental explanation: the suite scrubs
  its own environment (`topology_compare_test.sh:5-10` unsets every `PM_FLOW_*` and
  hard-fails if one survives), and re-running it with the full dispatch env exported
  still gives exit 0 (`review_004_topology_env.zsh`). Whatever produces that message
  is local to the developer's shell, not to either tree. Keep demanding the exact
  command, cwd and full output before acting on it.

## Standing facts for anyone touching these files again

- `template/.agentic/pm_flow/tests/verdict_parser.zsh` is the in-engine regression
  guard for anything touching the verdict path: it extracts `markdown_verdict_parse`
  and four neighbours by regex (`verdict_parser.zsh:19-33`), sets `SCRIPT_DIR` to the
  engine root (`:18`), and exercises 35 presentation cases. Baseline `pass=35 fail=0`
  at cycle 002, still `pass=35 fail=0` on main at cycle 005. Run it for any future
  edit to the verdict path; `tests/` alone does not cover it.
- `validate_section_brief` has a wide blast radius: eleven suites build briefs
  inline (`artifact_quality`, `store_ledger`, `packaged_layout`, `run_detach`,
  `otel_semconv`, `topology_compare`, `codex_usage`, `agent_bindings`,
  `persona_cards`, `trace_commands`, `pm_flow`). It must keep accepting exactly what
  it accepts today; cycle 002's A/B over 53 real artifacts is the baseline to re-run
  if T3 or T4 touches it.
- `pm_flow.sh` has no source guard — line 2019 is a bare `main "$@"` — so any
  harness that calls a validator directly must extract the functions rather than
  source the file as shipped.
- Every engine consumer of a schema hard-fails when `schemas/` or `export.py` is
  absent, by design. The cycle-002 escalation to `real-install` over this is
  **resolved and needs no handoff**: `install.sh` now lists `export.py` in
  `COPIED_ENGINE_FILES` (`:62`) and `schemas` in `COPIED_ENGINE_DIRS` (`:84`), added
  by `real-install` cycle 001 (`3d461ca`). The wheel path never had the gap —
  `pyproject.toml:51` force-includes the whole `template/.agentic/pm_flow` directory
  as `pm_flow/engine`, so `schemas/` ships with the package. This matters for T3:
  `agent_bindings_test.sh` runs `agent_exec.sh` from an installed wheel
  (`agent_bindings_test.sh:365-369`), so a schema read added there resolves.
- In zsh, never name a probe variable `path` — it is tied to `PATH` and assigning to
  it blanks the command search path. Cost one wasted probe run this cycle.

## The cli definition after T3

Scoping probe `probe_cli_003.zsh`; review probes `probe_mutate_003.zsh` and
`probe_msgs_003.zsh`, outputs under `sections/boundary-schema/review_003/`.

- The cli enum and the difficulty enum are each written exactly once in the whole
  engine, at `config.schema.json:10` and `:12`, inside `$defs.seat`. Verified by
  grep over `template/.agentic/pm_flow` and the suite. The literal guards that used
  to hold them — `pm_flow.sh:539`/`:542`, `agent_exec.sh:199`/`:202`,
  `topology.py:13` (`DIFFICULTIES`) and `:193` — are gone; `DIFFICULTIES` has no
  remaining reference anywhere in `template/`, `tests/` or `src/`.
- Still out of bounds and deliberately untouched: `agent_exec.sh:654`'s `copilot)`
  case arm (execution dispatch, not a legality guard), `catalog.py:231`/`:263`'s
  difficulty-to-effort *mapping* (`persona-packs`; a translation table, not a
  legality enum) and `catalog.py:227`'s `clis` seeding, and `telemetry.py:82`
  (`outcome-record`).
- The store no longer decides legality, but it is still read: on a flow whose
  `clis` table lists only `claude`, `codex`, `copilot`, `model_registry` returns
  exactly those three and an `acp` seat validates anyway. That is the whole point of
  the split, and reverting `topology.py` to `cli not in registry` reproduces the old
  rejection — the mutation the suite now catches.

## Baseline observed at cycle 002

- Section directories under `.../pm-agent/sections/` carry `name.txt`, `status.txt`,
  `priority.txt`, `summary.txt`, `owned_paths.txt`, `dependency_handoffs.txt`,
  `run_path.txt`, `updated_at.txt`, `brief.md`, `handoff.md`, `state.md`,
  `workplan.md`. 22 sections exist.
- `driver.zsh:1227` calls `markdown_verdict_parse` but the function itself lives in
  `pm_flow.sh:929`, so the verdict work needs no edit to another section's file.
- `schemas/`, `export.py`, the suite and the fixtures exist (T1) and the shell
  validators now read them (T2). The export verb landed at T4, cycle 004.
- After T2 the only heading-shaped literal left in `pm_flow.sh` is
  `extract_assignment_sections`' `WANTED`/`TITLES` list (`:975-977`), which describes
  the assignment prompt, not a boundary artifact, and has no schema. Out of scope
  unless a later brief adds one.
- `refresh_sections_index`'s generated preamble line is now schema-derived and reads
  "…carries only outcome, decisions, interfaces, risks, what is unproven, and next
  action" where it used to read "outcomes … and the next action". Cosmetic; nothing
  in `tests/`, `template/` or `src/` matches on the phrase.
- `verdict.schema.json`'s `x-allowed-token-sets` enumerates nine kinds. Confirmed
  complete against `driver.zsh`: the twelve CSV literals there reduce to exactly
  those nine distinct sets.

## Baseline observed at cycle 004 scoping

Probe `sections/boundary-schema/probe_export_004.zsh`, run against the `main`
checkout with T3 merged.

- The live project is already exportable. All 22 sections pass both
  `export.py check --kind brief` and `export.py check --kind handoff`
  (`totals: brief ok=22 bad=0 | handoff ok=22 bad=0 | state.md=22`), and each of
  `name.txt`, `status.txt`, `priority.txt`, `summary.txt`, `owned_paths.txt`,
  `dependency_handoffs.txt`, `run_path.txt`, `updated_at.txt` exists in 22/22
  directories. A1's "exits 0 on the pm-agent project" needs no markdown repair; a
  failure there would be the emit path's fault, not the data's.
- `parse_brief`'s `acceptance_ids` are whole bullet lines, not identifiers. For
  `otel-semconv` the first is
  `A1: On a run recorded after this change, an OTLP receiver independent of` and
  `n_ids: 7`. The export's `acceptance[].id` has to be the bare `A1`.
- `parse_handoff` already returns exactly the six stable fields plus the two counts:
  `['byte_count', 'decisions', 'interfaces', 'next_action', 'outcome', 'risks',
  'unproven', 'word_count']`. The handoff half of the export needs no new parser.
- `## Completed tasks and evidence` appears in 18 of 22 `state.md` files. The four
  exceptions — `agents-md`, `green-suite`, `installer`, `worktree-isolation` — use
  free-form headings (`Evidence, re-verified against the current main`,
  `Decisions and evidence`, `Completion review`, `Result`). Hence the revised
  acceptance-state rule under Active decisions.
- `priority.txt` holds the token on line 1 and the loss text on the lines after
  (`otel-semconv`: `must-have` then `Without it the measurement layer speaks a
  private dialect…`). Read line 1 only.
- `dependency_handoffs.txt` is empty for a section with no dependencies, so the
  export's `dependencies` must be `[]`, not `[""]`.
- `pm_flow.sh` line numbers have moved since the brief was written:
  `usage()` is at `:35`, `refresh_sections_index` at `:627` with `first_line` at
  `:668`, and `main`'s dispatch case block at `:1983-2084`.
- `src/pm_flow/cli.py:81-87` forwards any unrecognised verb to the engine with
  `PM_FLOW_*` exported and `cwd` set to the repo root, so `export` needs no Python
  change — confirmed by reading the file, not assumed from the brief.

## Observed at cycle 004 review

- The `$ref` blind spot carried from cycle 003 is closed. `SchemaReferenceError`
  now escapes the `oneOf` arm loop (`export.py:141-142`). PM probe
  (`review_004_ref.zsh`): a schema whose arm 0 matches and whose arm 1 holds
  `#/$defs/typo-that-does-not-exist` raises
  `unresolvable schema pointer '#/$defs/typo-that-does-not-exist'`; a missing
  referenced file raises `cannot load referenced schema at …`; and
  `{"$ref": "handoff.schema.json#"}` still resolves against a real handoff object.
  `_resolve_reference` also refuses absolute paths and any `..` component.
- Correction to the cycle-004 scoping note about free-form `state.md` headings.
  The prediction was that `agents-md`, `green-suite`, `installer` and
  `worktree-isolation` would report every acceptance ID `open`. In the live export
  they report **no acceptance IDs at all** — `acceptance: []`, alongside
  `packaging`, five sections in total. The cause is upstream of the state rule:
  their briefs are legacy-shape, and their Acceptance bullets carry no `A<n>` token
  (`agents-md/brief.md:36` is `- A fresh install writes AGENTS.md carrying the role
  router and invariants.`), so `_bare_acceptance_id` matches nothing to derive a
  state for. The emitted `[]` is faithful to the source. The heading-independent
  rule is therefore proven only by the `freeform` fixture and by the PM's mutation
  check, not by live data — which is sufficient, but a consumer reading the export
  sees five sections with no criteria. Adding IDs to those five briefs belongs to
  their owners, not here.
- The verb resolves the engine from `PM_FLOW_ENGINE_ROOT`
  (`pm_flow.sh:16`, set by `src/pm_flow/paths.py:244`), which on this machine is the
  source tree's `template/.agentic/pm_flow`. The developer's `unknown command:
  export` was that editable install pointing at an unmerged worktree, not a gap in
  the work: cycle 004 merged at `50ec3b2` and `pm-flow export --json` typed in the
  repository now exits 0 with no override, confirmed at cycle 005.
- The export arm passes the flow directory explicitly —
  `python3 "$SCRIPT_DIR/export.py" emit "$@" "$FLOW_DIR" "$PROJECT_KEY"`
  (`pm_flow.sh:2031-2033`), with `FLOW_DIR` from `PM_FLOW_FLOW_DIR` falling back to
  the engine's own directory (`:17`) and the key from `resolve_project_key`
  (`:172`), which reads `<flow>/.project-key`. So exporting a copy of the project
  means copying `.agentic/pm_flow` whole and setting `PM_FLOW_FLOW_DIR`; copying
  only the `pm-agent` directory loses the key file.

## Next eligible task

- None. T1-T4 are done and A1-A5 are met on merged `main`; the workplan is closed
  and the section is complete. What it leaves behind for the ticket-integration
  section is `template/.agentic/pm_flow/schemas/*.json`, the stable
  `pm-flow export --json` output shape, and `export.py check --kind
  {brief|handoff|verdict|config|export}`.
