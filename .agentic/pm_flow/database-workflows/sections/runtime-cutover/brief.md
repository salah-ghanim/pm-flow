### Objective
- Run the current product hierarchy as versioned workflow data under database authority through the installed engine.

### Current baseline
- `driver.zsh` coordinates through files; `catalog.py` and `topology.py` encode the current role arrangement.
- State, provenance, replay and migration interfaces are available for integration.
- `src/pm_flow/cli.py` and `pyproject.toml` remain owned by pm-agent `workflow-studio`.

### Deliverables
- Database-mode driver integration and published default, lean and heavy graph definitions.
- Shared interpreter, durable job dispatch and production source integration.
- Knowledge, workflow, timeline and experiment command routing through registered service handlers.
- Consistent authority-aware role guidance and package regression coverage.
- Extension points for routing, experiment jobs and telemetry without later shared-file edits.

### User-visible scenarios
1. Run `zsh tests/knowledge_state_test.sh`; assignment, review and handover survive restart without changing Git HEAD or tracked-file status.
2. Run `zsh tests/workflow_runtime_test.sh`; default, lean and heavy execute their intended sequence, rework, escalation, rescue and terminal paths.
3. Run `zsh template/.agentic/pm_flow/tests/run.zsh` and affected package regressions against legacy and migrated installations.

### Interfaces produced
- Versioned workflow publication and execution API.
- Driver job-handler and routing-extension contracts.
- Packaged command dispatch to the single local service.
- Shared workflow test runner discovering separately owned scenario directories.

### Interfaces consumed
- State-service jobs, reducer and source integration.
- Provenance dispatch and acceptance hooks.
- Timeline replay and migration authority contracts.
- External integration dependency: workflow-studio-owned package CLI forwarding and package metadata, if changes are needed.

### Scope
- In: current-flow cutover, driver/engine CLI integration, graph interpretation, authority guidance and packaged compatibility.
- Out: general delivery/panel/decomposition extensions and edits to other projects’ owned paths.

### Non-goals
- Another scheduler; UI implementation; changing legacy role semantics unnecessarily.

### Priority
- must-have: Without runtime cutover, the database remains an unused store and existing projects cannot operate through it.

### Owned paths
- template/.agentic/pm_flow/driver.zsh
- template/.agentic/pm_flow/pm_flow.sh
- template/.agentic/pm_flow/catalog.py
- template/.agentic/pm_flow/topology.py
- template/.agentic/pm_flow/topologies/**
- template/.agentic/pm_flow/runtime/**
- template/.agentic/pm_flow/roles/**
- template/.agentic/pm_flow/tasks/**
- template/.agentic/pm_flow/project/task_contract.md
- template/.agentic/pm_flow/domains/distressed-tech/task_contract.md
- template/.agentic/pm_flow/domains/distressed-tech/roles/**
- template/.agentic/pm_flow/domains/distressed-tech/tasks/**
- template/AGENTS.md
- template/.agentic/pm_flow/tests/**
- tests/workflow_runtime_test.sh
- tests/database_runtime/**
- tests/packaged_layout_test.sh
- tests/pm_flow_test.sh
- tests/boundary_schema_test.sh
- docs/database-runtime.md

### Dependencies
- legacy-migration

### Constraints and fixed decisions
- Acceptance text is quoted from `docs/database-workflows-spec.md` at `9236bde`.
- Existing `runs` remain scheduler sessions; every execution belongs to a workflow run.
- Derived tasks use `<subject-key>/<node-key>` once per subject; retries and rework retain their distinct meanings.
- Only production jobs move the integration branch.
- Do not claim `src/pm_flow/cli.py`, `pyproject.toml`, installer, inbox or ticket-sync paths.
- Record required package-wrapper changes as external integration dependencies; packaged acceptance remains unproven until the actual installed command works.
- Database-state scenarios use the existing shared test entry point through this section’s own scenario directory.

### Acceptance
- A2: “Assignment, review/assessment and handover updates survive fresh processes with identical Git HEAD and tracked-file status. `tests/knowledge_state_test.sh` verifies database authority and that editing a projection changes nothing.”
- A5: “Default, lean and heavy are represented as versioned graph/binding data with equivalent intended behavior. `tests/workflow_runtime_test.sh` executes sequence, bounded rework, escalation, rescue and terminal paths through the existing driver integration.”
- A14: “Packaged installations support both modes, and the full engine suite `zsh template/.agentic/pm_flow/tests/run.zsh` plus affected root regression suites pass. Updated contracts/role guidance describe the selected authority consistently.”

### Rejection conditions
- Database mode still reconstructs progress from editable projections or requires coordination commits.
- New workflows require scheduler branches named after business roles.
- Package integration bypasses the public state service or overwrites another section’s files.

### Open questions
- None.
