## Outcome

Cycles 004, 006 and 007 are accepted and merged. `MANIFEST` and `upgrade.py` are
gone from `main`; a repository now holds project data only and the engine comes
from an installed wheel. Cycle 008 is delivered and awaiting review.

Six of the brief's seven acceptance criteria have evidence in the running
system: the installed `pm-flow` command runs the packaged engine with no file
copying; a repository holds only config, overrides, state and store; a
repository-local persona overlays the packaged one and the record names the
layers; the full suite runs to completion through the wheel entry point; an
existing copied-engine install migrates losslessly and keeps running; and two
repositories pin different versions while upgrading one leaves its `.agentic/`
untouched. The seventh - that a checkout does not document machinery it no
longer has - is what cycle 008 is being reviewed for.

## Decisions

- Cycle 005's implementation was completed by a dispatch that died before
  writing `result.md`. It was recovered from the worktree as `d415128` and the
  branch was brought up to `main` in `c10f76e`, resolving `MANIFEST` as deleted
  because the assignment asks for that deletion by name.
- Cycle 005 was rejected `NO_GO` for the harness, not the work: one mandatory
  suite run failed a wall-clock concurrency assertion and passed unchanged on
  rerun. Cycle 006 replaced that assertion with a two-way rendezvous in which
  each seat writes its marker only after observing the other, both directions
  asserted, with a poll ceiling that only prevents deadlock.
- Ownership was widened to `tools/manifest.py` and the manifest passages of
  `README.md` after cycle 005 exposed a deadlock: a rejection condition requires
  the file-lifecycle machinery to be deleted or justified, and the tool that
  regenerates `MANIFEST` sat outside the allowlist.

## Interfaces

- `tests/packaged_layout_test.sh` is the installed-artifact harness: offline
  hashed wheelhouse, separate build and runtime venvs, data-only fixtures.
  Cycle 008 reports it at thirteen PASS groups.
- The installed `pm-flow` command resolves its engine from the venv and mutable
  project state from the repository it is invoked in.

## Risks

- The checked-in build wheelhouse must track Hatchling's Python 3.11+ closure.
- The harness needs a Python providing `venv`/`ensurepip`.

## What is unproven

- Cycle 008 has not been reviewed. Its README and manifest-tool changes, and the
  three PASS groups it adds, carry no verdict yet.

## Next action

Review cycle 008. If it stands, every brief criterion has evidence and the
section is ready for a completion review rather than another assignment.
