### Objective
- The product's one real install, golden-grid, runs the packaged engine: migrated by `install.sh` with project data intact, driven through one real cycle, its legacy costs imported and matching, its spans exportable.

### Current baseline
- `install.sh:262` (`migrate_legacy_flow_dir`) and `install.sh:334` (`remove_copied_engine`) implement the advertised migration; proven only against the synthetic legacy fixture in `tests/packaged_layout_test.sh:888-1108`.
- golden-grid (`/Users/salah/code/personal/golden-grid`, surveyed 2026-07-28): pre-sections `pm_flow.sh`, ten workspaces, no `.project-key`, legacy `cost_ledger.tsv`s — unmigrated.
- `sections/store-ledger/handoff.md` and `sections/packaging/handoff.md` "What is unproven" list the deferred real-install checks this section closes.

### Deliverables
- A fixture under `tests/fixtures/real_install/` reproducing golden-grid's pre-migration shape (pre-sections `pm_flow.sh`, multiple workspaces, no `.project-key`, legacy TSVs) and a suite `tests/real_install_test.sh` that migrates it and drives an installed tick, exiting 0 on `main`.
- Any `install.sh` fixes the real layout forces (multi-workspace migration, missing `.project-key`, TSV-era files), without regressing `tests/packaged_layout_test.sh`.
- The migration performed on golden-grid itself: current wheel in its venv, `install.sh` run, copied engine removed, project data preserved, rename recorded.
- One real cycle in golden-grid via `pm-flow run` or `run-detach`: a real dispatch, verdict, and driver commit in that repository.
- Deferred parity evidence: `cost.py import` per golden-grid workspace with independent TSV arithmetic, and a trace export showing golden-grid spans; captured outputs committed as evidence artifacts in this repository (`docs/real-install.md`).

### User-visible scenarios
1. In golden-grid: `.venv/bin/pip show pm-flow` names the current version; `.venv/bin/pm-flow status` reports the project — no copied engine invoked.
2. `zsh install.sh /Users/salah/code/personal/golden-grid …` prints the migration lines (`removed_copied_engine=N`, recorded rename); afterwards the flow dir holds no `pm_flow.sh` and `git -C golden-grid status` shows only migration changes, no lost project data.
3. `pm-flow run` (or `run-detach`) in golden-grid completes one section cycle; `git -C golden-grid log` shows the driver's commit.
4. `cost.py import <workspace>` prints `imported=N`, re-run prints `imported=0`; `cost.py total` matches arithmetic done directly over that workspace's `cost_ledger.tsv`.
5. `pm-flow trace status` in golden-grid lists spans; `pm-flow trace export` (file or OTLP) exits 0 and the output contains that install's spans.
6. In this repository: `zsh tests/real_install_test.sh` exits 0.

### Interfaces produced
- `tests/real_install_test.sh` and `tests/fixtures/real_install/**` — the real-layout migration regression any future install change must keep green.
- `docs/real-install.md` — the recorded evidence of the golden-grid migration and parity figures.

### Interfaces consumed
- `install.sh` migration entry points and copied-engine registry lists.
- `cost.py import|total`, `pm-flow trace status|export`, `pm-flow run` / `run-detach` as shipped on `main`.
- `tests/packaged_layout_test.sh` conventions (offline wheelhouse, data-only fixtures); its 13 PASS must remain green.

### Scope
- In: install.sh migration hardening for the real layout; the fixture and suite; performing and evidencing the golden-grid migration, one real cycle, cost parity, trace export; documentation.
- Out: golden-grid's own project content, plans, and personas; repricing the store's under-counted 2026-08-24 window; any change to `driver.zsh` budget behaviour.

### Non-goals
- Publishing to PyPI or proving `pip install pm-flow` from an index (packaging's separate unproven item).
- Upgrade across a behaviour-changing release.
- boundary-schema or outcome-record work, even where richer records would make the evidence nicer.

### Priority
- must-have: the completion criterion "`cost_ledger.tsv` is gone and the host repository absorbs no per-dispatch writes" cannot be claimed while the product's only real install still runs a copied engine over legacy TSVs, and the advertised migration path remains unproven on any real layout.

### Owned paths
- install.sh
- tests/real_install_test.sh
- tests/fixtures/real_install/**
- docs/real-install.md
- README.md

### Dependencies
- None.

### Constraints and fixed decisions
- golden-grid is evidence ground, not owned territory: writes there are limited to what install, migration, and a driven cycle legitimately produce, and every claim about it is backed by a captured artifact committed in this repository.
- Where the dispatch sandbox cannot reach `/Users/salah/code/personal/golden-grid`, acceptance is settled by the driver's extra-dir mechanism or an operator-run probe whose output is committed — never by substituting the fixture for the real install.
- `install.sh` stays in the checkout, not the wheel (packaging decision; do not reopen).
- The boundary-schema proposal, if cut, must not block this section.
- `tests/packaged_layout_test.sh` is not owned here; extend behaviour in the new suite and keep the existing one green.

### Acceptance
- A1: `tests/real_install_test.sh` exits 0 on `main`, migrating a fixture with golden-grid's pre-migration shape (pre-sections `pm_flow.sh`, ≥3 workspaces, no `.project-key`, legacy TSVs) and driving an installed tick afterwards — checked by running the suite.
- A2: golden-grid holds no copied-engine file or dir from `install.sh`'s registry lists, its venv's `pm-flow` reports status, and its project data (workspaces, run history, TSVs pre-import) survives — checked by the committed operator probe output in `docs/real-install.md` against scenario 2.
- A3: one real cycle ran in golden-grid: a driver commit exists in its history and `pm-flow status` there shows the advanced cycle — checked per scenario 3, evidence committed.
- A4: for every golden-grid workspace with a `cost_ledger.tsv`, `cost.py import` then `cost.py total` matches independent arithmetic over that TSV, and a re-run prints `imported=0` — checked per scenario 4, figures committed.
- A5: a trace export from golden-grid exits 0 and contains that install's spans — checked per scenario 5, output committed.

### Rejection conditions
- Any criterion settled by the fixture alone where the real install was reachable — the exact watering-down the owner forbade.
- Migration that "succeeds" by discarding or rewriting project data, or parity that "matches" because the expected figure was copied from the tool's own output rather than computed independently from the TSV.
- Evidence that exists only as handoff prose with no committed artifact.
- `tests/packaged_layout_test.sh` regressing from 13 PASS.

### Open questions
- Should a backup copy of golden-grid be taken before `install.sh` runs against it, and which workspace should host the real cycle?
