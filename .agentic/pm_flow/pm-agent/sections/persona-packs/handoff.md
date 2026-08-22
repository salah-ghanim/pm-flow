# persona-packs handoff

## Outcome

- Cycles 001 and 002 are rejected; no implementation has been accepted or
  committed. Cycle 002's focused adoption behavior is correct, but its required
  hermetic full suite exits 1 reproducibly.

## Decisions

- Fresh-store local installation, listing, idempotence, validation, containment,
  non-execution, and content versioning all passed the saved acceptance script.
- The result does not stand because an identical existing persona is not linked
  to the pack and does not receive the pack's provenance.
- The literal full-suite command also fails under the PM flow's inherited
  project selector, although clearing those variables lets the suite complete.
- Cycle 002 fixes identical standalone-persona adoption in the worktree: the ID
  and `attempts` reference remain stable, all nine provenance fields update, and
  a disabled-update mutant is caught. Cycle 001 acceptance still exits 0.
- The hermetic full suite now reaches the concurrent lock test but exits 1 twice
  with `a project-wide run was allowed while a section run held the project
  lock`. This is outside the section's two owned source paths.
- Two rejected cycles meet the configured consultant threshold. Do not re-issue
  the same assignment.

## Interfaces

- None accepted yet.

## Risks

- Content-addressed reuse can preserve stale standalone metadata unless pack
  adoption updates or otherwise links the existing row.
- The adoption implementation reattributes identical content already assigned
  to another pack; cross-pack collision policy has not been specified or tested.
- The full suite's lock-exclusion check is reproducibly red in the review
  environment even with all inherited PM-flow selectors removed.

## What is unproven

- No cycle result stands. Fresh local-path behavior and existing-content
  adoption pass their focused checks, including mutation, but the full-suite
  acceptance condition remains unsatisfied.
- Git acquisition, update-from-source, and layer-specific swapping remain
  unattempted.

## Next action

- Escalate to a consultant with the exact Cycle 002 evidence. The alternative
  must account for the passing owned-path implementation, the repeated unowned
  lock-test failure, and whether closure requires a dependency handoff to the
  section responsible for suite/locking behavior.
