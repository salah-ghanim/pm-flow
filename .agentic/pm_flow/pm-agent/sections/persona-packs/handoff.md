# persona-packs handoff

## Outcome

- Cycle 003 behavior passes all focused, mutation, regression, and full-suite
  checks, but the review is operational `NO_GO`: the required bundled acceptance
  commit cannot be created under the review sandbox's worktree/Git write policy.

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
- Cycle 003 establishes that cross-pack content identity is not permission to
  rewrite provenance. A different pack name claiming the same key, layer and
  body exits 1 and leaves the existing pack, persona, all nine provenance
  fields, persona ID, and measurement reference unchanged.
- The focused Cycle 003 acceptance exits 0. Its temporary-copy mutation disables
  the guard and makes the collision assertions exit 1. Saved Cycle 002 and 001
  checks exit 0, and the independently rerun hermetic full suite exits 0,
  including concurrent lock exclusion.

## Interfaces

- No interface is accepted yet. The candidate implementation proves local pack
  install/list, standalone adoption, and atomic cross-pack collision refusal,
  but remains uncommitted.

## Risks

- Content-addressed reuse can preserve stale standalone metadata unless pack
  adoption updates or otherwise links the existing row.
- Cross-pack provenance protection depends on the new guard; the accepted
  focused mutation check detects its removal.
- Candidate local source-path behavior is validated but uncommitted; git URL
  lifecycle behavior remains unimplemented and unproven.
- The validated Cycle 003 work can be lost until a commit-capable review records
  it with `state.md` and `handoff.md` in the section branch.

## What is unproven

- Acceptance of the validated local-pack foundation remains uncommitted. Git
  acquisition, update-from-source while retaining old attributable persona
  versions, and layer-specific swapping remain unattempted.

## Next action

- Repeat review/commit in an environment allowed to update the dedicated
  worktree's records and Git object store. Do not rework the passing source.
