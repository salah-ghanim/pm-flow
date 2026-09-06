## Assessment

The request makes operational coordination durable in SQLite and separates task revisions, prompt revisions, runtime bindings and source commits so an operator can rerun the same work and compare measured outcomes.

It directly serves the plan’s completion criteria for transactional tasks, evidence and handovers without Git churn; same-task/same-commit comparisons; and mandatory end-to-end OpenTelemetry. It also supplies the local data interface required by the planned visual application. **Must-have** is justified by these explicit criteria.

Bounded probes establish the baseline on `main` at `460f60b`; `git diff main -- template src tests AGENTS.md .agentic/pm_flow/pm-agent/task_contract.md` returned no differences:

- `sed -n '247,430p' template/.agentic/pm_flow/store.py` found existing tasks, dependencies, attempts, content-addressed artifacts, outcomes and persisted spans. Reuse foundation: **MET**. The requested revisioned coordination model: **NOT MET**.
- Targeted `rg` searches and `sed -n '1610,1670p' template/.agentic/pm_flow/driver.zsh` found file-based scope context and commits of section state. Review and handover without Git churn: **NOT MET**.
- `sed -n '362,443p' template/.agentic/pm_flow/export.py` confirmed acceptance inferred from mentions of criterion IDs in prose and no accepted-cycle export. Explicit acceptance evidence: **NOT MET**.
- Targeted probes of `compare.py` found isolated checkouts from one commit, persona swaps and descriptive cost reports, but no immutable task-revision comparison contract. The requested comparison: **NOT MET**.
- Probes of `telemetry.py`, `store.py` and `src/pm_flow/acp.py` found existing usage collection and persisted trace infrastructure. This proposal did not run provider/backend demonstrations; the extended telemetry requirement remains **NOT MET**.

The registry, supplied ownership map and bounded handoffs show no live section covering this outcome. `plan-inbox`, `ticket-exhaust` and `real-install` retain their existing boundaries. The cancelled sections concern A2A binding and repository hooks, neither of which covers this request.

## Section: knowledge-handover

### Objective

- Make task coordination and bounded knowledge transfer authoritative in the existing SQLite store, with reproducible task comparisons and reconciled OpenTelemetry across fresh processes.

### Current baseline

- `template/.agentic/pm_flow/store.py` stores task identities, dependencies, persona/binding definitions, attempts, artifacts, outcomes and spans.
- `driver.zsh` and `pm_flow.sh` coordinate through section files and commit operational state.
- `export.py` produces validated JSON from files but infers acceptance from prose and omits accepted-cycle records.
- `catalog.py`, `compare.py`, `telemetry.py`, `trace_export.py` and the existing protocol adapters provide reusable persona, comparison and measurement infrastructure.

### Deliverables

- Transactional task revisions, assignments, dependencies, attributed knowledge, bounded handovers, reviews and explicit acceptance decisions in the existing store.
- Independent immutable prompt revisions and attempt provenance linking task, prompt, binding, intended base and produced source commits.
- Migration, backup, rollback and runtime cutover with bounded database interfaces for the scheduler and fresh agents.
- Same-task/same-commit comparisons reporting acceptance, evaluation evidence, usage, cost and source outcomes.
- A versioned local interface for workflow-studio and compatible export/API projections.
- End-to-end telemetry integration, operational documentation and executable acceptance scenarios.

### User-visible scenarios

1. Run `pm-flow knowledge migrate --dry-run`, then `pm-flow knowledge migrate` on an existing project. Inspect the migration report and backup: task, cycle and evidence identities survive, and repeating migration creates no duplicates.
2. Record `git rev-parse HEAD` and `git status --porcelain`. Through the knowledge CLI, update an assignment, record a review and publish a handover. Restart the runtime and retrieve the handover and next eligible task. Both Git observations remain unchanged.
3. Record failed evidence mentioning `A1`, then query acceptance and run `pm-flow export --json`: `A1` remains unmet. Record an explicit authorized passing decision with evidence; both interfaces now show it as met.
4. Run the extended `pm-flow compare` with one task revision, one base commit and two distinct prompt revisions. Inspect separate checkout paths and the report linking each arm to its actual prompt, binding, evaluation, usage and outcome commit.
5. Run supported transports against real providers, interrupt and resume work, and temporarily stop the collector. Restore it, run `pm-flow trace export`, and inspect the backend trace against provider usage and stored totals.
6. Run `pm-flow knowledge rollback` against the documented backup on a disposable migrated project. Reopen it with the documented compatible engine and verify the preserved identities and evidence.

### Interfaces produced

