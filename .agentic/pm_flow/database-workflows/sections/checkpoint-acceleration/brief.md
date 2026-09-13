### Objective
- Reduce repeated fork preparation for long histories while preserving the transaction log as authority.

### Current baseline
- Timeline replay can reconstruct any committed position from its history.
- The pinned specification permits verified materialized snapshots but does not require them for product completion.

### Deliverables
- Optional verified checkpoint cache integrated through the timeline extension interface.
- Deterministic diagnostics showing reused checkpoint position and replayed suffix.
- Safe fallback when cached content is missing, incompatible or corrupt.

### User-visible scenarios
1. Run `zsh tests/checkpoint_acceleration_test.sh`; fork the same long history with caching disabled and enabled and observe identical state and source heads with fewer historical operations replayed.
2. Remove or corrupt cached content and repeat; observe successful authoritative reconstruction or an explicit integrity failure without production mutation.

### Interfaces produced
- Optional checkpoint materialization provider for existing timeline operations.
- Cache-use diagnostics and invalidation behavior.

### Interfaces consumed
- Timeline reconstruction, checkpoint verification and artifact retention contracts.
- Existing state-service hashes and immutable artifacts.

### Scope
- In: local checkpoint acceleration and its correctness/performance observations.
- Out: changes to replay semantics, distributed caches and new database authority.

### Non-goals
- A prerequisite for migration, experiments or live validation; a fixed wall-clock speed guarantee.

### Priority
- nice-to-have: Without this section, long-history forks require more reconstruction work, but all A1–A26 product guarantees remain intact.

### Owned paths
- template/.agentic/pm_flow/checkpoint_acceleration/**
- tests/checkpoint_acceleration_test.sh
- tests/checkpoint_acceleration_fixtures/**
- docs/database-checkpoint-acceleration.md

### Dependencies
- timelines-replay

### Constraints and fixed decisions
- Schedule after mandatory product outcomes; no must-have section depends on this optimization.
- Cached projections are verified against the log before use and never become a second authority.
- Use existing artifact retention and timeline extension contracts without editing their owned files.

### Acceptance
- A27: On a deterministic history with at least 100,000 transactions and a verified checkpoint within 100 transactions of the requested fork, `zsh tests/checkpoint_acceleration_test.sh` shows identical fork projection hashes and source heads with caching enabled and disabled; the cached fork replays at most the 100-transaction suffix.
- A28: The same command removes, corrupts and version-mismatches cached material; the operator receives authoritative reconstruction or an explicit integrity diagnostic, and production state and source refs remain unchanged.

### Rejection conditions
- Performance depends on skipping verification.
- Cache failure makes an otherwise reconstructable history unusable.
- The optimization delays a mandatory section or expands into another storage service.

### Open questions
- None.
