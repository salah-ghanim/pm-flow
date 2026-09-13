### Objective
- Make every new attempt and acceptance decision resolve to its exact inputs, effective environment, authorized reviewer and output.

### Current baseline
- `template/.agentic/pm_flow/agent_exec.sh` records rendered prompts but leaves ambient CLI inputs unrecorded.
- `template/.agentic/pm_flow/export.py` can infer acceptance from criterion mentions.
- The state service supplies immutable revision identities and attributed mutations.

### Deliverables
- Immutable output/input lineage, validated bounded handovers and attempt-read records.
- Prompt and effective environment capture with isolated CLI configuration homes.
- Authorized output-specific assessments and corrected acceptance exports.
- Dispatch hooks usable by production, replay, experiments and evaluators.

### User-visible scenarios
1. Run `zsh tests/knowledge_acceptance_test.sh`; negative prose remains unmet or unresolved, while an authorized assessment satisfies only its reviewed output and revision.
2. Run `zsh tests/knowledge_provenance_test.sh`; repeat one task/base with different prompts or bindings and inspect distinct, complete provenance.
3. Disable raw prompt capture and inspect retained identity plus explicit reconstruction limits.

### Interfaces produced
- Dispatch preparation and completion hooks recording requested and effective settings.
- Versioned instruction-slot vocabulary, environment comparison inputs and attempt-read interface.
- Lineage, assessment and bounded-context service operations.
- Acceptance-aware legacy and database exports.

### Interfaces consumed
- State-service identities, transactions, scope checks and artifact persistence.
- Existing persona composition, binding definitions and agent adapters.

### Scope
- In: provenance, declared inputs and outputs, acceptance authority, configuration isolation and export correction.
- Out: experiment scheduling, comparison verdicts and telemetry transport.

### Non-goals
- A second persona catalog; raw transcripts as handovers; reconstructing unavailable historical prompts.

### Priority
- must-have: Without exact lineage and authorized assessments, acceptance and repeatable comparisons have no reliable subject.

### Owned paths
- template/.agentic/pm_flow/agent_exec.sh
- template/.agentic/pm_flow/access_hook.sh
- template/.agentic/pm_flow/provenance/**
- template/.agentic/pm_flow/export.py
- tests/knowledge_acceptance_test.sh
- tests/knowledge_provenance_test.sh
- tests/database_provenance/**
- docs/database-provenance.md

### Dependencies
- state-service

### Constraints and fixed decisions
- Acceptance text is quoted from `docs/database-workflows-spec.md` at `9236bde`.
- Handovers are capped at 500 words and 8192 bytes; larger evidence remains referenced.
- Run-scoped configuration is seeded only from declared content and required credentials.
- Secrets never enter environment artifacts, logs, exports or handoffs.
- Record absent instruction slots explicitly and requested settings separately from effective settings.
- Experimental drift detection consumes this section’s environment records; its end-to-end acceptance belongs to experiment execution.

### Acceptance
- A4: “Negative prose mentioning A1 remains unresolved/unmet. Authorized assessment of the correct output can satisfy the criterion; old-revision evidence and unauthorized reviewers cannot. `tests/knowledge_acceptance_test.sh` verifies export parity and conflicting assessments.”
- A9: “Every new attempt resolves timeline, job, task revision, prompt revision, environment revision, node, binding and source provenance; interrupted or source-unchanged work has no fabricated produced commit. `tests/knowledge_provenance_test.sh` includes same-task/base runs with distinct prompt or binding revisions.”

### Rejection conditions
- Latest-row-wins assessment logic overrides authority or hides disagreement.
- Ambient settings reach dispatch without declaration and provenance.
- A mutable artifact location substitutes for immutable evidence.

### Open questions
- None.