- Versioned `pm-flow knowledge` commands for migration, backup/rollback, task and prompt revision management, assignments, dependencies, evidence, reviews, bounded handovers and task eligibility; structured JSON inputs and outputs.
- A stable local callable interface exposing the same operations and authoritative telemetry for workflow-studio, without requiring direct SQL or a second store.
- Extended `pm-flow compare` inputs for pinned task revision, base commit and per-arm prompt/binding revisions, with structured comparison results.
- Compatible `pm-flow export --json`, cost and trace interfaces, plus versioned explicit acceptance and accepted-cycle records.
- Documented relational identities and typed payload contracts for workflow definitions and communication relationships.

### Interfaces consumed

- Existing SQLite store, persona catalog, topology definitions, isolated checkout machinery and source commits.
- Existing section contracts, workplans, evidence and bounded handovers as migration inputs.
- Existing CLI/MCP/ACP dispatch, provider usage, OpenTelemetry/OpenInference mappings and persisted trace export.
- Existing public boundaries used by plan-inbox, ticket-exhaust and the packaged installation.

### Scope

- In: persistence, migration, scheduler and agent cutover, prompt/task provenance, comparison, compatible consumers and telemetry required for these outcomes.
- Out: visual editing, workflow presentation, trading-research content, hosted services and implementation inside other live sections’ owned paths.

### Non-goals

- A parallel orchestrator, competing database or independently writable Markdown mirror.
- Shared raw conversation history as agent memory.
- Statistically reliable quality claims from a single comparison pair.
- Unrelated model-catalog cleanup, historical cost reconstruction or fabricated run end times.
- Reopening A2A binding or repository hooks.

### Priority

- must-have: without this section the product cannot meet its SQLite coordination, zero-Git-churn handover, pinned task comparison and correlated OpenTelemetry completion criteria.

### Owned paths

