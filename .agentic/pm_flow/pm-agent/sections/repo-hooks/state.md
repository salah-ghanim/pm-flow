# repo-hooks section PM state

## Current task

- T1 — implement the dependency-free commit-message checker and focused tests.

## Completed tasks and evidence

- Packaging is complete and supplies the installed version/migration contract.
  No hook implementation exists yet.

## Active decisions

- Installation uses local `core.hooksPath`; hooks are opt-in and worktree-safe.
- Driver-generated subjects must become conventional; the checker must not add
  exemptions for current invalid messages.
- Project update reuses packaging migration instead of implementing another.

## Blockers

- None for T1, T3, or T4. T2 awaits `driver.zsh` ownership after codex-usage.

## Next eligible task

- T1. The accepted/rejected table must cover generated, merge, and revert
  subjects and run offline within the latency bound.
