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

## Current assignment

- Implement and demonstrate local-path `persona add` and `persona list`, with a
  validated manifest and rejection of machine-local binding/tool metadata.

## Dependencies

- Installer is complete. Its handoff proves stock installs include both owned
  modules and identifies no unproven dependency capability.
