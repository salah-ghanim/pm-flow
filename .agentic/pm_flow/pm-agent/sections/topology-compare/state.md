# topology-compare section PM state

## Current task

- T4 — end to end through the installed command. T3 closed at cycle 004,
  carrying two gaps T4 must close (inert `wall_clock_s`; unchecked
  `topology_edges` import — see Blockers).

## Completed tasks and evidence

- T1 — topology documents, the CLI model registry, and validation. Accepted
  cycle 002. Acceptance IDs: A4, plus the A6 regression gate.
  - `zsh tests/topology_compare_test.sh` → exit 0,
    `PASS: topology documents validate, overlay read-only, and refusals precede dispatch`.
    `lean` and `heavy` validate; their overlays differ from `config.json` in
    exactly the developer model and the consultant seat count
    (`gpt-5.6-sol`/`gpt-5.1-codex`/`gpt-5.6-sol`, seats `2`/`1`/`3`, with every
    other role and every non-`roles` key asserted equal); `validate missing`
    exits non-zero naming the key and `$FLOW/topologies/missing.json`; the
    `gpt-not-a-model` document exits non-zero naming `developer`, `codex` and
    the model; `attempts` is unchanged across both refusals.
  - The byte-identity `cmp` is now capable of failing. It sits at
    `tests/topology_compare_test.sh:125`, after every topology command and
    before the suite's own rewrite of `config.json` at `:133`. Reviewer
    mutation, 2026-08-24: a copy of the suite with one line inserted
    immediately above the `cmp` appending `corrupted` to `config.json` exits 1
    with `FAIL: topology commands changed config.json`; the unmutated suite
    exits 0. Cycle 001's placement passed under the same corruption.
  - `install.sh` names the new engine file and directory:
    `topology.py` in `COPIED_ENGINE_FILES`, `topologies` in
    `COPIED_ENGINE_DIRS`. `zsh tests/packaged_layout_test.sh` → exit 0, all 13
    `PASS:` lines, with the migrated flow directory reading exactly
    `.gitignore .project-key config.json local_env.sh.example projects.md salvage-legacy`.
    Reviewer negative check, 2026-08-24: with those two entries stripped, the
    same suite exits 1 —
    `FAIL: the migrated flow directory holds project data only: … got '… salvage-legacy topologies topology.py '`.
    `install.sh` was restored byte-identical afterwards.
  - `zsh tests/pm_flow_test.sh` → exit 0, all 10 `PASS:` lines. The `models`
    lists added to `clis.capabilities` do not change how `config.json`'s
    `gpt-stub` and `fixture-model` bindings resolve.

- T2 — run two arms from one commit. Accepted cycle 003 with changes.
  Acceptance IDs: A1, A5, plus the A6 regression gate.
  - `zsh tests/topology_compare_test.sh` → exit 0,
    `PASS: topology compare runs isolated arms and imports topology/persona provenance`.
    After `pm-flow compare lean heavy --max-ticks 5` on the stub project,
    `SELECT t.key || '|' || p.key FROM runs r JOIN topologies t … JOIN projects p … ORDER BY t.key`
    returns exactly `heavy|topology-project` / `lean|topology-project` — the
    asserted two-line string, not a count. Both arms' `copy_path` values are
    read from the command's own stdout, differ from each other and from the
    origin checkout; `starting_commit=` appears exactly once and equals the
    origin's `git rev-parse HEAD`; each copy's `config.json` `cmp`s equal to its
    arm's overlay and the origin `config.json` `cmp`s unchanged.
  - A5 is asserted in both directions and is capable of failing. The store query
    over `attempts.persona_stack` for `role_key='pm'`, base layer, returns
    `heavy|pm` and `lean|cpo`. Reviewer mutation, 2026-08-24: replacing
    `compare.py:363` `swap_first_arm(arms[0], engine, project)` with `pass`
    turns the suite red —
    `FAIL: persona swap is confined to the first arm: expected 'heavy|pm\nlean|cpo', got 'heavy|pm\nlean|pm'`.
    `compare.py` was restored byte-identical (`cmp` clean) and the suite re-run
    green afterwards.
  - The import is idempotent at the run-key boundary: re-importing arm one's
    store through `compare.py`'s own `import_store` leaves the `runs`/`attempts`
    counts unchanged.
  - Developer mutations, each reversed: both arms at one checkout →
    `ERROR: topology 'heavy' produced no run`; validation dropped →
    `FAIL: compare accepted a missing topology`; second import skipped →
    `FAIL: compare imports both topology runs under one project: expected 'heavy|topology-project\nlean|topology-project', got 'lean|topology-project'`.
  - `install.sh` names `compare.py` in `COPIED_ENGINE_FILES`.
    `zsh tests/packaged_layout_test.sh` → exit 0, 13 `PASS:` lines;
    `packaged_layout_test.sh` itself is untouched, so the exact migrated-directory
    listing at `:1018-1020` is what proves it.
    `zsh tests/pm_flow_test.sh` → exit 0, 10 `PASS:` lines.

