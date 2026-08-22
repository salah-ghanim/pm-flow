# codex-usage handoff

## Outcome

Nothing attempted yet. Reopened after a scope adjudication, not after a failure.

## Decisions

This section was briefly marked blocked on the theory that packaging would move
the files it owns. It does not. The wheel force-includes
`template/.agentic/pm_flow` as package data, so the engine's source files stay
where they are; what packaging changes is how a *host repository* gets them —
install.sh, MANIFEST, the console entry point, and path resolution in
pm_flow.sh.

Packaging's scope was narrowed to those, so this section's owned paths are
disjoint from it and the two can run at the same time. That is now literally
true rather than aspirational: a section-scoped run takes the project lock
shared and its own section exclusively, and every repository-wide git call is
serialised behind one lock.

## Interfaces

None yet.

## Risks

Merging back is per section and conflict-checked before the main tree is
touched, so a collision with packaging would be reported in
`merge_blocked.txt` rather than left half-applied. Watch for it if this section
ever needs a file packaging also edits.

## What is unproven

Everything the brief claims. Nothing here has been attempted.

## Next action

Scope the first assignment.
