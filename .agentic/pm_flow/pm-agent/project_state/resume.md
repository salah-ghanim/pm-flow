# Resume here

Rewritten 2026-08-22 evening. Read this and `plan.md`; you do not need the
conversation that produced them.

## Where the work stands

Shipped, verified, and pushed to `main` (through `0bbf015`):

- **green-suite - done.** `zsh tests/pm_flow_test.sh` exits 0 and runs to
  completion. Seven PASS labels, stable across repeated runs. Every brief's
  "the suite still passes" now means something.
- **worktree-isolation - done.** Each section dispatches in its own git
  worktree under `.git/pm-flow/worktrees/<project>/<section>`, on branch
  `pm-flow/<project>/<section>`. Accepted cycles merge back, rejected ones
  never reach the main tree. Verified in a real run, not only in the suite.
- **installer - done.** Closed on evidence from a fresh install performed for
  the review.
- Earlier: the store, telemetry recording and export, the catalogue,
  manifest-driven install, and the package skeleton (`pyproject.toml`,
  `src/pm_flow/paths.py`, `src/pm_flow/cli.py`; a wheel was built and run from
  a clean venv with no checkout present).

## Two dead hypotheses, recorded so nobody re-derives them

The dispatch-output guard was never defective. **It was never called.**
Project-level work preempts section work unconditionally in `cmd_tick`, and by
the guard fixture's tick 13 dispatches had accrued against a portfolio-review
threshold of 12, so the tick spent itself on a review and returned before
reaching `do_develop`. Neither the `/var` symlink theory nor the space in
`$TEST_ROOT/driver repo` had anything to do with it. `driver.zsh` was not
modified by green-suite.

## What is running

`packaging`, through the flow, scoped with `--section packaging`. It is the
re-baselining: the engine moves out of the repository and into the installed
package, and MANIFEST, `upgrade.py` and the file-lifecycle machinery are either
deleted or justified, because they exist to manage copies that will no longer
exist.

Budget rails are $40 total, $8 per section. Those are rails, not estimates.

## Do these in order

1. **packaging** - in flight. If it stalls, finish it by hand; the brief records
   what already exists so no manager rebuilds `paths.py`.
2. **Re-cut the five blocked sections** against the packaged layout:
   codex-usage, trace-commands, store-ledger, persona-packs, agents-md. They are
   marked `blocked`, not `planned`, so an unscoped run cannot spend budget on a
   scope that is already known to be wrong. Re-cut from each brief's
   *objective*, not by editing `owned_paths.txt` - see the defect below.
3. **Cut the two drafted sections** in `project_state/drafts/`:
   `topology-compare` and `agent-bindings`. They are the plan's headline
   promises and nothing owns them. Their owned paths are deliberately left open
   until packaging has produced the layout they belong to.

## Known defects

- **Editing `brief.md` does not re-derive `owned_paths.txt`.** Scope is captured
  at `init-section` and never refreshed, so a brief and the scope actually
  enforced can disagree silently. Both green-suite and worktree-isolation hit
  this; both files were corrected by hand. A real pm-flow bug, found by using it.
- **`install.sh` overwrites `project_state/resume.md`.** It treats resume.md as
  engine-provided prose alongside `task_contract.md` and `start.md`, and this
  file is authored project state. It leaves a backup named
  `resume.pre-sections.md`, which is misleading. Reinstalling this repository
  destroys this file unless it is restored from git afterwards.
- **An unparseable portfolio review starves sections for up to four ticks.** It
  self-heals - the claim ceiling gives up, `run_portfolio_review` advances the
  baseline and the run continues - so it is not a livelock, but it is four cpo
  dispatches spent on nothing. Bounding the re-ask explicitly belongs to
  whoever owns driver.zsh scheduling.
- **Telemetry is recorded but not wired into dispatch.** The helpers in
  driver.zsh are deliberately uncalled: wiring them regressed the scheduling
  tests with no error on any stream, and the cause is unexplained. Re-wire only
  with a test proving a dispatch still happens.

## Traps that fail silently

Both cost real time; both are commented where they bite.

- `local path` in zsh is tied to `PATH` and empties it for the rest of the
  function, so `git` stops being findable and the code reports success while
  doing nothing.
- `git rev-parse --is-inside-work-tree` prints `false` and exits **zero** from
  inside a `.git` directory, so testing the exit status alone calls a bare
  directory a worktree.
