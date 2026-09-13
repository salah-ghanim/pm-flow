### Objective
- Move existing projects to database authority without losing identities, evidence or available usage, with a verified rollback boundary.

### Current baseline
- Legacy projects contain Markdown state, cycle artifacts and existing store records.
- State, provenance and timeline services provide the target authority and explicit replayability model.

### Deliverables
- Inventory, dry-run mapping, coherent backup, staged import and atomic authority selection.
- Attributed explicit legacy outcomes, identity reports and unresolved acceptance where no assessment exists.
- Interrupted-import recovery, repeat-apply idempotence and verified restore.
- Safe rollback before new work, and compatible export or explicit refusal after new work.

### User-visible scenarios
1. Run `zsh tests/knowledge_migration_test.sh`; migrate representative legacy variants, including missing registries and contradictory records, and inspect preserved identities and reported ambiguities.
2. Interrupt and repeat apply; observe no duplicate tasks, cycles, artifacts or usage.
3. Restore before new database work, then attempt rollback after new work; observe verified preservation or a precise refusal.

### Interfaces produced
- Migration, backup, restore and rollback service operations and command handlers.
- Versioned migration manifest, identity mapping and replayability report.
- Atomic authority marker and legacy-writer incompatibility contract.

### Interfaces consumed
- State-service schema and transactions.
- Provenance assessment rules and artifact retention.
- Timeline checkpoint and replayability operations.

### Scope
- In: migration mechanisms and representative disposable validation.
- Out: package-layout migration and applying changes to golden-grid.

### Non-goals
- Guessing historical acceptance, cost, end times or source commits; automatic import of edited Markdown after cutover.

### Priority
- must-have: Without lossless migration and safe rollback, existing projects cannot adopt database authority.

### Owned paths
- template/.agentic/pm_flow/migration/**
- tests/knowledge_migration_test.sh
- tests/database_migration/**
- docs/database-migration.md

### Dependencies
- provenance-acceptance
- timelines-replay

### Constraints and fixed decisions
- Acceptance text is quoted from `docs/database-workflows-spec.md` at `9236bde`.
- Import a coherent snapshot; quiesce writers or verify the source cannot change during apply.
- Imported history is attributed to `legacy-import`; missing dispatch inputs remain explicitly non-replayable.
- Backup and restore include managed artifact content.
- Restoring an old snapshot after new work is never labelled lossless without preserving subsequent evidence.

### Acceptance
- A1: “Migration dry-run/apply preserves task, cycle, artifact and available attribution identities; repeat apply creates no duplicates. Imported explicit verdicts appear as attributed outcome codes, and imported cycles without captured inputs are marked not replayable. `tests/knowledge_migration_test.sh` covers legacy variants, ambiguity, interrupted apply and verified backup/rollback.”

### Rejection conditions
- Authority changes before mappings, foreign keys, evidence and usage reconcile.
- An old engine can silently continue writing authoritative legacy state after cutover.
- Rollback discards new evidence or claims replayability for missing inputs.

### Open questions
- None.
