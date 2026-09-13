### Objective
- Preserve accurate, inspectable provider usage and correlated traces across database execution, retries, outages and restart.

### Current baseline
- `telemetry.py`, `trace_export.py`, `cost.py` and `src/pm_flow/semconv.py` provide existing accounting and telemetry behavior.
- Database attempts now have timeline, job, task, prompt and environment identities.

### Deliverables
- Correlated durable usage and spans for all new execution identities, including experiment dimensions.
- Export jobs using the existing store and recovery behavior.
- Provider-field preservation, idempotent accounting and explicit unknown costs.
- Real provider/backend probe procedures and sanitized reconciliation evidence.

### User-visible scenarios
1. Run the live provider probe matrix and inspect backend traces for success, rejection, retry, interruption/resume and concurrent branches.
2. Run `zsh tests/knowledge_telemetry_test.sh`, interrupt collector availability and restart the runtime; observe retained usage and eventual exports without duplicate billing.
3. Disable raw capture; inspect retained provenance and absence of forbidden content.

### Interfaces produced
- Durable usage and span projection consumed by cost, trace and experiment reporting.
- Export job handler and correlation attributes for experiment, arm and replicate.
- Reusable live reconciliation probes for subsequent changed paths.

### Interfaces consumed
- Runtime job-handler interface.
- State-service accounting records and provenance identities.
- Real supported providers/transports and a real OpenTelemetry backend.

### Scope
- In: telemetry transport, usage semantics, export recovery and real current-flow reconciliation.
- Out: independent quality evaluation and statistical experiment reports.

### Non-goals
- A second accounting store; treating missing usage as zero; fixture-only live validation.

### Priority
- must-have: Without durable reconciled telemetry, operators cannot trust execution cost or experiment measurements.

### Owned paths
- template/.agentic/pm_flow/telemetry.py
- template/.agentic/pm_flow/trace_export.py
- template/.agentic/pm_flow/cost.py
- template/.agentic/pm_flow/requirements-telemetry.txt
- template/.agentic/pm_flow/telemetry_jobs/**
- src/pm_flow/semconv.py
- tests/knowledge_telemetry_test.sh
- tests/database_telemetry/**
- tests/codex_usage_test.sh
- tests/otel_semconv_test.sh
- tests/trace_commands_test.sh
- docs/database-telemetry.md

### Dependencies
- runtime-cutover

### Constraints and fixed decisions
- Acceptance text is quoted from `docs/database-workflows-spec.md` at `9236bde`.
- Preserve input, output, cache and reasoning categories separately; cumulative events and retries cannot double-count usage.
- Estimates name their price revision; unavailable values remain unknown.
- Missing provider or backend access leaves the affected criterion unproven; record the bounded failing probe and the access needed to settle it.
- Later experiment and general-workflow paths must reuse these hooks and receive live reconciliation during final validation.

### Acceptance
- A11: “Real supported provider/transport probes reconcile stored input/output and available cache/reasoning usage with inspected OpenTelemetry traces across success, rejection, retry, interruption/resume and concurrent branches. Store raw probe evidence and backend trace IDs; fixtures alone do not satisfy this criterion.”
- A12: “Collector outage and runtime restart retain usage and pending exports. Repeated export does not duplicate accounting; disabled raw capture retains identity without forbidden content/credentials. `tests/knowledge_telemetry_test.sh` plus real backend/provider inspection establish this.”

### Rejection conditions
- Export retries create billing records, interrupted usage disappears or credentials enter evidence.
- Supported-provider gaps are presented as validated coverage.
- New execution paths introduce independent counters.

### Open questions
- Which real backend and supported-provider accounts will the owner supply for the acceptance matrix?
