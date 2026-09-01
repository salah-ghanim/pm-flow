Owner request. Priority: must-have. Today a plan-level action taken while any
driver run is alive is refused outright: `pm-flow init-section` answered
"another pm_flow driver is already running for project 'pm-agent'" three times
this morning, and the owner had to wait for a section run to finish before the
plan could change. The refusal is correct — creation mutates the registry and
plan, which must not race the driver's own commits — but the request must not
be lost. The owner queues it; the driver executes it at the next safe point.

Wanted outcome: a file-based plan inbox the driver drains at tick boundaries.

1. A queued request is one file dropped into a project inbox directory
   (atomic write, no lock taken, safe while any run is live). First supported
   request kind: create-section, carrying exactly what `init-section` accepts
   today (name plus free-text request body for the officer).
2. `pm-flow init-section` run while a driver holds the lock queues instead of
   refusing, says so, and prints the queued request's path. A `--now` flag can
   keep today's refusal behaviour for an operator who wants the immediate
   attempt or an error.
3. The driver processes pending requests at the same preemption point where
   decomposition and portfolio review already run — project work before section
   work. Draining one request means running the existing officer-mediated
   proposal path; a request that fails (invalid, ownership overlap, officer
   rejects) is moved to a failed/ area with the error recorded, never silently
   dropped, and never retried in a loop.
4. `pm-flow status` shows pending inbox requests so a queued action is visible,
   not forgotten. A queued request survives a crash and a machine restart (it
   is just a file), and draining is idempotent — a request already applied is
   not applied twice.

Design the envelope so other plan actions can join later without a new
mechanism — block/reopen a section, change a priority, request a cut — but
only create-section must work in this section. Non-goals: any UI, any daemon
beyond the existing tick loop, editing live sections mid-cycle, changing lock
semantics. Suggested owned paths: the inbox handling in
`template/.agentic/pm_flow/driver.zsh` and `pm_flow.sh`'s init-section entry,
a new test suite; coordinate with whatever the boundary-schema section defines
for request/record shapes if it exists by then.
