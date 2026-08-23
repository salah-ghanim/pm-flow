# Portfolio log

## 2026-08-22 — `agents-md` panel adjudication

- Decision: SYNTHESIZE proposals 1 and 2.
- Priority: `agents-md` remains nice-to-have; no acceptance criterion is reduced.
- Product order: finish `packaging`, repair section checkout placement and manifest
  enumeration, then re-cut `agents-md` against the packaged layout.
- The repair must place linked checkouts outside the repository and Git metadata,
  filter manifest exclusions relative to `TEMPLATE`, and reject an empty generated
  manifest.
- The feature path remains one full `AGENTS.md` plus a managed `CLAUDE.md`
  `@AGENTS.md` compatibility import, preserving pre-existing content.
- Probe: the committed registry has `packaging` active and `agents-md` active;
  packaging owns `install.sh` and `MANIFEST`.
- Probe: the `agents-md` checkout resolves under `.git/pm-flow/worktrees/...`.
- Probe: `tools/manifest.py` enumerates 74 entries in the main checkout and zero
  in the section checkout.
- Probe: `worktrees_root()` derives its root from Git's common directory, and
  `iter_template_files()` tests exclusion parts on the absolute path.
- Rejected: another unchanged dispatch, a permission-control bypass, and an
  isolation-off main-tree rescue while overlapping packaging work is active.
- What is unproven: an external linked checkout accepts a real headless edit;
  manifest entry sets match between main and linked checkouts after repair; the
  post-packaging AGENTS/CLAUDE install and mutation probes pass.

## 2026-08-23 — `codex-usage` panel adjudication

- Decision: ADOPT proposal 2, the split contract test plus host-level canary.
- Priority: `codex-usage` remains must-have; no acceptance criterion is reduced.
- Product order: `codex-usage` must close after `store-ledger`, because that
  section owns `cost.py` and must make `pm_flow.sh cost` read recorded tokens.
- Rescue output: a tracked public-`tick` fixture replay must create one closed
  Codex attempt and run, assert exact usage including zero fields, exercise
  liveness and stderr-only classification, and fail under lifecycle and schema
  mutations.
- External-contract output: a host-level authenticated canary, outside the
  scoped reviewer sandbox, must publish immutable command, event, store, trace
  context, response, and exit-status evidence from the same public surface.
- Security boundary: do not grant scoped Codex roles network access, expose a
  general verification shell, or copy credentials into a role-controlled
  directory merely to make nested review possible.
- Probe: committed code captures `turn.completed.usage`, writes adjacent JSONL,
  exports `TRACEPARENT`, and brackets dispatch with attempt lifecycle calls.
- Probe: `tests/pm_flow_test.sh` checks only the fixture parser; it has no
  end-to-end store/lifecycle assertion.
- Probe: `driver.zsh` still routes `pm_flow.sh cost` through
  `cost_ledger.tsv`; `store-ledger` owns `cost.py` and its acceptance requires
  the command to read the store.
- Probe: a nonempty real-Codex fixture is committed, while the current section
  handoff still names a real CLI dispatch and production-length event-only
  liveness as unproven.
- Graph update blocked: the validated `section-dependencies` command rejected
  the `store-ledger` edge because active `packaging` ownership of
  `tests/fixtures/stub_*.zsh` is judged to overlap `codex-usage` ownership of
  `tests/fixtures/codex_events_real.jsonl`; do not hand-edit around the check.
- Rejected from proposal 1: expanding this section into `cost.py`, which would
  overlap `store-ledger`, and treating the nested reviewer as the live canary.
- What is unproven: the tracked public-surface replay and mutations, a fresh
  host-level authenticated canary, production-length event-only liveness, and
  non-zero Codex tokens reported by `pm_flow.sh cost` after `store-ledger`; the
  intended graph edge remains unrecorded until the ownership conflict is fixed.
