# persona-cards section PM state

## Current task

- T1 — define the portable optional card schema and validation contract.

## Completed tasks and evidence

- persona-packs is complete and supplies install/version/provenance primitives.
  No card implementation exists yet.

## Active decisions

- Reuse A2A identity/skills vocabulary, not endpoint/runtime fields.
- Author/provenance is a claim unless separately verified.
- Uncarded personas remain valid and executable.
- T2 requires catalog ownership transfer; T4 consumes topology output without
  editing topology-owned code.

## Blockers

- None for T1. T2 awaits catalog ownership transfer from completed persona-packs;
  T4 awaits topology-compare's output contract.

## Next eligible task

- T1 with canonical round trip, forbidden-field matrix, optional-card fallback,
  and provenance-claim labeling.
