### Objective
Make the test suite run to completion and pass, so every other section has a
working acceptance check.

### Scope
The dispatch-output-path guard test fails at HEAD and has failed since at least
`3b131af`: `assert_output_not_writable` accepts an assignment that grants write
access to the dispatch output path, when it must refuse it. Because the suite
halts at its first failure, exactly one assertion in the whole suite is currently
known to pass and everything behind it is unrun.

Two things have been established since this brief was written, and they change
where the work is.

The two guard assertions in the suite were stale: they expected the tick to fail
outright, but `do_develop` now handles a rejected assignment gracefully - it sets
the assignment aside as `assignment.rejected.md`, writes `rescope_reason.txt`,
returns the cycle to scope, and the tick succeeds. Those assertions have been
rewritten to the current contract.

The guard itself is still not firing. Extracted and run standalone against the
exact fixture the suite writes, `assert_output_not_writable` correctly refuses the
assignment and names the offending path. Inside the harness it does not, so the
rewritten assertion still fails. The most likely cause is that the repo-relative
path the guard computes does not match the path the fixture writes, which would
make the regex look for something that is not there. Confirm that before changing
any pattern.

Then run the suite to the end and fix or quarantine whatever else it surfaces.
Report the full pass/fail list; nobody has seen one since 7 August.

### Priority
- must-have. Without a green suite no other section can prove it did not break
  the engine, and every claim in this project becomes unverifiable.

### Owned paths
- tests/**
- template/.agentic/pm_flow/driver.zsh

Note on the second path: this section was originally scoped to tests only, on the
assumption the tests were stale. Half of them were, but the guard defect is in
`assert_output_not_writable` itself, so the fix cannot land inside tests/. Touch
nothing else in driver.zsh - the telemetry helpers near the top are deliberately
unused and belong to another section.

### Dependencies
- none

### Acceptance
- `zsh tests/pm_flow_test.sh` exits zero.
- The run reports more than one PASS, and the pass/fail list is in the handoff.
- The guard refuses the fixture assignment inside the harness, not merely when
  its logic is extracted and run standalone.
- A prohibition ("`result.md` is not writable") is still not read as a grant, and
  a read-only reference to another cycle's result is still legal. Both are
  already asserted; neither may regress while making the guard fire.

### Rejection conditions
- The guard test is deleted, skipped, or weakened rather than fixed.
- The suite is made to exit zero without actually running to completion.
- Any file outside tests/ and driver.zsh is modified.
- The telemetry helper block in driver.zsh is altered or wired up here.
