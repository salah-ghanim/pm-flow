# persona-packs workplan

## Design summary

- Represent a pack as a validated JSON index plus Markdown persona files.
  Persist immutable content hashes and source provenance in the existing
  catalog/store so updates add versions instead of rewriting history.

## Interfaces and data changes

- `catalog.py ... persona add <local-path|git-url>` installs a pack.
- `persona list`, `persona update`, and `persona swap` expose lifecycle actions.
- Seat composition remains ordered by layer; a swap replaces exactly one row.

## Task T1 — Local pack validation and installation

- Status: done (cycle 004, `aaaf4b9`).
- Outcome: local packs install and list without executing pack content;
  identical re-adds are idempotent and edited prompts create new versions.
- Paths: `template/.agentic/pm_flow/catalog.py`, `store.py`.
- Reuse: existing personas, content hashes, provenance, and transactions.
- Acceptance IDs: A1, A4.
- Validation: local install/list scenarios plus path, symlink, forbidden-field,
  collision, adoption, and atomic-rollback mutations.
- Depends on: installer.

## Task T2 — Git acquisition with durable provenance

- Status: done (cycle 006).
- Outcome: a `file://` Git source installs through the real Git CLI while the
  original URL and exact commit, never a temporary clone path, are persisted.
- Paths: `template/.agentic/pm_flow/catalog.py`.
- Reuse: T1 validation and installation after acquisition.
- Acceptance IDs: A1, A3.
- Validation: committed temporary repository, clean checkout removal, rejected
  forbidden pack, and mutation with Git acquisition disabled.
- Depends on: T1.

## Task T3 — Source update without history loss

- Status: done (cycle 008).
- Outcome: update installs changed content as a new attributable version and
  retains old persona rows and attempts.
- Paths: `template/.agentic/pm_flow/catalog.py`.
- Reuse: pack source URL, commit provenance, and content-version rows.
- Acceptance IDs: A3, A4.
- Validation: update a local Git source from v1 to v2, verify both histories and
  displayed provenance, and kill the update/version mutations.
- Depends on: T2.

## Task T4 — Swap exactly one seat layer

- Status: done (cycle 009, `dc38523`).
- Outcome: swapping a base/domain/style persona changes only that layer,
  survives catalog re-sync, reaches the next dispatch, and keeps old attempts.
- Paths: `template/.agentic/pm_flow/catalog.py`.
- Reuse: `topology_agents.overrides`, `seat_personas`, prompt composition, and
  existing attempt provenance.
- Acceptance IDs: A2, A4.
- Validation: compare stacks, binding row, pre/post attempts, and exact prompt;
  mutations that replace the seat or collapse sibling layers must fail.
- Depends on: T3.

## Task T5 — Full regression closeout

- Status: done (cycle 009).
- Outcome: every accepted pack operation and the full engine suite pass from a
  clean environment.
- Paths: no new product paths.
- Reuse: saved cycle acceptance scenarios and engine suite.
- Acceptance IDs: A5.
- Validation: `zsh tests/pm_flow_test.sh` exits 0 (ten groups).
- Depends on: T1–T4.

## Integration and end-to-end validation

- A real installed flow creates a pack, installs it from Git, updates it, swaps
  one seat layer, dispatches, and reads both old and new attribution from the
  same store.

## Risks and rollback

- Pack-level collision rejection is intentionally atomic. Roll back the latest
  catalog code; never delete prior persona or attempt rows.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1 | T1, T2 | Local and Git installs through one validation path |
| A2 | T4 | One layer changes; sibling layers and binding do not |
| A3 | T2, T3 | Source URL/commit persist and update retains history |
| A4 | T1, T3, T4 | Edited versions and prior attempts remain attributable |
| A5 | T5 | Full suite completes |
