# persona-packs section PM state

## Current task

- None; T1–T5 are done on `main`.

## Completed tasks and evidence

- T1 / A1, A4: local pack validation, installation, listing, attribution, and
  immutable content versions accepted in cycle 004.
- T2 / A1, A3: real Git `file://` acquisition with URL/commit provenance and
  cleanup accepted in cycle 006.
- T3 / A3, A4: source update retaining old rows/attempts and displaying the new
  version accepted in cycle 008.
- T4 / A2, A4: one-layer swap survives re-sync and reaches dispatch while
  sibling layers, binding, and old attempts remain unchanged; cycle 009 GO.
- T5 / A5: saved regressions and all ten engine suite groups passed in cycle 009.

## Active decisions

- Pack format is one JSON index plus Markdown files; installation never
  executes pack content.
- Content hash, source URL, and commit are durable provenance, not trust claims.
- Cross-pack collisions reject the whole install atomically.

## Blockers

- None.

## Next eligible task

- None; every acceptance ID has evidence above. The next scope call decides
  `COMPLETE`.