- T3 — the report and its limits. Accepted cycle 004 with changes.
  Acceptance IDs: A2, A3, A5, plus the A6 regression gate.
  - `zsh tests/topology_compare_test.sh` → exit 0,
    `PASS: topology compare reports literal metrics, limits, personas, and copy retention`.
  - A2. `compare --report lean-fixture-1 heavy-fixture-1` on the seeded
    `report-project` store prints, as exact strings, `cost_usd 4.0000 2.5000`,
    `tokens 310 250`, `cycles_to_done 2.00 2.00`, `rescue_rate 0.33 0.00`,
    `abandon_rate 0.33 0.00`, `escalation_depth 1 1`, `wall_clock_s 30.0 12.5`,
    `n_runs 2 1`, under the header `metric lean heavy` — every expected value
    written literally in the suite, not recomputed by it. The fixture is seeded
    through `telemetry.py run-start|attempt-start|attempt-end|outcome`, so each
    figure is hand-computable: lean is `lean-fixture-1` (1.25+0.25+0.50+0.75+0.25)
    plus `lean-fixture-2` (0.50+0.50) = 4.00 over 3 sections, one rescued
    (`10x_developer` on `alpha`) and one abandoned (`beta`).
  - A2 reconciliation, the one-accounting check: `python3 cost.py total
    <report-project>` → `6.5000`, equal to `4.0000 + 2.5000`.
  - A3. The report's last line is
    `Limits: lean n=2; heavy n=1. No difference between the arms can be inferred.`
    on the two-run fixture and
    `Limits: lean n=1; heavy n=1. No difference between the arms can be inferred.`
    on the driven compare — different sizes from different data, so the sizes
    are read from the store rather than printed.
  - A5. After `compare lean heavy --max-ticks 5 --persona lean:pm=cpo`, the
    per-arm block reads `arm lean / personas pm=cpo` and `arm heavy /
    personas pm=pm`, and the store query over `attempts.persona_stack` still
    returns `heavy|pm` and `lean|cpo`. Asserted in both directions.
  - T2's carried defect is cleared and the clearing is observed, not asserted
    from source: a second compare with no `--persona` leaves both arms on the
    base persona — `heavy|pm` / `lean|pm`.
  - Copy retention is observed from the command's own stdout:
    `--keep-copies` prints `copy_status=retained` on both arm lines, the default
    prints `copy_status=removed` on both.
  - A6. `zsh tests/pm_flow_test.sh` → exit 0, 10 `PASS:` lines;
    `zsh tests/packaged_layout_test.sh` → exit 0, 13 `PASS:` lines.
  - Reviewer mutations, 2026-08-24, each applied to the developer's tree, run,
    and reversed (`git status` clean to the four expected files afterwards);
    harness at `cycles/004/review_mutations.zsh`. All eleven the assignment
    required reproduce their failure line: `n_runs`→1, `escalation_depth`→0,
    `tokens`→`input_tokens`, `cycles_to_done`→`MAX`, rescue role→`developer`,
    `abandon_rate`→`complete`, `wall_clock_s`→`COUNT(*)`, limits sentence
    deleted (`got 'personas pm=pm'`), `--persona` dropped from the test
    (`got 'heavy|pm\nlean|pm'`), `outcomes` import skipped
    (`cycles_to_done` `expected '1.00 1.00', got '- -'`), and `do_abandon`'s
    record removed.
  - The `cost_usd`→`topology_comparison` mutation is caught by a source grep,
    not by output, and the developer said so. Verified: with the mutation
    applied *and* the grep guard removed, the suite still passes — the view
    (`store.py:422-437`) sums `COALESCE(a.cost_usd, 0)` per run over a LEFT
    JOIN, which is arithmetically the same number. The behavioural guard on
    "one accounting" is the `cost.py total` reconciliation above, and it holds.
  - `import_store` carries `topology_edges` and `outcomes` and is idempotent.
    Reviewer probe (`cycles/004/review_edges_probe.zsh`): a source store with 8
    edges and two runs imports to 8 edges; a second `import_store` returns `[]`
    and leaves 8. `topology_edges` has `UNIQUE (topology_id, from_role,
    to_role, kind)`, so the `INSERT OR IGNORE` is sound.

