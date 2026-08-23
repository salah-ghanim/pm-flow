## Outcome

The deliverable is on `main` as 4b53d0e and meets every acceptance criterion.
Verified by installing, not by inspection: a fresh install into a repository
that already had a `CLAUDE.md` writes a 58-line `AGENTS.md` carrying the role
router and the repo-wide invariants in full, leaves the pre-existing `CLAUDE.md`
content intact, and leaves a `CLAUDE.md` that imports it with `@AGENTS.md` and
keeps no copy of its own. README describes `AGENTS.md` as the instructions file.
Suite 10 PASS; `manifest.py --check` current at 77 files.

## Decisions

- Cycles 001 and 002 failed for the harness, not the work: this section's
  worktrees were placed under `.git/`, where `manifest.py` enumerated 0 of 74
  template files and agent write controls refuse the paths as sensitive. Those
  worktrees are gone and the branches survive.
- The rescue that followed succeeded and was lost. It committed a complete
  implementation to `pm-flow/pm-agent/agents-md-rescue-1` (a9790f2), then was
  killed before writing its result file, so the driver never reviewed or merged
  it. Its escalation directory has been archived rather than resumed; a panel
  now would re-solve a solved problem.
- Salvaged onto `main`: `AGENTS.md`, the `CLAUDE.md` pointer, the installer's
  file-neutral `merge_managed_block`, the README.
- Not salvaged: that branch's `driver.zsh` worktree placement and `manifest.py`
  path-exclusion fix. `main` reached both independently, with the same
  reasoning, while the branch sat unmerged.

## Interfaces

- `template/AGENTS.md` holds the router and invariants; `template/CLAUDE.md` is
  a managed pointer importing `@AGENTS.md`, so the two cannot drift.
- `install_instructions_file` and `merge_managed_block` in `install.sh` render
  both; a repository that already has either keeps it, backed up once, with the
  managed block merged between the markers.
- `tools/manifest.py` classes both instructions files `seed`.

## Risks

- `install.sh` and `MANIFEST` are also claimed by `packaging`, which is
  mid-flight on both. The work here is committed, so the exposure is a merge
  conflict on packaging's branch, not a race.
- `AGENTS.md` had to be classed `seed`. Classed `engine`, the post-render sync
  copies the raw template back over it and the file exists but is wrong.

## What is unproven

- Behaviour on a repository that already has an `AGENTS.md` rather than a
  `CLAUDE.md` was not exercised; only the existing-CLAUDE and fresh paths were.
- No cycle in this section has ever been accepted, so nothing here has been
  through a section review.

## Next action

Verify the four criteria against the installed artifact and record `COMPLETE`.
Write no implementation: it exists. A section cannot be marked done without a PM
completion review, which is the only thing still owed.