- template/.agentic/pm_flow/knowledge/**
- template/.agentic/pm_flow/store.py
- template/.agentic/pm_flow/driver.zsh
- template/.agentic/pm_flow/pm_flow.sh
- template/.agentic/pm_flow/export.py
- template/.agentic/pm_flow/schemas/**
- template/.agentic/pm_flow/catalog.py
- template/.agentic/pm_flow/compare.py
- template/.agentic/pm_flow/topology.py
- template/.agentic/pm_flow/topologies/**
- template/.agentic/pm_flow/telemetry.py
- template/.agentic/pm_flow/trace_export.py
- template/.agentic/pm_flow/cost.py
- template/.agentic/pm_flow/watch.py
- template/.agentic/pm_flow/agent_exec.sh
- template/.agentic/pm_flow/net_exec.sh
- template/.agentic/pm_flow/project/task_contract.md
- template/.agentic/pm_flow/project/project_state/README.md
- template/.agentic/pm_flow/roles/**
- template/.agentic/pm_flow/tasks/**
- template/.agentic/pm_flow/domains/distressed-tech/task_contract.md
- template/.agentic/pm_flow/domains/distressed-tech/roles/**
- template/.agentic/pm_flow/domains/distressed-tech/tasks/**
- template/.agentic/pm_flow/README.md
- template/.agentic/pm_flow/tests/**
- template/AGENTS.md
- AGENTS.md
- .agentic/pm_flow/pm-agent/task_contract.md
- src/pm_flow/knowledge/**
- src/pm_flow/mcp_server.py
- src/pm_flow/acp.py
- src/pm_flow/semconv.py
- tests/knowledge_handover_test.sh
- tests/fixtures/knowledge_handover/**
- tests/store_ledger_test.sh
- tests/boundary_schema_test.sh
- tests/topology_compare_test.sh
- tests/otel_semconv_test.sh
- tests/trace_commands_test.sh
- tests/agent_bindings_test.sh
- tests/outcome_record_test.sh
- tests/pm_flow_test.sh
- tests/prompt_quality_test.sh
- tests/packaged_layout_test.sh
- docs/knowledge-handover.md

### Dependencies

- None.

### Constraints and fixed decisions

- Extend the existing SQLite store. Use relational identities, foreign keys and queryable structural fields; validate extensible typed JSON payloads. Enforce task scope and provenance on knowledge access.
- Preserve fresh processes and bounded context. Handovers remain capped at 500 words and 8192 bytes. Database-derived dispatch files may be temporary projections; they cannot become writable authority.
- Existing file-based rules govern unmigrated projects. Update runtime contracts, shipped role guidance and self-hosting instructions together at validated cutover; preserve historical section source and cycle records.
- This section owns store, scheduler, CLI, export and telemetry integration. It supplies the hooks needed by plan-inbox and ticket-exhaust while those sections retain their modules. Shared integration changes are serialized through this owner; any later transfer requires an explicit CPO ownership update before another section edits the file.
- Claim none of the supplied live-owned paths. Preserve packaged-install behaviour without requiring changes to `install.sh`. If a protected-file change proves necessary, resolve its ownership and any genuine acceptance dependency with the CPO before proceeding.
- Keep existing consumers working through a documented compatibility strategy. Correct mention-based acceptance before consumers receive it as evidence; expose stable accepted-cycle identities without making the tracker authoritative.
- Knowledge-handover owns common persistence, migrations, identity/reference validation and stored relationship envelopes. Workflow-studio will own workflow authoring, relationship semantics and execution policy through that interface. It must not introduce separate task, prompt or telemetry authority.
- Reuse existing comparison isolation and persona resolution. Fix model restrictions only where necessary to run supported selected bindings; do not silently substitute a model.
- Prompt identity and provenance are mandatory even when telemetry content capture is disabled. Protect credentials and make content capture explicit.
- Real provider access and a real OpenTelemetry backend are external acceptance requirements. Missing access leaves the relevant criterion unproven; fixtures cannot substitute for it.
- The manager defines one bounded, ordered workplan covering migration, runtime integration and end-to-end validation.

### Acceptance

- A1: After scenario 1, migration preserves existing task, cycle and evidence identities and attribution, reports unsupported or ambiguous legacy records explicitly, and is idempotent. Interrupted migration and scenario 6 demonstrate recoverable backup/rollback without silent data loss.
- A2: Scenario 2 persists assignment, review and handover changes across process restart while tracked-file status and Git HEAD remain identical. The scheduler retrieves the correct next eligible task from SQLite, and a fresh agent proceeds using bounded retrieved context.
- A3: Through the local interface, create and revise tasks, responsible/accountable assignments, dependencies and typed knowledge. Historical revisions remain immutable; invalid references, payloads and dependency cycles are rejected. Concurrent updates and competing task claims produce explicit conflicts or one valid winner without lost evidence or duplicate execution.
- A4: Scenario 3 distinguishes positive, negative and unresolved acceptance through attributable decisions linked to criterion, task revision and evidence. A prose mention never establishes completion, and an older revision’s passing evidence does not silently satisfy a changed contract.
- A5: Every new attempt can be queried by exact task revision, resolved prompt revision/content hash, agent identity, CLI, model, effort and intended base commit. Accepted source changes resolve to their produced commit; rejected, interrupted and source-unchanged attempts report their actual outcome without fabricated commits.
- A6: Scenario 4 runs the same immutable task revision and base commit in separate isolated checkouts with distinct prompts, and also supports a binding-only variation. Its report preserves inputs, evaluator version, environment/data identities, acceptance, evaluation evidence, tokens, costs and outcome commits. Missing measures are explicit and a single pair carries no significance claim.
- A7: Existing export, cost, trace and MCP consumers operate after migration through the documented compatibility strategy. JSON export validates and exposes explicit acceptance and stable accepted-cycle records. Editing a projection cannot change authoritative state.
- A8: A separate local client creates and retrieves tasks, assignments, dependencies, prompt revisions and comparisons using only the published interface. It reads the same telemetry as CLI/export and round-trips typed workflow/communication records under the documented ownership contract.
- A9: Success, rejection, failure, retry, interruption/resume and concurrent branches produce correlated task/attempt/agent/model/effort/prompt/base-commit records and spans. Input/output and provider-reported cache/reasoning usage reconcile without overlapping-token or retry double counting; unavailable fields remain unknown.
- A10: Scenario 5 supplies real provider-output evidence for every supported dispatch transport and inspectable traces in a real OpenTelemetry backend. Backend usage reconciles with provider output and persisted records, including after restart and collector outage; replay does not duplicate billing totals. Fixtures alone do not satisfy this criterion.
- A11: With prompt-content capture disabled, scenario 5 still exposes required identity/provenance while configured prompt/response content and credentials remain absent from telemetry and exports. Enabling permitted content capture preserves credential protection.
- A12: `zsh tests/knowledge_handover_test.sh`, the affected existing regression suites and `zsh template/.agentic/pm_flow/tests/run.zsh` finish successfully. Packaged runtime demonstrations cover both an unmigrated project and a migrated project using the coordinated runtime guidance.

### Rejection conditions

- Operational state is dual-written as independently authoritative files and database records.
- Review-only work requires Git commits, or accepted source loses commit attribution.
- Migration silently invents acceptance, cost, usage, provenance or historical identities.
- A comparison changes its task/base inputs silently or reports quality superiority without supporting evidence.
- Telemetry acceptance relies on UI counters, stubs or an uninspected export instead of real provider/backend reconciliation.
- Delivery takes live-owned files, replaces the orchestrator, weakens existing acceptance or leaves runtime guidance contradicting the selected storage mode.

### Open questions

- None.

## Decision

CUT — knowledge-handover is required by explicit plan completion criteria and extends existing infrastructure without duplicating a live section.
