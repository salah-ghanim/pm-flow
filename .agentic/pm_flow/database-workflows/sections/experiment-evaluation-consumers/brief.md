### Objective
- Give operators and existing clients reproducible experiment reports based on independent evaluation and reconciled measurements.

### Current baseline
- Experiment execution supplies isolated replicates and durable lifecycle records.
- Existing CLI, MCP, export, cost, trace and compare consumers need a compatible database-backed interface.

### Deliverables
- Pinned independent evaluators with blind inputs and checkpoint criteria.
- Reconciled metrics, seeded uncertainty intervals and declared decision rules.
- Experiment reports and a two-arm `pm-flow compare` adapter.
- Versioned package API bridge, MCP compatibility and a separate API-only example client.

### User-visible scenarios
1. Run `zsh tests/experiment_evaluation_test.sh`; task-changing arms face checkpoint criteria, blind evaluator inputs reveal no arm identity, and evaluator usage remains separate.
2. Run metrics and report tests; known distributions yield reproducible intervals, while insufficient samples yield `inconclusive`.
3. Run `zsh tests/knowledge_api_test.sh`; existing consumers operate in both modes, an independent client uses the published API, and `pm-flow compare` returns a two-arm experiment report.

### Interfaces produced
- Evaluate and report handlers using existing durable jobs.
- Versioned metrics/report schema with evaluator evidence, uncertainty, confounds and baseline differences.
- Package API bridge and MCP adapters.
- Existing compare interface backed by experiment operations.

### Interfaces consumed
- Experiment lifecycle, definitions, stopped replicates and environment records.
- Telemetry’s authoritative attempt and usage records.
- Provenance exports and assessment lineage.
- External workflow-studio CLI forwarding where its owned package wrapper requires integration.

### Scope
- In: evaluator execution, metrics, reports, comparison adapter and public consumer compatibility.
- Out: experiment scheduling, accounting ingestion and UI implementation.

### Non-goals
- Quality scores from a replicate’s own reviewers; broader statistical guarantees; another API authority.

### Priority
- must-have: Without independent evaluation and compatible reports, experiments cannot support trustworthy operator decisions.

### Owned paths
- template/.agentic/pm_flow/experiments/analysis/**
- template/.agentic/pm_flow/compare.py
- template/.agentic/pm_flow/watch.py
- src/pm_flow/database_api.py
- src/pm_flow/mcp_server.py
- tests/experiment_metrics_test.sh
- tests/experiment_evaluation_test.sh
- tests/experiment_report_test.sh
- tests/knowledge_api_test.sh
- tests/topology_compare_test.sh
- tests/experiment_analysis_fixtures/**
- examples/database-client/**
- docs/database-experiment-reports.md

### Dependencies
- experiment-execution

### Constraints and fixed decisions
- Acceptance text is quoted from `docs/database-workflows-spec.md` at `9236bde`.
- Evaluators judge checkpoint criteria and run identically across replicates.
- Preserve separate overlapping token categories and unknown costs.
- Quality verdicts follow the declared rule; insufficient samples remain inconclusive.
- Existing export, cost, trace, scheduler and package CLI files retain their assigned owners.
- Workflow-studio, plan-inbox and ticket-exhaust consume these APIs; integration needs are reported without editing their paths.

### Acceptance
- A10: “Existing CLI, MCP, export, cost, trace and comparison consumers work on legacy and migrated projects; `pm-flow compare` produces a two-arm experiment report. A separate local client uses only the published API. Relevant existing regression suites and `tests/knowledge_api_test.sh` pass.”
- A21: “Each replicate's input, time, cost and flow metrics reconcile with attempts, provider output and exported spans. Token categories are reported separately and never summed across overlapping categories; queue, active, API and throttled time are distinct; unknown cost stays unknown and estimated cost names its price revision; rework, escalation and rescue counts derive from node keys and outcome codes, not role names. `tests/experiment_metrics_test.sh`.”
- A22: “Pinned evaluators run identically on every replicate after it stops. A blind evaluator's recorded prompt and inputs contain no arm key, override content or timeline identity; an arm that revises a task is evaluated against the checkpoint's criteria; evaluator usage is reported apart from arm cost; assessments by a replicate's own nodes appear only as process metrics.”
- A23: “With deterministic fixture arms of known distributions, the report shows per-arm sample count, median, mean, dispersion and 95% intervals (Wilson, seeded bootstrap) plus differences from baseline, reproducible from the recorded seed. The decision rule returns `inconclusive` below its sample minimum and `better` or `worse` only when the difference interval excludes zero. Start order, concurrency overlap, rate-limit events and cache-read share are reported per arm. `tests/experiment_report_test.sh`.”

### Rejection conditions
- Reports rank quality without independent evaluator evidence.
- Blind inputs leak arm identity, or changed task criteria weaken evaluation.
- Compatibility adapters create separate scheduling or accounting behavior.
- An unavailable external integration is reported as passing.

### Open questions
- None.
