# pm-flow: the measurement layer for agent team design

## What we are building

pm-flow already orchestrates a headless agent team. This body of work turns it
into the thing the field is missing.

There are roughly 150 open-source agent orchestrators. They have converged on
execution: a git worktree per agent, a board to watch them, a loop that retries
until done. Across that whole field, almost none measure whether the team design
they run actually works. Two mention comparing configurations; neither measures
performance. Four persist anything to a database. One emits telemetry, and it
does so by tracing syscalls from outside.

Academic work has already established that the question matters - topology
materially changes outcomes, and parallelisable work rewards centralisation
while sequential planning punishes every multi-agent variant. But that work
measures topologies on benchmarks. Nothing measures them on your own repository,
with your own work, at your own cost.

That is what we are building. Three things make it possible, and pm-flow is
unusually close to all three:

- a **record** that survives the run, so a finished run can be inspected later
- a **topology** that is addressable, so two arrangements can be compared
- a **persona** that is separable from the model that runs it, so a prompt can
  be swapped, shared, and measured

## The objective

A person should be able to run the same work under two different agent team
designs, see what each cost and where each escalated, swap one agent's system
prompt for somebody else's, re-run, and know whether it helped.

Everything below serves that sentence.

## Principles for this work

- **Adopt before building.** Where a standard exists and is better than what we
  would write, take it: OpenTelemetry and OpenInference for traces, git worktrees
  for isolation, ACP for agent binding, MCP for tools, AGENTS.md for instructions,
  Inspect AI for scoring. Build only the escalation model, the budget ceiling,
  the supervision layer, and the measurement - those are the parts nobody else has.
- **A persona names no model.** A system prompt that names a CLI or a model
  cannot be shared with someone who does not have it. Personas are portable;
  bindings are local; a seat is a persona on a binding.
- **Objective metrics only, and say so.** Separating a real quality difference
  from model noise takes on the order of ten thousand trajectories per arm. Lead
  with cost, tokens, cycles-to-done, rescue rate, abandonment rate and escalation
  depth, where effect sizes are large and measurement is not a matter of opinion.
  Document the limit rather than letting a user over-read three runs.
- **Definitions are markdown; records are SQLite.** Definitions change rarely,
  deserve git history, and are what a person wants to edit. Records are written
  on every dispatch and are unmergeable churn in somebody else's repository.
- **The flow must not rewrite itself mid-run.** Work on pm-flow's own machinery
  happens in a git worktree, reviewed and merged back. Sections owning disjoint
  paths is the normal isolation mechanism, but here the paths are the engine.

## What must be true when this is done

- A finished run can be opened in Phoenix, Langfuse or Jaeger, hours later,
  showing every role, prompt, response, retry, stall, token count and dollar.
- `cost_ledger.tsv` is gone and the host repository absorbs no per-dispatch writes.
- Sections run in isolated worktrees rather than merely disjoint paths.
- A persona can be installed from somewhere else, dropped onto a seat, and
  measured against the one it replaced.
- Two topologies can be run over the same project and compared in one command.
- pm-flow is drivable over MCP and can bind any ACP-compatible agent.
- The test suite runs to completion.

## Current position

- Met: sections run in isolated worktrees outside the repository; the four
  suites exit 0 from the officer's tier (`zsh tests/pm_flow_test.sh`,
  `zsh tests/prompt_quality_test.sh`, `zsh tests/store_ledger_test.sh`,
  `zsh template/.agentic/pm_flow/tests/run.zsh`), with the engine fixtures
  now seeding and reading the store.
- Unmet: backend-readable traces (no OTLP endpoint in `config.json`, no
  `pm-flow trace`), `runs/cost_ledger.tsv` still on disk, no compare, no
  persona measurement, no MCP or ACP surface.
- `store-ledger`: T4 is on `main` (`1c5a301`). The driver's
  `record_dispatch_cost`, `spent_usd` and `dispatch_count` go through the
  store; `git grep cost_ledger -- template` hits only `cost.py:184,191`,
  the import reader, which is legitimate. Remaining to done: delete the
  TSV after proving A1 parity on the live project (`pm-flow cost` after
  import equals the TSV report to the cent on `pm-agent`) and A4 (a
  project at `max_usd` is refused its next dispatch with the store as the
  source).
- Cost-recording integrity: between 02:17Z and 06:08Z on 2026-08-24 the
  cost reader recorded a blank cost for one developer dispatch, $0.00 for
  one review, and ~$0.0022 for five scope dispatches whose historical
  price is $2.7-4.8. `9452a80` keeps the run alive through a broken
  reader; it does not repair the rows. The store carries known-low rows
  for that window, the driver's spend-since-review figure ($2.3986) is a
  third of what the TSV recorded for the same window ($8.74), and budget
  governance under-counts until `store-ledger`'s A1 parity settles which
  totals are right. The TSV must not be deleted before that parity check
  runs against it.
- `trace-commands` and `otel-semconv` each have cycle 001 scope done and
  wait on nothing; their first assignments are next.
- Order of work: `store-ledger` T5 to done, then `topology-compare` (the
  objective) and `agent-bindings`, which wait on it (compare needs cost
  totals, `pm-flow cost` for an ACP attempt needs the rewritten `cost.py`).
  The driver ranks by dependents before recency, so `trace-commands` and
  `otel-semconv` get ticks only while `store-ledger` is not actionable;
  once it is done the four must-haves interleave by least-recent dispatch.
  `persona-cards`, `artifact-quality` and `run-detach` are the live
  nice-to-haves; the driver dispatches must-haves first.
- `run-detach` gets its `pm_flow.sh` routing arm and help line at the first
  portfolio review after `trace-commands` reports done; until then its
  script is invoked directly.
- Cut: `a2a-binding` and `repo-hooks`. The product does not guarantee an A2A
  seat, a commit-message hook, or an install registry.

## Deliberately out of scope

- A visual editor. The vault format has to survive real use first; the markdown
  is already readable and linkable in Obsidian today.
- Any hosted service. Everything runs locally, against backends the user starts.
- Migrating the driver's file-derived state machine to SQLite. The record moves;
  the state stays where it is.
