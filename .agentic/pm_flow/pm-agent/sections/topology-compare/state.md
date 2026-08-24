# topology-compare section PM state

## Current task

- T3 — the report and its limits. T2 closed at cycle 003, carrying one defect
  T3 must clear (the hardcoded persona swap; see Blockers).

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

- Open carried defect, from cycle 003: `compare.py` performs the A5 persona
  swap itself. `run_compare` calls `swap_first_arm(arms[0], …)` at `:363`
  unconditionally, and `swap_first_arm` hardcodes
  `catalog.py persona swap pm cpo --topology <arms[0].key>`. So every real
  `pm-flow compare a b` runs arm A with the CPO persona on the PM seat and arm B
  with the PM persona, and the two arms then differ by more than their topology
  — which is exactly the confound the section's headline sentence rules out.
  It was written this way because cycle 003's assignment placed the swap inside
  the compare flow; that instruction was mine and it was wrong. A5 asks that a
  swapped persona be *visible* per arm, not that the command perform one.
  T3 deletes `swap_first_arm` and its call site and has the test do the swap.
  Not a blocker on T3 starting, and it does not invalidate cycle 003's A1
  evidence: the clone-overlay-run-import path is independent of the swap.
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

- T3 — the report and its limits. Depends on T2, now done. Its first
  requirement is removing `compare.py`'s hardcoded `swap_first_arm`; the rest is
  `compare --report` over the imported rows, with `cost_usd` from `cost.py
  total` and the limits sentence mutation-tested.
