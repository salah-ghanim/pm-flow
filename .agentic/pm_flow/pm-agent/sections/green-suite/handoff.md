# green-suite handoff

## Outcome

`zsh tests/pm_flow_test.sh` exits 0 and runs to completion. Six PASS labels,
stable across three consecutive runs: dependency scheduling and blocked
sections; headless driver, escalation and parallel rescue; product
decomposition and a full headless project run; section-scoped PM flow; role
personas, agent dispatch and supervision; independent consultant panel and CPO
adjudication. Every brief's "the suite still passes" now means something.

## Decisions

Both recorded hypotheses for the dispatch-output guard were wrong, and so was
the brief. `assert_output_not_writable` has no defect and `driver.zsh` was not
modified. The guard was never called: project work preempts section work in
`cmd_tick`, and by the guard fixture's tick, 13 dispatches had accrued against
a portfolio-review threshold of 12, so the tick spent itself on a review and
returned before `do_develop`. The assertion read the review's output.

Three further defects, all in the fixtures and all older than this section:

- No stub could answer `Task: review the portfolio`, so every review came back
  UNPARSED and was re-asked to the claim ceiling.
- `stub_decompose.zsh` omitted the `### Priority` heading that
  `split_section_blocks` requires, killing the decomposition run.
- A non-zero run inside `$(...)` under `set -e` killed the suite silently. That
  is why this read as "the suite stops after the driver tests".

## Interfaces

`drain_project_work` and `driver_tick` in the suite. Any assertion on a single
section tick must go through `driver_tick`, or it will eventually read a
portfolio review's output instead. Stub portfolio verdicts are derived from the
sections on disk, so a new section needs no fixture change.

## Risks

The stubs read `$PROJECT_ROOT/.agentic/pm_flow/.project-key`. A test that
installs with `--project-key` and then dispatches will glob every workspace;
unknown keys make a review unparseable.

## What is unproven

Nothing above. Each was demonstrated by a full suite run.

## Next action

worktree-isolation, by hand. Then packaging. An unparseable portfolio review
still costs four cpo dispatches and starves sections for four ticks before the
claim ceiling gives up; bounding that belongs to whoever owns driver.zsh
scheduling.
