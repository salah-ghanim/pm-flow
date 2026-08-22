# worktree-isolation handoff

## Outcome

Every section now runs its dispatches in its own git worktree under
`.git/pm-flow/worktrees/<project>/<section>`, on branch
`pm-flow/<project>/<section>`. Accepted cycles commit there and merge back into
whatever branch the main tree has checked out; rejected ones merge nothing and
leave their work on the branch for the next cycle. The suite proves it from the
inside: the developer stub records its own `$PWD`, and the assertion is on that,
not on the driver's report of where it dispatched.

## Decisions

The merge is tested with `git merge-tree --write-tree` before anything is
touched. A merge attempted without that check leaves conflict markers in the
main working tree, which is the one failure this section was forbidden to cause.
On a conflict, or on a main tree with changes the merge would overwrite, nothing
is merged and `merge_blocked.txt` is written beside the section.

Parallel rescue gives each path its own worktree and does **not** merge them
together when several deliver: they are independent attempts at one problem, and
combining them produces a tree no author wrote. The branches are named in
`rescue_branches.txt` and a human chooses.

Orchestration state stays in the main tree. `agent_exec.sh` gained `--work-root`
(the workspace moves, the installation does not) and `--extra-dir` (the cycle
directory travels with the dispatch as an explicit grant).

## Interfaces

`isolation.worktrees` in `config.json`, default true. Off automatically when the
project is not a git repository, and the flow then behaves exactly as before.
`begin_worktree_dispatch` / `end_worktree_dispatch` bracket any dispatch that
should run in a section's tree.

## Risks

Never write `local path` in zsh: the name is tied to `PATH`, and declaring it
local empties `PATH` for the rest of the function, so `git` stops being findable.
That is what made the first working implementation silently do nothing.

## What is unproven

"Concurrently" is interleaved, not simultaneous. The driver ticks one section at
a time, so what the suite proves is separate trees and non-colliding merge-backs,
not two dispatches in flight at once. Nothing else here is unproven.

## Next action

packaging, then re-cut the remaining five sections against the packaged layout.
