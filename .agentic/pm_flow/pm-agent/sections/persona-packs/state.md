# persona-packs section PM state

## Current task

- None. T7 (cycle 011) is accepted; the workplan is complete. No product
  source changed in cycle 011, so there is nothing for the driver to merge
  beyond the section's planning artifacts.

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
- T7 / A1–A5 (end-to-end): accepted in cycle 011 (review GO). The brief's
  three scenarios run in one chain on one `$DB` from a real `install.sh`
  fixture; `cycles/011/acceptance.sh` + `assertions.py`, `regressions.sh`.
  No product change: the worktree at `2038254` (engine paths identical to
  `main`) has an empty `git status --short`. Evidence (PM re-run from the
  developer worktree, `cycles/011/review/run_acceptance.zsh` →
  `review/acceptance.out`): `assertions_exit=0`, 88 `ok` lines, no `FAIL`.
  Step 1 `persona add <dir>` → `+ update-manager`, list shows hash
  `701d0151a77e`, commit `-`, path source; `persona_packs` = (path, NULL).
  Step 2 `persona add file://…` at C1 → `commit C1` + `~ update-manager
  (adopted into pack)`, no `+`/`^`; `personas` row count 1 → 1, same id 1,
  same hash; row `source_url` = URL, `metadata.git_commit` = C1,
  `source_path` = `personas/manager.md`; `persona_packs` = (URL, C1);
  `ls -A checkouts` empty. Step 3 swap → exactly one `seat_personas` row
  (pm agent id 6, layer base) changed `persona_id` → 1; domain/style rows,
  other seats, `bindings`, `tool_grants`, `topology_agents` (minus the
  override column) identical; `overrides` = `{"persona_layers": {"base":
  "update-manager"}}` only. Step 4 tick → `prompt-v1.txt` has `VERSION ONE
  ONLY`, exact domain body, both house lines, base<domain<style; one new pm
  attempt (id 1) names H1. Step 5 `persona update` exit 0 → `commit C2`,
  `^ update-manager (new version; the previous one is kept)`, `= stable-style
  (unchanged)`; list shows `1095e5071565`/C2/URL, H1 absent; v1 row
  field-identical; `persona_packs` = (URL, C2); `attempts`/`seat_personas`/
  `topology_agents`/`bindings`/`tool_grants` identical. Step 6 tick →
  `prompt-v2.txt` has `VERSION TWO ONLY`, no `VERSION ONE ONLY`; attempt 2
  names H2, attempt 1 still H1. Step 7 `persona update update-crafts` →
  `= update-manager (unchanged)`, 15 → 15 rows, snapshot identical. Step 8
  readback prints exactly `1 H1 1 C1` and `2 H2 15 C2`; pack ref C2. Step 9
  marker absent, no `pm-flow-pack-*`, roles/domains digest and worktree
  status unchanged. Mutants (`review/run_mutants.zsh`): M1 update rewrites
  the newest row in place → `assertions_exit=1` on `v1 row identical field by
  field`, `pre-update attempt still resolves to a live row`, `readback shows
  H1→C1 and H2→C2` (one line only); M2 Git add never adopts →
  `sqlite3.IntegrityError: UNIQUE constraint failed: personas.key,
  personas.content_hash`, `persona add URL exit` 1 and 16 more FAILs.
  `review/regressions_and_suite.out` — `cycle_008_exit=0 cycle_009_exit=0
  cycle_010_exit=0 regressions_exit=0`; suite ten `PASS:` lines,
  `suite_exit=0`; `diff_check_exit=0`; `git status --short` empty.

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

## Notes

- `adopt_persona` (T1, unchanged) refreshes provenance columns in place when a
  pack's content is unchanged but its manifest `version`/`summary`/`title`
  differ (reported `~ adopted`); `persona update` inherits this through the
  shared helper. Body, hash, key and layer are never touched. Cycle 011
  showed `~` only on the path→URL adoption and `=` on the no-op update.
- A swap is persisted in `topology_agents.overrides` on the swapped seat's
  row (T4 design); "topology_agents unchanged" is therefore checked on every
  column except `overrides`, with the override pinned to exactly the
  requested key.
- `cycles/011/acceptance.sh` removes `$TMPDIR/xcrun_db` (Apple's git shim
  cache) before the step-2 emptiness probe; the authoritative leak guard is
  step 9's `find -name 'pm-flow-pack-*'`.
- The PM tier cannot `cd` or run bare `python3`; validation from a worktree
  goes through a `zsh` wrapper (`cycles/011/review/run_acceptance.zsh` is the
  pattern).

## Next eligible task

- None. All workplan tasks are done; the section is ready to report
  `COMPLETE` through `handoff.md`.
