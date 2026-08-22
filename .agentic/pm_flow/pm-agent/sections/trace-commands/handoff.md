# trace-commands handoff

## Outcome

Nothing attempted. The section is blocked on purpose, not stalled.

## Decisions

This brief was cut against a layout where the engine lives inside the
repository, so its owned paths point at files that `packaging` is about to
move or delete. Working it now would be work done twice, and the second time
would be a merge against a tree that no longer has those paths.

It is marked `blocked` rather than left `planned` so an unscoped run cannot
spend budget on a scope that is wrong by construction.

## Interfaces

None yet.

## Risks

Re-cutting must be done from this brief's *objective*, not by editing
`owned_paths.txt`. Scope is captured at `init-section` and never re-derived,
so a brief and the scope actually enforced can disagree silently. That is a real
pm-flow defect, found by using it, and it is why this is a re-cut rather than an
edit.

## What is unproven

Everything the brief claims. Nothing here has been attempted.

## Next action

Re-cut against the packaged layout once `packaging` reports done, then reopen.