## Active decisions

- Engine Python lives in `template/.agentic/pm_flow/`, not `src/pm_flow/`.
  `src/pm_flow/cli.py:69-87` forwards unrecognised commands straight to
  `pm_flow.sh`, and `store-ledger` shipped `cost.py` under `template/`. So
  `topology.py` and `compare.py` go beside `cost.py`, and `pm-flow compare` is
  a dispatcher case in `pm_flow.sh` with a `cmd_compare` in `driver.zsh`. The
  brief's owned paths are wrong on this point; the workplan carries the
  correction, and it is worth raising upward at handoff so other sections do
  not repeat it. No acceptance ID changes.
- A topology document never edits `config.json`. `topology.py overlay` prints
  the merged config; the compare command writes that text into the arm's
  disposable copy only. `agent_exec.sh:50` reads `$FLOW_DIR/config.json`, so a
  per-copy file is all that is needed to redirect an arm's bindings.
- No model list exists anywhere in the engine today. `register_clis`
  (`catalog.py:218-278`) records `thinking_levels` and `capabilities` per CLI
  and nothing about models; the `clis` table has no models column. A4's
  "a model the bound CLI does not list" therefore needs a list, and it goes
  inside the existing `capabilities` JSON blob — a value change, no schema
  change. Deterministic and offline; the alternative, probing the live CLI,
  would make the acceptance check depend on the network.
- The model check applies to topology documents only. `config.json` in the
  test suites binds `gpt-stub` and `fixture-model`; validating those would
  break `pm_flow_test.sh` and `packaged_layout_test.sh`.
- Cost comes from `store-ledger`'s `cost.py total`. The `topology_comparison`
  view (`store.py:422-437`) sums `attempts.cost_usd` itself; using it for
  `cost_usd` would be the second accounting the brief rejects. The view stays
  in use for attempts, tokens, duration and status.
- A persona swap is an operator argument, not something the command does.
  Probed 2026-08-24: a swap is stored per `(project, topology, role)` in the
  project store (`catalog.py:400-430`), and an arm copy is a `git clone`
  (`compare.py:45-52`) whose store starts empty — so a swap made in the origin
  store cannot reach an arm, and only the compare command can reach the arm's
  store between `sync` and `run`. Hence `--persona <topology>:<role>=<persona>`
  on `compare run`: no swap unless asked for, and the arms otherwise differ by
  their topology alone. This replaces cycle 003's hardcoded `swap_first_arm`.
- The report's columns are defined against facts the store actually holds; the
  formulas and their formats live in `workplan.md` T3. Two consequences worth
  keeping here: `rescue_rate` reads `role_key='10x_developer'`, because
  `do_rescue` (`driver.zsh:1903-1909`) is that role's only dispatch site; and
  `abandon_rate` needs a record that does not exist yet, because `do_abandon`
  (`driver.zsh:2070-2089`) dispatches nothing at all. The `outcomes` table and
  `telemetry.py outcome` (`store.py:369-383`, `telemetry.py:753-777`) are built
  for exactly this and no engine code emits to them, so T3 emits
  `section_status` at `do_abandon` and `do_complete`. A column that can only
  ever read zero would be a report that describes nothing.
- `cost_usd` reuses `cost.py` as a module — `import_legacy` then
  `stored_totals`' own `SUM(COALESCE(a.cost_usd, 0))` restricted to the arm's
  runs — and `cost.py` is not edited. The reconciliation assertion (both arms
  summing to `cost.py total`) is what makes "one accounting" checkable rather
  than a matter of style.
- Arm copies are deleted once imported, unless `--keep-copies`. Settled at T3;
  before the report existed, the clone was the only way to inspect an arm.
- One disposable checkout per arm, from the same starting commit; rows
  imported back under the arm's key. Probed 2026-08-24: an arm needs no new
  dispatch path — `telemetry_begin_run` (`driver.zsh:679-690`) already reads
  `PM_FLOW_TOPOLOGY` into both `catalog.py sync --topology` and `telemetry.py
  run-start --topology`, and `run-start` (`telemetry.py:412-446`) stamps
  `runs.topology_id`. The import is store-to-store and has no existing helper;
  it belongs in `compare.py`, keyed on `runs.run_key`. An arm copy is a
  separate checkout rather than a `git worktree`, because worktrees are already
  the sections' mechanism and `cmd_run` prunes them at every start.

