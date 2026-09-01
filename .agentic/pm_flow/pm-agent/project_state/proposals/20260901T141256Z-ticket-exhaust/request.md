Owner request. Priority: nice-to-have (first tracker only; more trackers are
follow-up sections, not this one). Make section state visible in the ticket
systems teams already live in, starting with GitHub Issues, without ever making
the tracker the state store — files remain the truth, the tracker is a view.
The field's cautionary example is CCPM, which stores project state in GitHub
Issues and is coupled to one vendor's API and rate limits; pm-flow must not
repeat that.

Wanted outcomes, GitHub first because `gh` is already scriptable and needs no
new auth:

1. Outbound exhaust: a sync step (a `pm-flow` command the driver can also run
   after accepted cycles and status transitions) that creates or updates one
   issue per section — title from the section key and objective, body from the
   structured export of the brief's acceptance state and the latest handoff,
   a comment per accepted cycle, close on `done`, label or reopen on
   `cancelled`/reopen. Idempotent: re-running sync must not duplicate issues or
   comments; store the issue number in the section's own workspace.
2. Inbound: `pm-flow init-section` accepts a GitHub issue or epic reference
   (URL or number) and feeds its title/body/checklist through the existing
   officer-mediated section proposal path — the officer still writes the brief;
   the issue is a request, not a brief.
3. Credentials never enter role prompts: sync runs from the driver or as an
   operator command, in the spirit of `fetch.sh`'s isolation. If `gh` is absent
   or unauthenticated, sync says so and changes nothing — it must never block a
   tick.

Dependency: the boundary-schema section — sync consumes its validated JSON
export rather than parsing markdown itself. Suggested owned paths: a new
`template/.agentic/pm_flow/ticket_sync.*`, its command wiring in `pm_flow.sh`,
driver hook points, a test suite with a stubbed `gh`. Non-goals: Jira, Plane,
Linear, Asana adapters (later sections against the same export), any two-way
state sync, any webhook listener.
