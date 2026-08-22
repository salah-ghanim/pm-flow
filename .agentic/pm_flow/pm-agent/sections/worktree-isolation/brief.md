### Objective
Give each section its own git worktree, so sections are genuinely isolated and
can run in parallel.

### Scope
Roughly ninety-five percent of the open-source orchestrator field isolates agents
with git worktrees. pm-flow relies on sections owning disjoint paths, which is
weaker: it depends on every role honouring its brief, and it cannot survive two
sections touching the same file.

Give each section a worktree, run its dispatches there, and merge back on an
accepted result. This is also what makes it safe for pm-flow to work on its own
machinery: a developer rewriting driver.zsh while driver.zsh is executing the run
is a live hazard, and a worktree removes it.

### Priority
- must-have. It is table stakes in this field, it unlocks real parallelism, and
  it is the precondition for pm-flow working on itself safely.

### Owned paths
- template/agentic/pm_flow/driver.zsh

### Dependencies
- green-suite

### Acceptance
- Each section's dispatches run in their own worktree.
- An accepted result merges back to the branch; a rejected one leaves the main
  tree untouched.
- A crashed run leaves no orphaned worktree that blocks the next run.
- Two sections can run concurrently without colliding.
- The suite still passes.

### Rejection conditions
- A failed merge leaves the main working tree dirty or half-applied.
- Worktrees accumulate without cleanup.
- Any file outside driver.zsh is modified.
