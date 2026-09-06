### Objective

- Make reusable collaborative workflows visually editable, executable through pm-flow, inspectable and comparable with authoritative state and reconciled OpenTelemetry.

### Current baseline

- `src/pm_flow/cli.py` delegates commands to the packaged engine; `pyproject.toml` packages Python modules and engine assets.
- `template/.agentic/pm_flow/topology.py`, `topologies/`, `catalog.py` and `compare.py` provide role configurations, personas and comparison machinery.
- Existing store, telemetry, export and CLI/ACP adapters provide components to extend.
- The driver explicitly dispatches the existing hierarchy; no visual workflow application is exposed.
- `knowledge-handover` is planned and must deliver the authoritative operational SQLite/API boundary.

### Deliverables

- A lightweight local application with installed launch integration, visual editor, backend/API and operational inspection views.
- Versioned workflow definitions describing seats, separate prompt revisions and bindings, responsibility, accountability and typed relationships.
- Runtime relationship interpretation integrated with existing dispatch, isolation, supervision, budgets, persistence and telemetry.
- Default hierarchy and trading-research templates, deterministic research fixtures and reproducible automated checks.
- A real runtime demonstration covering research handovers, review, comparison, recovery and backend-inspected telemetry.

### User-visible scenarios

1. Run `pm-flow --project <key> studio` in an initialized repository. Open the reported local URL, create a workflow, add/remove/name seats, select prompts and bindings, assign tasks and relationships, validate, save and reopen it.
2. Introduce a dependency cycle or ambiguous accountability. Observe a precise validation error and blocked launch. Replace it with valid dependencies and bidirectional communication; validation succeeds.
3. Select the trading-research template, repository, base commit and bounded execution settings. Inspect the launch summary and start. Observe independent research tasks overlap, cited hypotheses reach developers only after prerequisites complete, experiments produce evidence, and a reviewer closes or requests a bounded follow-up.
4. Restart the application and runtime during that run. Reopen its state and resume safely. Edit the template; observe that the existing run retains its pinned version.
5. Duplicate a task at the same task revision and base commit, change one prompt or binding, and launch another arm. Inspect acceptance, evaluation evidence, costs, outcomes and uncertainty beside the original.
6. Export the demonstration trace to a real OpenTelemetry backend. Follow tasks and attempts across concurrent branches and reconcile displayed usage with provider output and persisted records.

### Interfaces produced

- `pm-flow --project <key> studio`, serving the local application and API.
- A versioned workflow contract covering seats, assignments, typed edges, review limits and immutable run pins.
- A relationship-routing interface within pm-flow consuming that contract and producing existing task, attempt, handover, outcome and telemetry records.
- Documented local API operations for workflow versions, validation, launch summaries, launch/resume, inspection and comparison.
- Packaged default and research templates with reproducible sample inputs.

### Interfaces consumed

- `knowledge-handover` APIs for authoritative tasks, assignments, dependencies, knowledge, evidence, prompt revisions, attempts and transactional persistence.
- Existing persona catalog, topology comparison, source checkout isolation, dispatch adapters, supervision and budget controls.
- Existing store-backed cost, trace/export, OpenTelemetry/OpenInference and versioned GenAI conventions.
- Packaged repository/project resolution through `src/pm_flow/paths.py`.

### Scope

- In: visual authoring, workflow version semantics, validation, relationship routing, local API/backend, installed launch, inspection, comparison, recovery and required demonstrations.
- Out: replacing the operational store, independently migrating existing projects, implementing new agent transports, external ticket synchronization or plan-inbox behavior.

### Non-goals

- Hosted services, public deployment, live trading, order placement or deployment of trading systems.
- A separate orchestrator, independent accounting system or alternate writable task store.
- An unrestricted workflow programming language or claims of statistically established prompt superiority from small samples.

### Priority

- must-have: without this section the product cannot satisfy its visual workflow, executable relationship and research-demonstration completion criteria or expose their required measured comparisons.

### Owned paths

