# Owner request: workflow-studio

Register exactly one new section named workflow-studio through the existing
section interface. The owner authorized this extension on 2026-09-06; the plan
now includes a lightweight local visual workflow app and replaces the earlier
visual-editor exclusion. React is preferred if it is the simplest maintainable
choice; an equally lightweight visual implementation is acceptable.

Let an operator create reusable collaborative environments without hand-editing
JSON: add/remove/name seats, select separately versioned prompts/personas and
agent/CLI/model/effort bindings, assign task responsibility and accountability,
and visually edit typed dependency, communication and review/handover edges.
Make these relationships executable configuration consumed by the real runtime,
not an attractive diagram over the existing hardcoded CPO/PM/developer hierarchy.
Preserve that hierarchy as one supported default template. Existing topology
comparison, store and agent adapters are components to reuse, not duplicate.

Use knowledge-handover's authoritative SQLite/API boundaries for tasks,
assignments, knowledge, evidence, prompt revisions and attempts. Establish a
clear owner for workflow definitions/versions and runtime relationship routing.
The editor should save/reopen a version, validate missing/ambiguous responsibility
or accountability and dependency cycles, instantiate it against a repository and
base commit, show a concrete launch summary, start the real workflow, and inspect
task state, scoped handovers, outcomes and comparisons. Distinguish dependency
edges (acyclic execution prerequisites) from communication edges (which can be
bidirectional) and require bounded/terminating behavior for iterative review.
Changing a template must not silently alter an in-flight run's pinned version.

Primary demonstration: create a trading research environment with researcher
bots reading papers, retaining citations and extracting testable hypotheses;
developers consume the bounded hypothesis handovers, implement experiments or
backtests quickly, record reproducible data/code/evaluator identities and their
results; a reviewer evaluates the evidence and requests a bounded follow-up or
closes the task. Show both concurrent independent tasks and a dependent handover
that starts only after its prerequisite. Use a deterministic sample research
dataset for automated acceptance, plus a real end-to-end runtime demonstration.
This is research/evaluation only, with no live trading or order placement.

Allow duplicating the same task/base commit with a different prompt or binding
and inspecting acceptance/quality evidence, costs and outcomes through the app.
Do not require raw JSON or direct SQLite manipulation for normal workflows.
Include the UI/backend/API and installed/local launch integration needed for an
operator to actually run it; a static mockup or a file-export-only graph editor
does not satisfy the request. A hosted service and public deployment are not
requested. Use a local application consistent with the existing product.

CPO integration constraints: register knowledge-handover as the required
dependency where its API is necessary. Continue existing sections, identify all
shared runtime/CLI integration files explicitly, and serialize ownership rather
than assigning the same file to two live sections. Keep exactly the requested
two new top-level sections; ordered workplan tasks may decompose this capability.
Acceptance must test visual setup and persistence, graph validation, actual
runtime routing from configured relationships, restart, the researcher-to-dev
demonstration, and a prompt comparison against the same source/task revision.

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
