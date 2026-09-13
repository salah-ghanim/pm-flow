### Objective
- Run validated experiment replicates concurrently with enforced isolation, recoverable jobs and explicit conflict-checked promotion.

### Current baseline
- Timelines provide checkpoints and forks; runtime and telemetry provide shared execution and usage interfaces.
- Existing `compare.py` performs two sequential whole-project runs with limited overrides.

### Deliverables
- Experiment definition, typed override validation and exact post-fork diffs.
- Seeded interleaved scheduling with stop conditions, budgets and resource allocation.
- Enforced filesystem, credential and network isolation.
- Environment drift detection, pause/resume/cancel and promotion through production acceptance.
- Experiment service operations consumed by reporting and future UI clients.

### User-visible scenarios
1. Run `zsh tests/experiment_definition_test.sh`; invalid designs fail before any timeline, worktree or job is created.
2. Run `zsh tests/experiment_isolation_test.sh`; four replicates overlap while hostile read and denied-side-effect probes fail and are recorded.
3. Run environment and recovery tests; ambient configuration does not leak, undeclared drift is named, and interrupted replicates resume without duplicate publication or billing.
4. Run promotion tests against unchanged and conflicting production state; observe authorized integration or listed conflicts.

### Interfaces produced
- Create, validate, start, pause, resume, cancel, diff and promote experiment operations.
- Immutable experiment designs, typed overrides, replicate stop records and environment-confound records.
- Completed-replicate notification through durable jobs for independent evaluators.

### Interfaces consumed
- Timeline forks and replay fingerprints.
- Runtime scheduler and registered job handlers.
- Provenance configuration isolation and environment records.
- Telemetry usage, rate-limit and correlation records.

### Scope
- In: experiment lifecycle, concurrency, isolation, recovery, environment comparability and promotion.
- Out: evaluator implementations, statistical reports, comparison CLI adapter and visual editor.

### Non-goals
- Another experiment runner; automatic promotion; permission inferred from a production credential being present.

### Priority
- must-have: Without isolated recoverable replicates, the product cannot safely compare controlled changes.

### Owned paths
- template/.agentic/pm_flow/experiments/__init__.py
- template/.agentic/pm_flow/experiments/runtime/**
- template/.agentic/pm_flow/net_exec.sh
- tests/experiment_definition_test.sh
- tests/experiment_isolation_test.sh
- tests/experiment_environment_test.sh
- tests/experiment_recovery_test.sh
- tests/experiment_promotion_test.sh
- tests/experiment_execution_fixtures/**
- docs/database-experiment-execution.md

### Dependencies
- telemetry-continuity

### Constraints and fixed decisions
- Acceptance text is quoted from `docs/database-workflows-spec.md` at `9236bde`.
- Exactly one baseline has no overrides; models are validated without silent substitution.
- Worktree separation alone is insufficient: enforce cross-replicate access denial.
- Non-production brokerage, deployment, release and outbound messaging are denied by default.
- Use the existing scheduler and state service; no direct edits to their owned files.
- Human gates wait or use a declared deterministic stand-in unless external contact is explicitly authorized.
- Environment differences outside declared overrides mark the comparison confounded.

### Acceptance
- A18: “One experiment from one checkpoint has a baseline and arms overriding a task description, a seat binding, a persona stack, an instruction slot, a topology revision and a policy value. Validation rejects an unknown target, a duplicate target in one arm, an unpublished topology, an unavailable model and a missing baseline before any timeline, worktree or job exists. `experiment diff` shows each arm's overrides as exactly the transactions following its fork. `tests/experiment_definition_test.sh`.”
- A19: “Two arms with two replicates each run concurrently with `max_parallel` 4. Each replicate has a distinct timeline, worktree, ref namespace, CLI configuration home and allocated resource set. A probe agent cannot read another replicate's worktree, configuration home or unpublished outputs; its use of a denied credential or network destination is refused and recorded; production and its integration branch are unchanged. `tests/experiment_isolation_test.sh`.”
- A20: “Every experiment attempt records an environment revision whose CLI version, effective model and effort (a Codex `xhigh` request recorded as effective `high`), instruction slot hashes (repository instruction files in its worktree, seeded user configuration, persona layers, output style), tool manifest and attempt reads match the dispatch. A marker placed in the operator's ambient user configuration reaches no attempt. Changing a CLI version or user configuration between replicates without an override marks the comparison `confounded` and names the field. `tests/experiment_environment_test.sh`.”
- A24: “A replicate paused by a provider usage limit, or killed mid-attempt, resumes from its jobs without duplicating accepted outputs, routing effects or billing records, and the interrupted attempt keeps its usage. Cancelling an experiment stops leasing, records each replicate's stop reason and leaves completed evaluations intact. `tests/experiment_recovery_test.sh`.”
- A25: “Promoting one replicate appends production transactions referencing its outputs and produced commit, re-assesses them under production acceptance authority and integrates through a production job. Promotion is refused, listing the conflicts, when production changed the same tasks or paths after the checkpoint. Unpromoted replicates leave production unchanged. `tests/experiment_promotion_test.sh`.”

### Rejection conditions
- Isolation is merely advisory or depends on agents obeying instructions.
- Validation failure leaves runnable resources behind.
- Cancellation discards completed evaluations, or promotion bypasses production acceptance.
- Experimental side effects can reach golden-grid’s live IB gateway.

### Open questions
- None.
