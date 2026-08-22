# worktree-isolation section PM state

## Objective

Give each section its own git worktree, so isolation is structural rather than
contractual, and so pm-flow can work on its own engine safely.

## Owned paths

Corrected from `driver.zsh` alone; see `brief.md` for why. Now: driver.zsh,
agent_exec.sh, config.json, README.md, tests/**, MANIFEST.

## What was built

- `agent_exec.sh --work-root <dir>` moves the workspace without moving the
  installation: the role's cwd, granted root and sandbox boundary all become
  that directory, while config.json, personas and task files still come from the
  installed flow directory. That is what lets a developer edit the worktree's
  copy of the engine instead of the one executing the run.
- `agent_exec.sh --extra-dir <dir>` (repeatable) grants one more directory. On
  codex it is a prompt-level boundary only, like its scoped tier.
- `driver.zsh`: worktree lifecycle (create, reuse, ff-sync, commit, merge back,
  remove, prune), `begin_worktree_dispatch`/`end_worktree_dispatch`,
  `CONTEXT_PATH_STYLE` so prompts name context by a path that resolves from the
  worktree, and `section_tree_root` so orphan detection watches the tree the
  dispatch actually changed.
- Merge discipline: `git merge-tree --write-tree` decides before anything is
  touched. Conflicts and dirty-tree refusals write `merge_blocked.txt` and leave
  the main tree exactly as it was.
- Rescue: one worktree per path, created before forking because `git worktree
  add` takes a repository-wide lock. Several delivered paths are never merged
  together; `rescue_branches.txt` names them.
- `config.json` ships `isolation.worktrees: true`; README documents the whole
  arrangement.
- `tests/fixtures/stub_worktree.zsh` plus a new suite block.

## Decisions and evidence

The suite block asserts from inside the dispatch: the stub records its own `$PWD`
and the test asserts on that. It also plants a leftover directory where a
worktree belongs before the first run, which is what a killed run leaves behind,
and asserts the next run reclaims it.

Two defects found while building this, both mine, both worth remembering:

- `local path` in zsh ties to `PATH` and empties it for the rest of the
  function, so `git` stopped being findable and every worktree call failed
  silently. Every local was renamed to `tree_path`.
- `git rev-parse --is-inside-work-tree` prints `false` and exits **zero** from
  inside a `.git` directory. Testing only the exit status called a bare
  directory a worktree. The check is now on the output, and on the path being
  its own `--show-toplevel`.

## Result

`zsh tests/pm_flow_test.sh` exits 0 with seven PASS labels, stable across three
runs. New label: "per-section git worktrees, merge-back, and cleanup".

## What is unproven

"Concurrently" means interleaved ticks, not two dispatches in flight. The driver
ticks one section at a time by design, so the suite proves separate trees and
non-colliding merge-backs, not simultaneity.
