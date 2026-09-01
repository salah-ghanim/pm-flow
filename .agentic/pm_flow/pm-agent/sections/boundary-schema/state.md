# boundary-schema section PM state

## Current task

- T4 — `pm-flow export --json`. T3 accepted at cycle 003; T1, T2 and T3 are all
  done, so T4's dependencies are satisfied and it is the last task.

## Completed tasks and evidence

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
    in the developer worktree. `topology_compare_test.sh` exits 1 — not caused by
    this cycle; see Blockers.

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
- Acceptance state is derived, not stored: an ID from `brief.md`'s Acceptance
  bullets is `met` when it appears under `state.md`'s completed-evidence heading,
  otherwise `open`. The schema pins that enum so no consumer invents a third value.
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

- `tests/topology_compare_test.sh` fails, and it is **not ours to fix**. Observed at
  cycle 003 review: `zsh tests/topology_compare_test.sh` exits 1 with the single line
  `FAIL: abandonment does not emit section_status`. The identical failure reproduces
  on the `main` checkout with none of this section's changes present
  (`zsh /Users/salah/code/personal/pm-flow/tests/topology_compare_test.sh`, exit 1,
  same line), so it predates cycle 003 and is not a regression from T3.
  The cause: `topology_compare_test.sh:917` is a source guard requiring the literal
  `telemetry_record_outcome "$(basename "$section_dir")" abandoned` in `driver.zsh`,
  but `outcome-record` cycle 001 changed the helper's signature to
  `(metric, value, section)`, so `driver.zsh:2152` now reads
  `telemetry_record_outcome section_status abandoned "$(basename "$section_dir")"`.
  `driver.zsh` and `telemetry.py` belong to `outcome-record`; the fix — updating the
  guard to the new argument order, or the guard's owner reconciling it — is theirs.
  The observation that unblocks A5 here: that one grep in
  `topology_compare_test.sh:916-918` matching `driver.zsh:2152` again.
  Escalate through `handoff.md`; do not edit either file from this section.
- Correction to the cycle-002 entry this replaces: the developer's reported
  `sync: cannot find pm_flow.persona_card` failure still does not reproduce, at any
  of the three cycles. The developer reported it again at cycle 003 and diagnosed it
  as a `catalog.py` packaging fault; what actually fails here is the unrelated
  `driver.zsh` source guard above. Keep asking for the exact command, cwd and full
  output — the reported output has now been wrong three times running.

## Carried into T3 and T4

- `template/.agentic/pm_flow/tests/verdict_parser.zsh` is the in-engine regression
  guard for anything touching the verdict path: it extracts `markdown_verdict_parse`
  and four neighbours by regex (`verdict_parser.zsh:19-33`), sets `SCRIPT_DIR` to the
  engine root (`:18`), and exercises 35 presentation cases. Baseline `pass=35 fail=0`
  at cycle 002. Keep it in the A5 list for every remaining task.
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
  validators now read them (T2). The export verb does not exist; that is T4.
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

## Next eligible task

- T4 — `pm-flow export --json`, the last task and the end-to-end scenario (A1, A2,
  A5). Depends on T1, T2, T3, all now done.
- Carried into T4 from the cycle-003 review, a latent weakness in the new `$ref`
  resolver: inside `oneOf`, an unresolvable pointer in one arm is swallowed when
  another arm matches. Shown by `probe_msgs_003.zsh` — breaking arm 0 to
  `#/$defs/nosuch` and validating a panel binding prints `ACCEPTED a document whose
  oneOf arm 0 holds an unresolvable pointer`. Harmless as shipped, because both arms
  reference `$defs.seat`, so deleting or renaming it fails both arms and the whole
  document is rejected (`unresolvable schema pointer '#/$defs/nosuch';
  unresolvable schema pointer '#/$defs/seat'`). It becomes real the moment
  `project_export.schema.json` gives two `oneOf` arms different `$ref`s — a typo in
  one would then degrade silently. If T4 adds such a schema, resolve pointers before
  the `oneOf` arms are tried, or let an unresolvable-pointer error escape the arm
  loop rather than joining the collected messages.
