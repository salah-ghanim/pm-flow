### Objective
- A plan-level request made while the driver lock is held is queued as a durable file and applied through the existing officer-mediated proposal path at the next tick boundary, never refused and lost.

### Current baseline
- `pm-flow init-section` under a held lock fails outright: `template/.agentic/pm_flow/pm_flow.sh:890` ("another pm_flow driver is already running").
- `cmd_init_section` (`pm_flow.sh:1665`) and the officer-mediated request→proposal path (`driver.zsh:3632-3704`) exist and work when the lock is free.
- `project_next_action` (`driver.zsh:2976-2990`) already runs project work before section work, but knows only `decompose` and `portfolio-review`.
- No inbox mechanism exists anywhere in `template/` or `tests/` (grep for `inbox`: zero matches); `pm-flow status` shows no queued requests.

### Deliverables
- An inbox directory per project under the flow's runtime state: one request per file, atomic write (temp + rename), no lock taken.
- A request envelope with an explicit `kind`, extensible to later plan actions; only `create-section` (name plus free-text request body, exactly what `init-section` accepts today) is implemented.
- `pm-flow init-section` queues instead of refusing when the lock is held, says so, and prints the queued file's path; `--now` preserves today's immediate-attempt-or-refusal behaviour.
- A drain step at the existing project-work preemption point: each pending request runs the existing officer-mediated proposal path; a failed request (invalid, ownership overlap, officer DECLINE) moves to a `failed/` area with the error recorded, never dropped, never auto-retried.
- `pm-flow status` lists pending inbox requests.
- A suite `tests/plan_inbox_test.sh` wired into `tests/run.zsh`, with fixtures.

### User-visible scenarios
1. Start `pm-flow run`; from a second shell run `pm-flow init-section demo --file req.md`: exit 0, output says the request was queued and prints the file's path; the file exists in the inbox.
2. Same command with `--now`: today's refusal message and nonzero exit.
3. Let the run reach its next tick: the tick log shows a project-level drain, the officer proposal runs, the section appears in `project_state/sections.md`, and the inbox no longer holds the request.
4. Queue a request whose owned paths overlap a live section: after one tick it sits under `failed/` with the error recorded beside it; the following tick does not touch it again.
5. With one request queued, run `pm-flow status`: the pending request is listed by name.
6. Kill the driver between queueing and draining, restart, tick: the request is still applied exactly once.

### Interfaces produced
- The inbox directory layout and request-envelope format (the `kind` field is the extension point for later plan actions).
- The queued-path output of `init-section` and the pending-requests lines of `pm-flow status`.

### Interfaces consumed
- The officer-mediated proposal path and its validate-then-create contract (`driver.zsh:3632-3704`).
- `project_next_action`'s project-before-section preemption (`driver.zsh:2976`).
- The driver-lock check at `pm_flow.sh:890`.
- boundary-schema's request/record schemas, if one covers request envelopes by then.

### Scope
- In: the inbox module, envelope format, queue-on-lock behaviour of `init-section`, `--now`, the tick-boundary drain, failed/ handling, status visibility, the suite.
- Out: implementing any request kind beyond `create-section`; any UI or daemon beyond the existing tick loop; editing live sections mid-cycle; changing lock semantics; `install.sh` registration (owned by real-install).

### Non-goals
- Block/reopen, priority-change, or cut requests — the envelope must admit them, this section must not build them.
- A watcher, poller, or any drain trigger other than the existing tick boundary.
- Retry policy for failed requests; a failed request is terminal until a human re-queues it.

### Priority
- must-have: the plan's completion criterion "a plan-level request made while a run holds the driver lock is queued and applied at the next safe point, never refused and lost" cannot be met without it.

### Owned paths
- template/.agentic/pm_flow/inbox.zsh
- tests/plan_inbox_test.sh
- tests/fixtures/plan_inbox/**

### Dependencies
- boundary-schema
- outcome-record

### Constraints and fixed decisions
- The queue and drain hooks must land in `template/.agentic/pm_flow/pm_flow.sh` (init-section entry) and `template/.agentic/pm_flow/driver.zsh` (tick-boundary drain, status). Both are owned by the sections named under Dependencies; this section starts only after both are done and then claims exactly those two hook sites — do not reopen or weaken their delivered work, including outcome-record's swallow-and-exit-0 telemetry contract and boundary-schema's validators.
- Drain reuses the existing officer-mediated proposal path; no second proposal mechanism.
- Queueing takes no lock; the write is atomic (temp file + rename, the pattern at `driver.zsh:994`); lock semantics are unchanged (owner decision).
- A failed request is moved with its error recorded — never silently dropped, never retried in a loop (owner decision).
- If boundary-schema ships a schema covering request envelopes, the inbox envelope validates against it; otherwise the envelope is documented in the inbox module.
- Inbox files are runtime state under the flow directory, like `runs/` — never committed per-dispatch into the host repository.
- `install.sh` is owned by real-install: hand it the new engine file (`inbox.zsh`) for its copied-engine lists; acceptance here is checked against the checkout.
- These paths are the engine: work happens in a git worktree, merged back after review.

### Acceptance
- A1: with a `pm-flow run` live, `pm-flow init-section` exits 0, prints the queued file's path, and the file exists in the inbox; with `--now` it reproduces today's refusal — checked per scenarios 1 and 2.
- A2: the next tick drains the queue at the project-work boundary through the officer proposal path, and a valid request's section appears in `project_state/sections.md` — checked per scenario 3.
- A3: an invalid or rejected request lands in `failed/` with its error recorded, and a subsequent tick leaves it untouched — checked per scenario 4.
- A4: `pm-flow status` lists pending requests — checked per scenario 5.
- A5: a queued request survives a driver kill and restart and is applied exactly once; re-draining an applied request creates nothing — checked per scenario 6.
- A6: `zsh tests/plan_inbox_test.sh` exits 0 on `main` and `tests/run.zsh` still runs to completion.

### Rejection conditions
- Queueing implemented as waiting for the lock (blocking or polling `init-section`) instead of a durable file the process can abandon.
- A drained `create-section` applied without the officer-mediated validate-then-create path.
- A failed request deleted, overwritten, or retried automatically.
- An envelope that hard-codes `create-section` so a second kind needs a new mechanism.
- Suite green without ever exercising the queue under a genuinely held lock.

### Open questions
- None.
