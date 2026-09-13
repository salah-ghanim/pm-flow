# Database state, replayable timelines and workflow experiments

## Mission

- Make project coordination authoritative in SQLite as an ordered transaction
  log, execute versioned task graphs with bounded artifact handovers, replay or
  fork any checkpoint to compare agents, instructions, task descriptions and
  topologies in parallel under independent evaluation, and migrate existing
  projects without loss.
- The outcome contract is `docs/database-workflows-spec.md` at commit `9236bde`:
  §1–§10 define the outcomes and acceptance IDs A1–A26, §11 seeds the
  decomposition. Every section brief quotes the spec text of the acceptance IDs
  it owns, because a fresh section manager reads its brief, not the spec. A spec
  change is adopted only by recording its new commit here.

## Project-wide constraints

- Extend the existing store (`template/.agentic/pm_flow/store.py`). No second
  task database, scheduler, experiment runner or accounting store.
- One authority per project: legacy files or the database. Only the production
  timeline changes authoritative state or moves the integration branch;
  experiment and replay timelines reach production only through promotion.
- Provenance that cutover-era rows reference cannot be backfilled. Timelines,
  transactions, jobs, checkpoints, environment revisions and experiment
  arm/replicate identities exist from the first schema migration.
- Non-production timelines deny brokerage, deployment, release and
  outbound-messaging credentials by default. Golden-grid runs a live IB paper
  gateway; no acceptance run touches it.
- Unknown usage, cost, end times and provenance stay unknown. Overlapping token
  categories are never summed.
- Where the spec requires real providers or a real OpenTelemetry backend
  (A11, A12, A13, A26), fixtures do not substitute.
- The engine is this repository's own machinery. Sections work in isolated
  worktrees, and shared scheduler, store, CLI and export files have one
  integration owner at a time.
- Do not claim paths owned by open pm-agent sections: `workflow-studio`
  (`src/pm_flow/studio/**`, `src/pm_flow/workflows/**`, `src/pm_flow/cli.py`,
  `pyproject.toml`, `ui/workflow-studio/**`), `plan-inbox`
  (`template/.agentic/pm_flow/inbox.zsh`), `ticket-exhaust`
  (`template/.agentic/pm_flow/ticket_sync.*`) and `real-install` (`install.sh`,
  `README.md`, `docs/real-install.md`). A change needed there is recorded as an
  integration dependency.

## Section graph

Seeded from spec §11. The officer may merge or split these, provided every
acceptance ID has exactly one owning section and owned paths stay disjoint.

- State schema and service (T1–T2): transaction log, reducer, projections,
  tasks, jobs and leases. A3, A15.
- Provenance and acceptance (T3): lineage, prompt and environment revisions,
  run-scoped CLI configuration homes, attempt reads, explicit acceptance, export
  correction. A4, A9, A20.
- Timelines and replay (T4): checkpoints, forks, timeline refs and
  verify/recorded/execute replay. A16, A17.
- Legacy import (T5): production-timeline import, backups, replayability
  marking and rollback. A1.
- Runtime cutover (T6): graph interpreter for the current hierarchy,
  database-mode scheduler/CLI/agent context, source integration jobs. A2, A5, A14.
- Consumers and telemetry (T7): compatibility, API client, OpenTelemetry and
  outage recovery. A10, A11, A12.
- Experiments (T8): arms, validation, parallel isolation, side-effect policy,
  evaluators, metrics, report, recovery, promotion and the compare adapter.
  A18–A25.
- General routing (T10–T11): conditional routes, rework, panels and joins, the
  delivery demonstration, decomposition and subworkflows. A6, A7, A8.
- Golden-grid rollout (T9) and live proof (T12). A13, A26.

## Integration order

1. The schema and state-service interface settle before any consumer starts:
   table identities, operation vocabulary and structured error codes.
2. Provenance and timelines build on the state service and run concurrently only
   with disjoint paths.
3. Runtime cutover follows provenance, timelines and legacy import.
4. Consumers and telemetry follow cutover; experiments follow consumers and
   timelines. General routing follows cutover and may run beside experiments.
5. Golden-grid rollout waits for consumers and for golden-grid's package-layout
   migration (pm-agent `real-install`, currently blocked). The live experiment
   comes last.

## Project-level decisions

- 2026-09-13, owner: this project takes over pm-agent `knowledge-handover`
  (cancelled as transferred; its handoff maps A1–A12 onto spec IDs) and the
  experiment backend behind pm-agent `workflow-studio` A9. Workflow-studio keeps
  its interface and consumes this project's API.
- Tasks are independent of topology, model and timeline. A derived task such as
  review, adjudication or release is created once per subject task, keyed
  `<subject-key>/<node-key>`; a re-review is another execution of it.
- Evaluators judge against the criteria pinned at the checkpoint. Assessments
  made inside a replicate are process metrics, never its quality measure.
- Jobs replace claims and the outbox: an execution is business progress, a job
  is the operational work that advances it.
- Quality claims go no further than an experiment's declared decision rule;
  too few samples report `inconclusive`.

## Completion criteria

- Coordination: migrated projects keep task, cycle and evidence identity;
  reviews and handovers cause no Git churn; competing workers and stale leases
  cannot double-publish; acceptance comes only from authorized assessments of
  the exact output (A1–A4).
- Workflows: default, lean, heavy and PM → design → develop → QA → release run
  as versioned graphs without role names in the scheduler; panels, joins,
  decomposition and subworkflows are restart-safe (A5–A8).
- Provenance and consumers: every attempt resolves timeline, job, task, prompt,
  environment, binding and source; existing CLI, MCP, export, cost, trace and
  compare consumers keep working; telemetry reconciles with real providers
  through outages (A9–A12, A14).
- Replay: the log reproduces state at every checkpoint; forks leave production
  unchanged; recorded replay spends nothing and names its divergence point
  (A15–A17).
- Experiments: typed overrides of task description, binding, persona,
  instruction slot, topology and policy validate before anything starts;
  replicates run in parallel, isolated, with recorded effective environments;
  metrics reconcile; blind evaluators, intervals and a declared decision rule
  produce the verdict; interrupted replicates resume; promotion is explicit
  (A18–A25).
- Real targets: a golden-grid snapshot migrates and a real target completes a
  database-mode cycle (A13); a live experiment with three arms and three
  replicates each on a real checkpoint is inspected by arm in a real
  OpenTelemetry backend (A26).

## Next coordination actions

- Decompose the project from the graph above. Each brief quotes its acceptance
  IDs from the spec and names disjoint owned paths.
- After decomposition, confirm no section claims a path owned by an open
  pm-agent section.
