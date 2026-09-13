### Objective
- Let operators fork historical state and replay recorded work while preserving production and exposing the first divergence.

### Current baseline
- The state service supplies transaction histories, verification, checkpoints’ schema identities and timeline-scoped integration.
- Existing comparison starts from current HEAD rather than an addressable historical checkpoint.

### Deliverables
- Checkpoint creation and inspection at named and arbitrary committed positions.
- Independent forks with source refs, reset leases and explicit replayability limits.
- Verify, recorded and execute replay through the shared service and execution interfaces.
- Fingerprint-based result reuse with source-job attribution.

### User-visible scenarios
1. Run `zsh tests/timeline_fork_test.sh`; fork a named checkpoint and an arbitrary sequence, finish the children and compare production before and after.
2. Run `zsh tests/timeline_replay_test.sh`; unchanged recorded replay invokes no workers, while a policy change reports its first affected decision.
3. Request execution replay from an incomplete imported checkpoint and inspect the missing-input diagnostic.

### Interfaces produced
- Timeline, checkpoint, fork and replay service operations and command handlers.
- Alignment keys, fingerprint comparison and reuse eligibility.
- Replay job-handler interface consuming the same deterministic workflow decisions as normal execution.

### Interfaces consumed
- State-service reducer, operation versions, source integration, immutable artifacts and job lifecycle.
- Shared workflow decision contracts; later runtime modules supply execution handlers through those contracts.

### Scope
- In: independent timeline state, historical source refs, replay and result reuse.
- Out: experiment definitions, statistical comparison and optional snapshot acceleration.

### Non-goals
- Reconstructing missing legacy inputs; free execution replay; production changes from an unpromoted fork.

### Priority
- must-have: Without historical forks and replay, operators cannot repeat or compare work from a fixed checkpoint.

### Owned paths
- template/.agentic/pm_flow/timelines/**
- tests/timeline_fork_test.sh
- tests/timeline_scenarios/**
- docs/database-timelines.md

### Dependencies
- state-service

### Constraints and fixed decisions
- Acceptance text is quoted from `docs/database-workflows-spec.md` at `9236bde`.
- Forks materialize their own state and never read through to a changing parent.
- Leased jobs become queued in a child; in-flight attempts are not copied.
- Recorded replay makes no model calls; execute replay uses the normal job and dispatch contracts.
- Non-production execution denies brokerage, deployment, release and outbound messaging by default.
- Contribute replay scenarios through the state-service-owned test entry point; do not edit that shared file.

### Acceptance
- A16: “Forking production at a named checkpoint and at an arbitrary sequence yields a timeline whose projection hash equals the source's hash at that position and whose source refs point at the checkpoint heads. After the fork runs to completion, production's head sequence, projection hash, jobs and integration branch are unchanged. Forking a non-replayable checkpoint in `recorded` or `execute` mode is refused with the missing inputs listed. `tests/timeline_fork_test.sh`.”
- A17: “`recorded` replay with unchanged definitions reproduces the source's operations, routing decisions and output artifact identities with zero worker invocations. Changing only a rework bound or escalation threshold reproduces history up to the first affected routing decision and reports that position and the differing fingerprint component. With `identical_inputs`, only jobs whose alignment key and fingerprint match reuse results, each marked with its source job, and reused usage is excluded from measured totals. `tests/timeline_replay_test.sh`.”

### Rejection conditions
- Replay silently skips an unknown operation version or divergent input.
- Fork execution changes production jobs, state or integration branch.
- Reused usage appears as newly incurred consumption.

### Open questions
- None.
