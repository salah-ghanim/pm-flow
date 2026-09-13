### Objective
- Demonstrate safe migration on a coherent golden-grid snapshot and a complete database-mode cycle on a real target.

### Current baseline
- The pinned specification inventories golden-grid’s older engine, overwritten history and shared live resources.
- pm-agent `real-install` is recorded as blocked; its package-layout migration remains a separate prerequisite.
- Disposable migration and current-flow telemetry are supplied by preceding sections.

### Deliverables
- Declarative target inventory, snapshot procedure, migration checks and rollback procedure.
- Coherent golden-grid snapshot validation.
- A staged real-target cutover and cycle with preserved identities, usage, evidence and source integration.
- Sanitized target, version, manifest, commit and trace evidence.

### User-visible scenarios
1. Run the rollout preflight against the selected target; inspect package provenance, authority mode, writer quiescence and denied live-resource access.
2. Run the snapshot acceptance procedure; compare source and imported identity/usage manifests.
3. At a driver boundary, apply the validated cutover and complete one safe real cycle; inspect state, actual source integration and backend traces.

### Interfaces produced
- Verified real migration manifest and replayable cutover checkpoint.
- Real-target database-mode evidence usable by final experiment validation.
- Operator apply, verification and rollback commands.

### Interfaces consumed
- Legacy migration and runtime cutover.
- Telemetry reconciliation and backend inspection.
- External prerequisite: completed golden-grid package-layout migration owned by pm-agent `real-install`.

### Scope
- In: real snapshot validation and staged state-authority rollout.
- Out: repairing golden-grid’s package installer, brokerage workflows and experiment execution.

### Non-goals
- Treating package migration as state migration; touching the IB paper gateway; live orders.

### Priority
- must-have: Without real migration and cycle evidence, the product’s existing-target adoption guarantee remains unproven.

### Owned paths
- tests/golden_grid_database_test.sh
- tests/database_rollout/**
- validation/database-rollout/**
- docs/golden-grid-database-rollout.md

### Dependencies
- telemetry-continuity

### Constraints and fixed decisions
- Acceptance text is quoted from `docs/database-workflows-spec.md` at `9236bde`.
- This section can proceed independently of general routing and experiment reporting once current-flow prerequisites are satisfied.
- Package-layout migration must finish before state migration; do not infer completion from a handoff.
- No target source paths or installer files are claimed.
- Missing target access requires a current bounded probe and explicit unresolved evidence; disposable fixtures cannot close real acceptance.
- Apply only at a verified safe boundary with the rollback consequence established.

### Acceptance
- A13: “Coherent golden-grid snapshot migration passes identity/usage checks; a real target completes a database-mode cycle with preserved state and source integration. Record target, engine version, base/result commits, migration manifest and inspected traces. Do not substitute a fixture for the live-target evidence.”

### Rejection conditions
- The snapshot is taken from moving state without coherence guarantees.
- A fixture substitutes for the real target.
- Target work touches brokerage resources, loses unknown usage semantics or lacks a verified rollback boundary.

### Open questions
- Which safe real task and target maintenance boundary will the owner designate after package-layout migration?
