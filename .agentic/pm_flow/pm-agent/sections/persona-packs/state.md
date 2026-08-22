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
- The accepted local slice reuses `persona_packs`, content hashes and the
  existing provenance columns. It introduces no parallel store or schema.
- Cycle 004 is `GO` and committed as `aaaf4b9`, merged to main by `1b17900`.
  Local `persona add` and `persona list` now cover manifest validation,
  containment, non-execution, idempotence, edited-content versioning and
  adoption of an identical standalone persona without changing its ID or
  measurement references.
- A different pack cannot claim an identical installed persona. The attempted
  install rolls back atomically while the original ID, provenance and
  measurement references remain intact.
- The saved checks for local installation, standalone adoption and cross-pack
  collision all exit zero. Mutations of adoption and collision handling make
  their assertions fail. The hermetic full suite exits zero.
- Git URL acquisition, update from source and layer-specific seat swapping are
  not implemented.

## Current assignment

- Add `persona add <git-url>` acquisition through the real Git executable while
  preserving the caller's URL and exact installed commit as durable provenance.
- Reuse the accepted validation and installation path after acquisition. Do not
  add updating or seat swapping in this slice.

## Dependencies

- Installer is complete. Its handoff proves stock installs include both owned
  modules and identifies no unproven dependency capability.
- Git URL acquisition can be checked without a network service by installing
  from a committed temporary `file://` repository through the real Git CLI.
