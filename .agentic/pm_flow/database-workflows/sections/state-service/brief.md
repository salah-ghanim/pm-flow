### Objective
- Make project state an attributable, replayable transaction history with safe concurrent work and recoverable source integration.

### Current baseline
- `template/.agentic/pm_flow/store.py` contains the existing schema and accounting records; coordination still depends on files.
- Baseline and acceptance text are pinned to `docs/database-workflows-spec.md` at `9236bde`; named new test commands are deliverables.

### Deliverables
- Versioned migration extending the existing database while preserving existing identities.
- Transaction service, deterministic reducer, projections, bounded queries, jobs, leases and fencing.
- Recoverable source integration through timeline-scoped jobs.
- Published operation, error, extension and schema contracts for subsequent sections.

### User-visible scenarios
1. Run `zsh tests/knowledge_state_test.sh`; competing processes produce one accepted job completion, stale workers are rejected, and interrupted source integration recovers without another merge.
2. Run `zsh tests/timeline_replay_test.sh`; transaction histories reproduce checkpoint and head hashes, and unauthorized projection changes are detected.

### Interfaces produced
- Versioned local state-service requests carrying project, actor, timeline, scope, idempotency key and expected version.
- Stable identities, transaction operations, structured errors and extension contracts for commands, job handlers and workflow decisions.
- Schema identities for timelines, transactions, jobs, checkpoints, environments, experiment arms and replicates from the first migration.
- Shared test entry points that discover separately owned scenario directories.

### Interfaces consumed
- Existing store, artifact, usage, outcome and telemetry records.
- Existing source ownership and driver integration rules.

### Scope
- In: schema authority, transactional mutation, revision identities, access validation, task dependencies, jobs, reducer verification and Git integration recovery.
- Out: legacy parsing, agent environment capture, workflow scheduling and experiment orchestration.

### Non-goals
- A second database, scheduler or accounting system; multi-host coordination; exactly-once provider invocation.

### Priority
- must-have: Without transactional authority and fencing, concurrent coordination and replay cannot be trusted.

### Owned paths
- template/.agentic/pm_flow/store.py
- template/.agentic/pm_flow/state_service/**
- template/.agentic/pm_flow/source_integration.py
- tests/knowledge_state_test.sh
- tests/timeline_replay_test.sh
- tests/database_state/**
- tests/store_ledger_test.sh
- docs/database-state-api.md

### Dependencies
- None.

### Constraints and fixed decisions
- Extend the existing per-project store; retain one production timeline and one authority mode.
- Settle schema identities, operation vocabulary, extension boundaries and errors before dependent sections start.
- All authoritative mutations pass through the service; downstream modules cannot introduce independent SQL mutation paths.
- Unknown historical provenance and usage remain unknown.
- Test complete state-service histories, including panel, decomposition and human-gate operations, without requiring a later scheduler implementation.
- Shared files retain this section as their sole owner; later changes require an explicit integration assignment.
- Schema application requires a coherent backup and a documented compatible rollback boundary.

### Acceptance
- A3: “Invalid references, cross-project access, cyclic concrete dependencies and stale updates are rejected. Competing workers leasing one job produce one accepted completion; a worker with an older fencing epoch cannot complete; a crash between the Git operation and completion of an `integrate_source` job recovers without a second merge. `tests/knowledge_state_test.sh` uses multiple processes.”
- A15: “Every projection change on a timeline belongs to a committed transaction with a contiguous sequence; a mutation attempted outside the state service is rejected or detected by the projection-hash check. For a fixture history containing rework, a panel join, decomposition, a human gate and a crash between dispatch and publication, `verify` replay reproduces the stored projection hash at every checkpoint and at the head. `tests/timeline_replay_test.sh`.”

### Rejection conditions
- Cutover records require identities or provenance that would be invented later.
- A stale worker can publish, projection mutations escape verification, or recovery merges source twice.
- Database transactions remain open during provider calls or Git operations.

### Open questions
- None.
