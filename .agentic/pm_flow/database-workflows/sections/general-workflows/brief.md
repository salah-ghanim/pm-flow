### Objective
- Execute delivery workflows, independent panels and dynamic decomposition through the same restart-safe graph engine.

### Current baseline
- Runtime cutover supplies the current hierarchy, published graph revisions and extension contracts.
- State-service operations support durable groups, firings, task expansion and pinned workflow identities.

### Deliverables
- Conditional routes, explicit bounded loops, deterministic joins and late-result handling.
- PM → design → develop → QA → release example with an isolated deterministic executor and persisted human gate.
- Validated decomposition and pinned subworkflow execution.
- Independently owned scenarios loaded by the shared workflow test command.

### User-visible scenarios
1. Run `zsh tests/workflow_runtime_test.sh`; QA rejects an implementation, rework consumes the exact findings, and approval releases only the reviewed output.
2. Restart during panel completion; inspect one adjudication with frozen selected inputs under all, quorum and deadline policies.
3. Expand a planning task and edit its workflow template; observe validated child tasks and an active run that retains its pinned version.

### Interfaces produced
- Routing and expansion implementations registered through the existing interpreter.
- Versioned delivery, panel and subworkflow examples.
- Persisted join and recursion-policy behavior exposed through the workflow API.

### Interfaces consumed
- Runtime interpreter, publication, job handling and test extension contracts.
- State-service transactions, provenance, assessments and source integration.

### Scope
- In: conditional routing, panel joins, derived review tasks, human gates, decomposition and subworkflows.
- Out: new scheduler, external human-service transports and automatic production release.

### Non-goals
- Arbitrary code embedded in workflow JSON; role-specific execution branches; unbounded recursion.

### Priority
- must-have: Without these graph capabilities, the product cannot execute the required delivery and decomposition scenarios.

### Owned paths
- template/.agentic/pm_flow/workflow_extensions/**
- template/.agentic/pm_flow/workflow_examples/**
- tests/database_workflow_scenarios/**
- docs/database-workflow-examples.md

### Dependencies
- runtime-cutover

### Constraints and fixed decisions
- Acceptance text is quoted from `docs/database-workflows-spec.md` at `9236bde`.
- Conditions use a versioned restricted vocabulary with defined missing-field and ambiguity behavior.
- Persist expected panel membership; late outputs cannot change already dispatched adjudication.
- Re-review executes the existing derived review task; transport retries remain attempts of the same job.
- Child scopes and permissions cannot exceed the parent’s authority.
- Shared scheduler, schema and workflow test entry points remain with their existing owners.

### Acceptance
- A6: “PM → design → develop → QA → release runs without scheduler role-name changes. QA rejection creates a new execution of the implementation task consuming the exact findings; both reviews are executions of the single derived task `<key>/qa`; approval releases only the reviewed output. `tests/workflow_runtime_test.sh` uses an isolated release fixture and persisted human gate.”
- A7: “Three independent panel executions join into one adjudication; all/quorum/deadline policies handle missing, late, failed and duplicate completions deterministically. `tests/workflow_runtime_test.sh` verifies bounded context and no duplicate routing after restart.”
- A8: “A planning task creates validated child tasks/dependencies; subworkflow invocation pins its version. Editing the template cannot alter an active workflow run. `tests/workflow_runtime_test.sh` verifies ownership, recursion limits and concrete dependency acyclicity.”

### Rejection conditions
- Restart duplicates downstream activation or changes selected panel inputs.
- Template edits alter an active run.
- Release can consume an output other than the one approved.

### Open questions
- None.
