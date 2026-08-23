# persona-packs workplan

## Design summary

- Represent a pack as a validated JSON index plus Markdown persona files.
  Persist immutable content hashes and source provenance in the existing
  catalog/store so updates add versions instead of rewriting history.

## Interfaces and data changes

- `catalog.py ... persona add <local-path|git-url>` installs a pack.
- `persona list` shows the newest version of every key with pack, version,
  hash, commit and source.
- `persona update [pack-name]` re-acquires an installed pack from the
  `persona_packs.source_url` it was installed from and installs changed
  content as a new version (T6, cycle 010).
- `persona swap <role> <persona-key>` replaces exactly one layer of the
  role's seats; the key resolves to its newest version at read time.
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

## Task T3 — Source re-add without history loss

- Status: done (cycle 008).
- Outcome: re-adding a changed Git source installs the changed content as a
  new attributable version and retains old persona rows and attempts. Cycle
  007 chose repeated `persona add <same-url>` as the surface; the brief's
  named command `persona update` is T6.
- Paths: `template/.agentic/pm_flow/catalog.py`.
- Reuse: pack source URL, commit provenance, and content-version rows.
- Acceptance IDs: A3 (partial — versioning and history), A4.
- Validation: re-add a local Git source from v1 to v2, verify both histories
  and displayed provenance, and kill the update/version mutations.
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

## Task T5 — Regression closeout of T1–T4

- Status: done (cycle 009).
- Outcome: every accepted pack operation and the full engine suite pass from a
  clean environment, as of `dc38523`.
- Paths: no new product paths.
- Reuse: saved cycle acceptance scenarios and engine suite.
- Acceptance IDs: A5.
- Validation: `zsh tests/pm_flow_test.sh` exits 0 (ten groups).
- Depends on: T1–T4.

## Task T6 — `persona update`: the brief's named update command

- Status: done (cycle 010; evidence in `state.md`).
- Outcome: `python3 catalog.py --db <db> persona update [pack-name]`
  re-acquires each installed pack (or only the named one) from the
  `persona_packs.source_url` recorded at install, through the same
  acquisition and install path `persona add` uses, and installs changed
  content as a new version while every previous version row and every
  attempt that named it stay exactly as they were. An unreachable or invalid
  source is reported by pack name, changes nothing for that pack, and the
  command exits non-zero after trying the remaining packs. A pack name that
  is not installed is refused by name. `persona list` shows the new version,
  hash and commit; a seat swapped to a key from that pack dispatches the new
  wording on its next run without any further command.
- Paths: `template/.agentic/pm_flow/catalog.py` (only; `store.py` needs no
  change — `persona_packs.source_url` and `.ref` already hold what update
  needs).
- Reuse: `looks_like_git_url`, `git_checkout`, `read_pack_from_url`,
  `read_pack`, `install_and_report` / `install_pack`, `PackError`,
  `persona_packs` rows, `newest_persona`, the swap override readers.
- Acceptance IDs: A3, A4.
- Validation: a hermetic `file://` Git pack installed at v1, edited and
  committed to v2, then `persona update`: the listing shows v2's hash and
  commit; the v1 row and an attempt recorded against v1 are byte-identical
  before and after; a swapped seat dispatches v2 wording; an unreachable
  source and an unknown pack name fail without a store change; mutations
  that (a) rewrite the v1 row in place and (b) skip the source re-acquire
  must fail their targeted assertions. Cycle 008 and 009 checks re-run
  against the changed module.
- Depends on: T3, T4.

## Task T7 — End-to-end closing proof

- Status: next.
- Outcome: one script on one real `install.sh` fixture runs the brief's three
  scenarios in sequence against a single store — `persona add file://…`,
  `persona list` with source and commit, edit + commit + `persona update`,
  `persona swap` of one layer, run-start re-sync, headless dispatch — and
  reads both the old and the new attribution from that store. Then the full
  suite.
- Paths: no new product paths unless the chain exposes a defect, in which
  case `catalog.py`/`store.py` only.
- Reuse: cycle 009's fixture (install.sh, three-layer `pm` stack, capturing
  stub CLI), cycle 008's Git pack repository, T6's update step.
- Acceptance IDs: A1, A2, A3, A4, A5 (end-to-end).
- Validation: the chained script exits 0 with every scenario's observation
  printed; `zsh tests/pm_flow_test.sh` exits 0.
- Depends on: T6.

## Integration and end-to-end validation

- T7 is the integration proof: a real installed flow installs a pack from
  Git, updates it, swaps one seat layer, dispatches, and reads both old and
  new attribution from the same store.

## Risks and rollback

- Pack-level collision rejection is intentionally atomic. Roll back the latest
  catalog code; never delete prior persona or attempt rows.
- `persona update` must never delete or rewrite a version row; if the chain
  in T7 shows an attempt repointed, revert T6 rather than patch around it.

## Acceptance coverage

| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1 | T1, T2, T7 | Local and Git installs through one validation path |
| A2 | T4, T7 | One layer changes; sibling layers and binding do not |
| A3 | T2, T3, T6, T7 | Source URL/commit persist; `persona update` installs a new version and retains history |
| A4 | T1, T3, T4, T6, T7 | Edited versions and prior attempts remain attributable |
| A5 | T5, T7 | Full suite completes on the final module |
