# green-suite section PM state

## Objective

Make `zsh tests/pm_flow_test.sh` run to completion and exit zero, so every
other section has a working acceptance check.

## Owned paths

- `tests/**`
- `template/.agentic/pm_flow/driver.zsh` (not touched in the end; see below)

## What was actually wrong

Both recorded hypotheses for the dispatch-output guard were wrong, and so was
the brief's framing. `assert_output_not_writable` has no defect. It was never
called.

Project-level work preempts section work unconditionally in `cmd_tick`, and by
the time the guard fixture ran, 13 dispatches had accumulated against a
portfolio-review threshold of 12. The tick spent itself on a portfolio review
and returned before reaching `do_develop`. The assertion then read the review's
output and reported the guard as broken.

The stubs could not answer a portfolio review at all, so the review came back
UNPARSED and was re-asked. That is bounded by `supervision.max_step_claims`
(3), not infinite - the fourth attempt fails, `run_portfolio_review` catches it,
advances the baseline, and the run continues - but it costs four cpo dispatches
and starves every section for four ticks while it happens.

## What was changed

- `tests/fixtures/stub_*.zsh`: all three stubs answer `Task: review the
  portfolio` with a parseable review. Verdicts are derived from the live
  sections on disk (`$PROJECT_ROOT/.agentic/pm_flow/<project-key>/sections/*`,
  skipping `done`/`cancelled`), so the double does not hardcode section names.
- `tests/fixtures/stub_decompose.zsh`: the two decomposed sections gained the
  `### Priority` heading. `split_section_blocks` has required it for a while;
  the fixture predated it, so the decomposition run died with
  `section 'data-model' is missing the 'Priority' heading`.
- `tests/pm_flow_test.sh`: added `drain_project_work` and `driver_tick`. The
  four guard ticks and the guard's scoping run now clear the project queue
  first, using `status` (side-effect free) to read due-ness rather than
  spending a dispatch to discover it.
- `tests/pm_flow_test.sh`: the two NO_GO assertions were stale. The driver now
  reports `NO_GO (developer said PARTIAL; consecutive failures: N)`; the
  assertions matched the older text without the reason.
- `tests/pm_flow_test.sh`: the decomposition run's exit status is captured and
  reported. Under `set -e`, a non-zero run inside `$(...)` killed the suite
  with no output whatsoever, which is exactly why this failure looked like
  "the suite stops after the driver tests".

`driver.zsh` was not modified. The engine defect the brief expected is not
there.

## Result

`zsh tests/pm_flow_test.sh` exits 0 and runs to completion. Six PASS labels,
stable across three consecutive runs:

- dependency scheduling and blocked sections
- headless driver, escalation, and parallel rescue
- product decomposition and a full headless project run
- section-scoped PM flow
- role personas, agent dispatch, and supervision
- independent consultant panel and CPO adjudication

The guard assertions pass on their own merits: `rescope_reason.txt` is written,
names the offending path, `assignment.rejected.md` is set aside, no developer
dispatch is spent, and the prohibition and read-only-reference cases still
dispatch normally.

## Left for another section

An unparseable portfolio review preempts all section work for up to four ticks
before the claim ceiling gives up. It self-heals, so it is not a livelock, but
in a real run that is four cpo dispatches spent on nothing while every section
waits. Bounding the re-ask explicitly (a `governance.portfolio_review_attempts`
ceiling that abandons the review and advances the baseline) belongs to whichever
section owns `driver.zsh` scheduling.