- src/pm_flow/studio/**
- src/pm_flow/workflows/**
- src/pm_flow/cli.py
- pyproject.toml
- ui/workflow-studio/**
- tests/workflow_studio_test.sh
- tests/workflow_studio/**
- tests/fixtures/workflow_studio/**
- docs/workflow-studio.md

### Dependencies

- knowledge-handover

### Constraints and fixed decisions

- `workflow-studio` owns workflow definition/version semantics, validation and runtime relationship routing. `knowledge-handover` owns operational persistence, migrations and shared APIs. Persist workflow versions through that authoritative boundary; portable exports are not a competing writable authority.
- Before implementation assignments, establish the consumed API contract from the dependency’s bounded handoff, including immutable workflow references, transactional launch/resume, assignment updates and correlated attempts.
- Reuse existing dispatch, isolation, supervision, budgets, comparison and telemetry. Preserve the CPO/PM/developer hierarchy as a supported default template.
- Dependency edges are acyclic execution prerequisites. Communication edges may be bidirectional and do not independently authorize execution. Review/handover edges define recipients and explicit finite iteration or termination rules.
- Reject missing or ambiguous responsibility/accountability. Multiple responsible seats require explicit execution semantics; each task has one accountable decision owner.
- Pin workflow version, task revision, exact prompt revisions, binding, repository and source commits at launch. Editing a template cannot mutate an existing run.
- Shared integration files remain outside this section’s ownership: `template/.agentic/pm_flow/{driver.zsh,pm_flow.sh,store.py,topology.py,compare.py,catalog.py,export.py,telemetry.py,trace_export.py,cost.py,agent_exec.sh,net_exec.sh}`, its `knowledge/**`, `schemas/**`, `topologies/**`, `roles/**`, `tasks/**` and `tests/**`, and `src/pm_flow/{knowledge/**,mcp_server.py,acp.py,semconv.py}` belong to `knowledge-handover`.
- `install.sh` and `README.md` remain with `real-install`. This section supplies packaged launch integration through its owned CLI/package paths and its own installation documentation and tests.
- Any necessary shared-file change must be delivered by its current owner or receive a recorded CPO ownership transfer after release, before assignment. Coordinate later `driver.zsh`/`pm_flow.sh` changes with plan-inbox and ticket-exhaust; never assign concurrent ownership. A possible later file transfer adds no dependency by itself.
- Prefer React only if it is the simplest maintainable lightweight implementation. Installed operation must include built assets and must not depend on a frontend development server.
- OpenTelemetry and provider usage reconciliation are release-blocking. UI totals read authoritative records. Credentials never enter telemetry; raw prompt capture is separately controlled while prompt identity remains mandatory.
- A missing real provider/backend demonstration remains explicitly unproven; fixtures cannot substitute for it.

### Acceptance

- A1: From an installed package in an initialized repository, `pm-flow --project <key> studio` opens a usable local application with packaged assets; an operator completes scenario 1 without JSON editing or direct SQLite manipulation.
- A2: Save/reopen and application restart preserve seat names, prompt revisions, independent bindings, assignments and typed edges exactly. Changing the template after launch leaves the run’s pinned version unchanged, verified in its inspection view.
- A3: UI and backend both reject missing/ambiguous responsibility or accountability, dangling references, dependency cycles and unbounded review loops before dispatch. Bidirectional communication without a dependency cycle passes.
- A4: Changing configured assignments and relationships changes actual dispatch recipients, readiness and bounded handover delivery. Recorded attempts show independent tasks overlapping and dependent work starting only after its prerequisite succeeds; rejected prerequisites do not release dependent execution.
- A5: The default hierarchy launches through the same integrated runtime and preserves its accepted/rejected cycle behavior, isolation and configured budget enforcement.
- A6: The deterministic research scenario produces cited, testable hypotheses, scoped developer handovers, implemented experiments and results identifying dataset, code, evaluator and configuration. The reviewer demonstrably closes work or requests a follow-up that terminates at its configured bound.
- A7: A real agent-driven research run completes scenario 3 through the app. Inspectable source artifacts, citations, handovers, experiment evidence and reviewer outcomes corroborate execution; no live trading or order placement occurs.
- A8: Interrupt and restart active execution, then resume through the app. Durable task, handover and attempt identities remain intact; completed work is not redispatched, interrupted attempts receive explicit disposition, and concurrent branches neither lose results nor silently duplicate accepted effects.
- A9: Scenario 5 runs isolated comparison arms with identical task revision and base commit while changing the selected prompt or binding. The app displays exact provenance, acceptance results, reproducible quality evidence, costs, outcomes, sample counts and uncertainty from shared records.
- A10: Stored records and exported spans correlate workflow/run, task, attempt, agent/CLI/model/effort, prompt revision and source commits across success, rejection, failure, retry, interruption/resume and concurrent branches. Inspect these paths in automated tests and the runtime demonstration.
- A11: For every supported dispatch transport, real provider output reconciles with persisted records, app totals and traces inspected in a real OpenTelemetry backend. Input/output and provider-reported cache/reasoning usage preserve their semantics; unavailable fields remain unknown and retries or cumulative events do not inflate totals.
- A12: During collector outage and process restart, usage remains durable. Restored export/replay preserves correlated evidence without duplicated billing totals. Verify repeated export, disabled raw prompt capture and absence of credentials in stored/exported telemetry.
- A13: `zsh tests/workflow_studio_test.sh` exits zero covering installed launch, visual interaction, validation, routing, persistence, recovery, research and comparison fixtures. `zsh tests/pm_flow_test.sh` and `zsh template/.agentic/pm_flow/tests/run.zsh` complete successfully after integration; real acceptance evidence for A7 and A11 is recorded separately.

### Rejection conditions

- Graph edits do not govern runtime behavior, or normal operation requires hand-editing JSON.
- A parallel scheduler/accounting stack bypasses existing supervision, isolation, budgets or authoritative storage.
- Template edits alter active runs, or recovery silently repeats completed work.
- Research outputs lack reproducible provenance, or demonstrations use stubs as evidence of real provider/backend integration.
- Missing usage is fabricated as zero, secrets enter telemetry, or unsupported evidence is reported as proven.
- Delivery edits another live section’s paths without a recorded ownership settlement.

### Open questions

- None.
