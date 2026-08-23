# persona-packs section PM state

## Current task

- T7 assigned in cycle 011: the chained end-to-end proof on one store. T6 is
  merged on `main` (`e2eb511`; `cmd_persona_update` and
  `acquire_install_and_report` are at `catalog.py:1557` / `:1513`), so the
  prerequisite is met.

## Completed tasks and evidence

- T1 / A1, A4: local pack validation, installation, listing, attribution, and
  immutable content versions accepted in cycle 004.
- T2 / A1, A3: real Git `file://` acquisition with URL/commit provenance and
  cleanup accepted in cycle 006.
- T3 / A3 (partial), A4: re-adding a changed Git source retains old
  rows/attempts and lists the new version; accepted in cycle 008. The surface
  exercised was repeated `persona add <same-url>` (cycle 007 scope decision),
  not the brief's `persona update`.
- T4 / A2, A4: one-layer swap survives re-sync and reaches dispatch while
  sibling layers, binding, and old attempts remain unchanged; cycle 009 GO,
  `dc38523` on `main`.
- T5 / A5: saved regressions and all ten engine suite groups passed in cycle
  009 at `dc38523`.
- T6 / A3, A4: `persona update [pack-name]` accepted in cycle 010 (review GO),
  merged as `e2eb511`. Change: `catalog.py` only (+71/−26); `persona add`'s acquire-then-install
  body became `acquire_install_and_report(db, source, verb, expected_name)`,
  which both commands call; `cmd_persona_update` reads `persona_packs`
  (`name, source_url`), re-acquires each pack through that helper, reports a
  `PackError` per pack on stderr and exits 1 after the remaining packs. Evidence
  (PM re-run from the developer's worktree, `cycles/010/review_run.sh`):
  `review_acceptance.out` — `assertions_exit=0`, 62 `ok` lines: `persona add
  file://…` at C1, swap, dispatch; v2 commit; `persona update` exit 0 printing
  `persona update:   commit <C2>` and `^ update-manager (new version; the
  previous one is kept)`; list shows v2 hash and C2, not the v1 hash; v1
  `personas` row field-identical; `persona_packs.ref` = C2, `source_url`
  unchanged; `attempts`/`seat_personas`/`topology_agents`/`bindings`/
  `tool_grants` identical; re-sync + tick dispatches v2 wording with domain and
  house-style lines in order; pre-update attempt still names v1's hash;
  unchanged update `= update-manager (unchanged)` with 15 → 15 rows; unknown
  pack / moved-away repo / forbidden `model` field / renamed manifest each exit
  1 with the pack and source named and a full-table snapshot unchanged; no
  `pm-flow-pack-*` checkout left; pack `install.sh` never executed. Mutants:
  in-place rewrite → `mutant_in_place_assertions_exit=1` on "v1 row identical
  field by field" and "pre-update attempt remains attributable"; skip
  re-acquire → `mutant_no_reacquire_assertions_exit=1` on "v2 metadata records
  C2", "update output names C2", "list shows v2 commit" (+15 more).
  `review_regressions.out` — `cycle_008_exit=0 cycle_009_exit=0`.
  `review_probe_named_update.sh` — named update with changed local-path
  content installs a second row (`^ probe-key`, exit 0), a vanished local
  source exits 1 naming the pack, an empty store prints `no packs installed`
  exit 0. `review_suite.out` — ten `PASS:` groups, `review_suite_exit=0`.
  `git diff --check` exit 0; `git status --short` lists only
  `template/.agentic/pm_flow/catalog.py`.

## Gap found at cycle 010 scope (closed by T6)

- Before cycle 010, `catalog.py` `main()` registered only `persona add`,
  `persona list` and `persona swap`; the brief's scenario 3 command was an
  argparse error. Closed by T6 above.

## Active decisions

- Pack format is one JSON index plus Markdown files; installation never
  executes pack content.
- Content hash, source URL, and commit are durable provenance, not trust claims.
- Cross-pack collisions reject the whole install atomically.
- Repeated `persona add <same-url>` stays valid, but it is not a substitute
  for the brief's `persona update`; `update` re-acquires from the recorded
  `persona_packs.source_url` so the user never has to remember the URL.
- A swap records a key, not a version id; after `persona update` the next
  dispatch of a swapped seat carries the new version with no further command.
- The command surface is `python3 <flow>/catalog.py --db <store> persona
  {add,list,update,swap}` (since T1). `pm_flow.sh` has no `persona`
  subcommand and is outside this section's owned paths, so the brief's literal
  `pm-flow persona add …` spelling is not delivered here; the handoff names
  this as the one-line wrapper another section may add.
- Re-adding identical content from a richer source is adoption, not a
  version: `persona add <path>` then `persona add file://<same repo>` keeps
  the persona row id and hash, refreshes `source_url`/`metadata.git_commit`
  on that row (`~ adopted into pack`), and moves `persona_packs.source_url`
  and `.ref` to the URL and commit, which is what lets a later `persona
  update` re-acquire through Git.

## Blockers

- None.

## Notes for T7

- `adopt_persona` (T1, unchanged) refreshes provenance columns in place when a
  pack's content is unchanged but its manifest `version`/`summary`/`title`
  differ (reported `~ adopted`); `persona update` inherits this through the
  shared helper. Body, hash, key and layer are never touched. T7's chain should
  show the `=` path for a no-op and not mistake `~` for a version row.
- The PM tier cannot `cd` or run bare `python3`; validation from a worktree
  goes through a `zsh` wrapper (`cycles/010/review_run.sh` is the pattern).

## Next eligible task

- T7 (in flight, cycle 011). It is the last task before `COMPLETE`; no
  product change is expected unless the chain exposes a defect.
