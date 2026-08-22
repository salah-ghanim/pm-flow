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
- template/.agentic/pm_flow/driver.zsh
- template/.agentic/pm_flow/agent_exec.sh
- template/.agentic/pm_flow/config.json
- template/.agentic/pm_flow/README.md
- tests/**
- MANIFEST

The original scope named driver.zsh alone. That was wrong by construction and the
correction is recorded here rather than hidden in a commit: a dispatch cannot be
moved to another working tree without a way to tell `agent_exec.sh` where that
tree is, the acceptance says the suite still passes and nothing in `tests/`
covered worktrees at all, a new `isolation` setting that appears in no shipped
config is undiscoverable, and MANIFEST is generated from whatever under
`template/` moved. Note that editing this file does not re-derive
`owned_paths.txt`; that file was corrected by hand, which is the same pm-flow
defect green-suite hit.

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
- Any file outside the owned paths above is modified.
