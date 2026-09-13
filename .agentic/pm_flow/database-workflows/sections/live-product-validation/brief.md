### Objective
- Prove the assembled product through a real parallel experiment and inspectable telemetry across all changed execution paths.

### Current baseline
- Experiment execution, independent reporting, general workflows and real-target cutover have dedicated owners.
- No live database-mode experiment has yet been demonstrated.

### Deliverables
- A pinned real checkpoint and safe task with baseline, instruction-slot and binding arms.
- Three replicates per arm executed against real providers in parallel.
- Independent evaluator evidence, reproducible report and backend traces grouped by arm.
- Packaged end-to-end acceptance runner and operator examples covering the assembled product.
- Bounded observations recorded as MET or NOT MET for the existing acceptance contract.

### User-visible scenarios
1. Run the live experiment preflight; inspect the pinned task, checkpoint criteria, effective bindings, budget and denied production capabilities.
2. Execute the nine-replicate experiment to its declared stop condition and inspect its report and evaluator evidence.
3. Query the real OpenTelemetry backend by experiment and arm; reconcile attempts, provider usage and exported spans.
4. Run the packaged product validation command, including general-workflow and experiment paths; inspect failures without replacing component acceptance.

### Interfaces produced
- Complete live experiment definition, checkpoint identity, engine version, trace IDs, evaluator evidence and report.
- Reproducible operator commands and a bounded product acceptance index.

### Interfaces consumed
- Experiment execution and reporting APIs.
- General-workflow examples and runtime.
- Golden-grid rollout’s verified target/cutover evidence.
- Telemetry live reconciliation procedures.

### Scope
- In: final assembled-product validation, live experiment execution and directly supporting operator guidance.
- Out: implementation fixes in component-owned files and publication or release automation.

### Non-goals
- Fixtures as live evidence; performance or quality claims beyond the declared experiment; production promotion during acceptance.

### Priority
- must-have: Without the live experiment, parallel comparison and changed-path telemetry remain unproven against real systems.

### Owned paths
- tests/database_product_test.sh
- tests/database_live/**
- validation/database-live/**
- examples/database-experiments/**
- docs/database-workflows-operations.md

### Dependencies
- experiment-evaluation-consumers
- general-workflows
- golden-grid-rollout

### Constraints and fixed decisions
- Acceptance text is quoted from `docs/database-workflows-spec.md` at `9236bde`.
- This section owns the live experiment criterion; it rechecks other sections’ criteria without taking ownership or weakening them.
- Real providers and a real backend are required, including changed-path usage reconciliation.
- Missing access is established by a bounded current probe and remains unproven until real execution and inspection succeed.
- No acceptance task requires brokerage or production credentials.
- Report component failures to their sole integration owners; do not patch their paths.
- Store evidence without secrets or forbidden raw content.

### Acceptance
- A26: “On a real database-mode project checkpoint whose selected task is verifiable without brokerage or production credentials, an experiment with a baseline, an instruction-slot arm and a binding arm, three replicates each, runs in parallel against real providers to its stop condition. Store the experiment definition, checkpoint, engine version, per-replicate trace IDs, evaluator evidence and report, and inspect the traces grouped by arm in a real OpenTelemetry backend. Fixtures do not satisfy this criterion.”

### Rejection conditions
- Fewer than three replicates per arm, sequential-only execution or missing backend inspection is presented as completion.
- A quality claim exceeds the declared decision rule.
- Live validation bypasses the installed product or permitted side-effect policy.

### Open questions
- What provider budget and real checkpoint will the owner authorize for the nine-replicate acceptance experiment?
