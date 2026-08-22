# persona-packs section PM state

## Objective

- Make portable, content-versioned system-prompt packs installable, inspectable,
  swappable by seat layer, and updateable without losing attribution.

## Owned paths

- `template/.agentic/pm_flow/catalog.py`
- `template/.agentic/pm_flow/store.py`

## Plan

- Establish the pack format and local `persona add` / `persona list` lifecycle.
- Add git-URL acquisition and source update while retaining old persona rows.
- Add layer-specific `persona swap` and prove sibling layers are unchanged.
- Run the full suite and mutation-check each accepted capability during review.

## Decisions and evidence

- A pack uses one JSON index plus indexed Markdown files. JSON preserves the
  standard-library-only implementation and avoids extending the deliberately
  small YAML-ish frontmatter parser into a general manifest parser.
- The first slice reuses `persona_packs`, `upsert_persona`, content hashes and
  existing provenance columns. It does not introduce a parallel store.
- No persona-packs implementation has been accepted. At cycle 001 scope, git
  showed no changes to either owned source path, `state.md`, or `handoff.md`;
  only driver-managed status scratch was dirty, so there was nothing to commit.
- Cycle 001 review is `NO_GO`; no implementation was accepted or committed.
  The fresh-store acceptance script exits 0 and a runtime mutation proves the
  forbidden-metadata rejection assertion detects its violation. However, when
  a standalone persona already has the same key and content, `persona add`
  reports it unchanged without setting `pack_id` or propagating pack author,
  licence, version, tags, or source. The assignment's literal
  `zsh tests/pm_flow_test.sh` also exits 1 because the PM environment's inherited
  `PM_FLOW_PROJECT=pm-agent` redirects the suite fixture; clearing inherited
  PM-flow variables lets the unchanged suite complete.
- Cycle 002 review is `NO_GO`; no implementation was accepted or committed.
  The focused adoption check exits 0 and proves that an identical standalone
  persona keeps its ID and measurement reference while all nine pack provenance
  fields are updated. Its isolated no-update mutant exits 1 on those provenance
  assertions, and the saved Cycle 001 behavior exits 0. The required hermetic
  full suite nevertheless exits 1 on two independent review runs at
  `a project-wide run was allowed while a section run held the project lock`.
  That failure is in unowned lock/test behavior and cannot be waived here.
- The current adoption implementation also reattributes an identical persona
  already owned by another pack. Cycle 002 specified only adoption from no pack,
  so cross-pack collision policy remains unproven rather than accepted behavior.

## Current assignment

- Do not re-issue Cycle 002. Two rejected cycles reach the configured consultant
  threshold. Escalate with the passing adoption/mutation evidence, both repeated
  lock-exclusion suite failures, and the unowned-path constraint; seek an
  alternative closure path or an explicit dependency on the section that owns
  the suite/locking behavior.

## Dependencies

- Installer is complete. Its handoff proves stock installs include both owned
  modules and identifies no unproven dependency capability.
- Acceptance is currently held by reproducible failure of the repository's
  project/section lock-exclusion test, outside persona-packs' owned paths.