## Blockers

- Open carried defect, from cycle 004: `wall_clock_s` cannot be non-zero in a
  real run. `telemetry_end_run` (`driver.zsh:752`) is defined and has no call
  site anywhere under `template/` — the only other mention is a comment at
  `:827`. So `runs.ended_at` stays NULL, `SUM(ended_at - started_at)` is NULL,
  and the column reads `0.0`. Observed 2026-08-24 on the origin store
  immediately after `compare lean heavy --max-ticks 5`: both imported runs read
  `status=running` with `ended_at` empty, and the printed report's
  `wall_clock_s` row is `0.0 0.0`. This is the defect class T3 cleared for
  `abandon_rate`, left standing for the column that answers the brief's "how
  long each took". It is pre-existing engine behaviour, not introduced this
  cycle, and cycle 004's assignment fenced the driver to `cmd_compare` and the
  outcome helper, so it was outside the developer's writable paths — which is
  why A2 stands on the seeded fixture and the cycle was accepted. T4 owns it:
  call `telemetry_end_run` where a run finishes, and assert a non-zero
  `wall_clock_s` from a driven compare rather than only from a fixture.
- Open coverage gap, from cycle 004: nothing observes `import_store` carrying
  `topology_edges`. The suite asserts `escalation_depth` only on the
  `report-project` fixture, whose topologies are synced into its own store by
  `catalog.py sync --topology` and never cross the importer; the driven
  compare's `escalation_depth` value is not asserted at all. Reviewer mutation,
  2026-08-24: disabling the edge SELECT in `import_store` leaves
  `tests/topology_compare_test.sh` green (exit 0). The importer itself is
  correct — probed separately, 8 edges in and 8 out across two imports — so
  this is a missing check, not a missing behaviour. T4 closes it.
- The migration rule stays open as a standing rule
  for the rest of the section: every task that adds a file under
  `template/.agentic/pm_flow/` must add its name to `install.sh`'s
  `COPIED_ENGINE_FILES` or `COPIED_ENGINE_DIRS` in the same cycle, or
  `packaged_layout_test.sh` turns red. `install.sh:40-46` states those lists are
  "the whole of what migration removes". `compare.py` reintroduces this at T2;
  its T2 path list already names `install.sh`. `install.sh` is an owned path for
  this section that the brief does not list.
- `store-ledger` is not a blocker. Its handoff records A1-A5 with evidence and
  four suites exiting 0 on `main` `75462bd`, so its `cost.py total` interface
  is available to T3. T1 and T2 never needed it.

## Verified, to be carried rather than re-derived

- `topology.py`'s A4 behaviour is sound and mutation-tested by the reviewer at
  cycle 001: removing the model-membership check, dropping the expected path
  from the missing-document refusal, and ignoring the document's `roles` in the
  overlay each turn `tests/topology_compare_test.sh` red. The model check is
  correctly scoped to roles the document names, so `config.json`'s fixture
  models still pass. Cycle 002 left `topology.py`, both documents and
  `catalog.py` untouched — their mtimes are cycle 001's, `12:41-12:42`, against
  `12:54` and `12:57` for `install.sh` and the test — so that evidence stands.
- `packaged_layout_test.sh` catches an unmigrated engine name two ways, and only
  one of them is live for new names. Its local `COPIED_ENGINE_FILES` /
  `COPIED_ENGINE_DIRS` mirror (`:670-675`) lists what *old* installs copied and
  deliberately does not track new engine files; what caught `topology.py` is the
  exact directory listing at `:1018-1020`. Do not "fix" the mirror when a future
  file fails migration — the failure is `install.sh`'s to answer.

## Next eligible task

- T4 — end to end through the installed command. Depends on T3, now done. It
  drives scenarios 1-3 through `.venv/bin/pm-flow`, including `pm-flow cost`
  after a compare showing attempts from both arms under their topology keys,
  and it closes cycle 004's two carried items: give `telemetry_end_run` a call
  site so `wall_clock_s` is non-zero in a driven compare, and assert
  `escalation_depth` on imported arms so the `topology_edges` import has a
  check behind it.
