# Owner request: knowledge-handover

Register exactly one new section named knowledge-handover through the existing
section interface. The owner authorized this extension on 2026-09-06; the plan
now explicitly includes it and supersedes its old exclusion of SQLite state.

Build database-based knowledge and handover management using SQLite, reusing the
existing store instead of creating a separate competing database. The owner
wants to stop modifying tracked project files and creating commits every time
a review, assignment update or handover occurs. Source changes still have Git
commits; operational coordination records should not need them.

Model tasks and immutable task revisions; responsible and accountable seats;
task dependencies; typed, attributed knowledge/evidence and bounded handovers;
reviews and explicit acceptance decisions; intended source/base commit and
produced result commit; and the exact agent identity, CLI, model and effort for
each attempt. Prefer relational identities, foreign keys and queryable fields
for structure, with validated JSON for extensible typed payloads. Knowledge
needs provenance and task scope, not a pool of inherited raw chat transcripts.

Separate a task's objective and acceptance contract from reusable versioned
prompt/persona content and from runtime model bindings. Record the exact resolved
prompt revision/content hash and task revision on every attempt. An operator
must be able to take one task revision and one base commit, create two isolated
checkouts, run different prompt revisions or bindings, and compare acceptance,
quality/evaluation evidence, tokens, cost and outcome commits. Mark unknown cost
and evaluation limits explicitly; do not claim statistically reliable quality
from a single pair. Inputs, evaluator version and relevant environment/data
identities must be captured sufficiently to explain what changed between arms.

Deliver migration/backup/rollback and restart/concurrency checks for existing
projects. After migration, the scheduler and fresh agents must consume the DB
through bounded interfaces; optional Markdown/JSON exports are projections,
not another independently writable truth. A review-only cycle and a fresh-agent
handover must leave tracked-file status and Git HEAD unchanged while proving
that new evidence and the next eligible task survived a restart. Accepted code
must remain attributable to its source commit. Preserve current exported/API
contracts through a deliberate compatibility strategy for consumers.

Expose a stable local interface for workflow-studio to manage tasks, assignments,
dependencies, prompt versions and comparisons. Typed workflow/communication
relationships must have a clear storage ownership split with that next section.
The visual UI itself belongs to workflow-studio, which will be registered next.

CPO integration constraints: continue plan-inbox, ticket-exhaust and real-install.
Do not silently take live owned files or repeat the existing missing-hook-owner
problem. Explicitly allocate eventual scheduler/CLI/store integration and
serialize shared files. Existing task_contract/AGENTS file-only handover and
review-commit rules are the current implementation, not a reason to reject the
owner's requested migration; include their coordinated update at cutover.
The project plan records the observed acceptance-export false positives,
missing accepted-cycle export, unknown Codex cost and stale topology model lists;
reuse or resolve those where they are necessary for this section's acceptance.

Acceptance must include actual CLI/runtime scenarios for migration, zero Git
churn on review, fresh-session handover retrieval, explicit positive/negative
acceptance state, and a same-task/same-commit comparison with distinct prompts.
Keep these two requested capabilities as two sections with bounded ordered
workplans, not an unrequested proliferation of top-level sections.

## Additional owner requirement: end-to-end OpenTelemetry

The owner explicitly requires this setup to work fully with OpenTelemetry for
token tracking. This is a release-blocking acceptance requirement, not optional
instrumentation. Reuse and extend existing OpenTelemetry/OpenInference and
versioned GenAI conventions, retaining compatible trace/export interfaces.
Every task/attempt/agent/model/effort/prompt revision/base commit must correlate
with stored usage and exported spans. Reconcile input/output and provider-
reported cached/reasoning tokens without double counting; unavailable fields
are unknown, never fabricated zero. Cover successful work, failed/rejected
attempts, retries, interruption/resume and concurrent workflow branches.
Persist usage through process restart and collector outage with replay/export
that does not duplicate billing totals. The visual interface must consume the
same authoritative telemetry, not estimate counters independently. Verify a
real backend trace and usage totals against real provider output for every
supported dispatch transport; deterministic automated fixtures alone do not
settle that integration. Protect credentials and distinguish optional prompt
content capture from always-required prompt identity/provenance. Include this
explicitly in the brief's acceptance IDs and in the runtime/UI demonstration.
