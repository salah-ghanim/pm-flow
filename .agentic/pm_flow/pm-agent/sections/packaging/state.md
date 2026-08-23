# packaging section PM state

## Current task

- None. T1–T5 are complete on main; cycle 010 recorded COMPLETE.

## Completed tasks and evidence

- T1 / A1, A3: installed engine and repository-data boundary accepted in
  cycles 003 and 006.
- T2 / A4: local persona overlay and recorded layer provenance accepted in 004.
- T3 / A7, A8: lossless legacy migration and removal of manifest/copy lifecycle
  accepted across 005, 006, and 008.
- T4 / A2, A5: two independently pinned repositories and byte-identical project
  data on upgrade accepted in 007.
- T5 / A1–A8: documented wheel workflow, 10-group engine suite, and 13-group
  packaged-layout suite accepted in 009 and merged at `c2438b4`.

## Active decisions

- Engine code is immutable package content; `.agentic/` is mutable project data.
- `install.sh` remains checkout-provided; a future `pm-flow init` is separate.
- Repository persona files overlay packaged defaults without editing the wheel.

## Blockers

- None. Reviewer shell permissions, worktree heartbeat, PyPI publication, and
  `pm-flow init` are product follow-ups, not incomplete packaging criteria.

## Next eligible task

- COMPLETE. Release shared path ownership and rebaseline dependent sections.
