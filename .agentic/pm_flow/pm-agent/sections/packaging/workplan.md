# packaging workplan

## Design summary

- Separate immutable engine code, shipped in the wheel, from mutable repository
  data under `.agentic/`. Resolve both roots once in `src/pm_flow/paths.py` and
  keep the shell entry as an installed-package implementation detail.

## Interfaces and data changes

- `pm-flow` is the console entry point; it dispatches to the packaged engine.
- Repository-local personas overlay packaged personas without modifying them.
- Legacy copied-engine installations migrate in place while retaining state.

## Task T1 — Establish the installed engine/data boundary

- Status: completed (cycles 003 and 006).
- Outcome: a clean venv runs `pm-flow` while the target repository contains
  project data and no copied engine.
- Paths: `pyproject.toml`, `src/pm_flow/{__init__,cli,paths}.py`, `install.sh`,
  `template/.agentic/pm_flow/pm_flow.sh`.
- Reuse: the existing zsh engine and project layout.
- Acceptance IDs: A1, A3.
- Validation: install the locally built wheel into a clean runtime venv, run
  `pm-flow status`, and assert the target repository is data-only.
- Depends on: green-suite, worktree-isolation.

## Task T2 — Preserve persona overlays and provenance

- Status: completed (cycle 004).
- Outcome: a local persona layer changes the dispatched prompt and the attempt
  records every layer used.
- Paths: `template/.agentic/pm_flow/pm_flow.sh`, packaged-layout fixtures.
- Reuse: existing catalog composition and attempt provenance.
- Acceptance IDs: A4.
- Validation: dispatch from an installed wheel with a project-local override;
  compare exact prompt content and stored layer provenance.
- Depends on: T1.

## Task T3 — Migrate legacy installs and retire copy lifecycle machinery

- Status: completed (cycles 005, 006, and 008).
- Outcome: migration keeps state, history, domain, and the open cycle while
  deleting `MANIFEST`, `upgrade.py`, and `tools/manifest.py`.
- Paths: `install.sh`, `.gitignore`, `README.md`, legacy fixtures, retired
  manifest paths.
- Reuse: the real copied template as the legacy fixture.
- Acceptance IDs: A7, A8.
- Validation: drive a legacy tick, migrate, drive the next tick through the
  installed command, compare store/state, and search for retired machinery.
- Depends on: T1.

## Task T4 — Prove per-repository version isolation

- Status: completed (cycle 007).
- Outcome: two repositories run different pinned versions; upgrading one
  changes no byte under `.agentic/` and does not affect the other.
- Paths: packaging metadata and `tests/packaged_layout_test.sh`.
- Reuse: the offline hashed wheelhouse.
- Acceptance IDs: A2, A5.
- Validation: build two versioned wheels, install each into a separate project
  venv, upgrade one, and compare versions and project-data hashes.
- Depends on: T1.

## Task T5 — Close the installed-artifact E2E contract

- Status: completed (cycles 008 and 009; merged at `c2438b4`).
- Outcome: documented install, status, and tick commands execute through the
  wheel and the full packaged suite completes.
- Paths: `README.md`, `install.sh`, `tests/pm_flow_test.sh`,
  `tests/packaged_layout_test.sh`, `tests/fixtures/stub_*.zsh`.
- Reuse: all prior packaging scenarios.
- Acceptance IDs: A1–A8.
- Validation: `zsh tests/pm_flow_test.sh` reports 10 PASS groups and
  `zsh tests/packaged_layout_test.sh` reports 13 PASS groups.
- Depends on: T1–T4.

## Integration and end-to-end validation

- Completion decision is recorded in cycle 010. The product-level follow-ups
  (`pm-flow init`, publication, reviewer shell permission, heartbeat path) are
  not packaging acceptance criteria and remain separate work.

## Risks and rollback

- Roll back the package release, not repository project data. Never restore the
  copied-engine lifecycle as an upgrade mechanism.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1, A3 | T1, T5 | Installed command works; repository is data-only |
| A4 | T2 | Exact prompt and stored layer provenance |
| A7, A8 | T3 | Lossless migration and retired machinery absent |
| A2, A5 | T4 | Independent versions and byte-identical data on upgrade |
| A6 | T5 | Full suite through the installed artifact |
