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

- The backend render is settled: a Jaeger all-in-one (container
  `pm-flow-jaeger`, operator-started) displays pm-flow runs hours after they
  finished. `pm-flow trace export --otlp http://localhost:4318/v1/traces`
  exits 0 and is idempotent (`exported 0 span(s)` on re-run);
  `curl :16686/api/traces?service=pm-flow` returns role spans (`cpo:
  portfolio review 6`, `pm: handoff topology-compare (attempt 1)` and
  `(attempt 2)`, developer model spans) with token counts, `pm_flow.cost_usd`
  and `input.value` payloads.
- The one open criterion is the suite. Two section suites exit 1 on `main`,
  each reopened with an owner at review 007: `packaged_layout_test.sh`
  (migration leaves `artifact_quality.md`, `cards` and `run_detach.zsh` in
  the flow dir because none is registered in `install.sh`'s copied-engine
  lists; `run-detach` owns the three entries) and `otel_semconv_test.sh`
  (the secondary tree's exported span reports revision v1.37.0 against the
  test's own v1.36.0 sed pin; `otel-semconv` reopened, acceptance
  unchanged). Everything else is green from the officer's own runs:
  `pm_flow_test.sh`, `prompt_quality_test.sh`, `store_ledger_test.sh`,
  `tests/run.zsh` (35/41/32/58/74), `topology_compare_test.sh`,
  `agent_bindings_test.sh`, `trace_commands_test.sh`, `run_detach_test.sh`,
  `persona_cards_test.sh`, `artifact_quality_test.sh`, `codex_usage_test.sh`.
- The TSV was retired after its gate ran: `cost.py import` on `pm-agent`
  printed `imported=0` twice (every TSV row already had a store row, reruns
  are no-ops), and the file is archived as
  `runs/cost_ledger.tsv.imported-20260824`, gitignored.
- Documented limits, deliberately not worked around: the store under-counts
  the 2026-08-24 02:17-06:08Z window (the broken reader wrote the same low
  rows to both sinks; import cannot reprice an existing row); no shipped ACP
  agent or stock MCP SDK client has connected, only the suites' protocol
  clients; compare arms have only run on stub projects; a budget-capped arm
  drops out of `wall_clock_s` (`assert_within_budget` fails via `fail`, so
  `runs.ended_at` stays NULL); `spent_usd` fails open on a broken reader.
  Fixing the last two means reopening `driver.zsh` ownership - deferred
  until capped-arm measurement matters.
- Known test defects without a live owner, tolerated: `trace_commands_test.sh`
  has an order-sensitive assertion over an unordered span-id set (one fail,
  green on re-run; deflake when `trace-commands` can be reopened without
  overlapping `run-detach`'s `pm_flow.sh` ownership);
  `maintenance_accounting_test.sh` requires an installed driver at
  `.agentic/pm_flow`, a layout this repository deliberately does not have;
  `persona-cards` closed without the `catalog.py` rewording, so
  `otel-semconv`'s A4 comment exemption stays.
- Live sections: `run-detach` (nice-to-have, reopened for the three
  `install.sh` registry entries; its `pm_flow.sh` routing arm and
  `run_detach_test.sh` are green on `main`) and `otel-semconv` (must-have,
  reopened for its red suite).
- Cut: `a2a-binding` and `repo-hooks`. The product does not guarantee an A2A
  seat, a commit-message hook, or an install registry.

## Deliberately out of scope

- A visual editor. The vault format has to survive real use first; the markdown
  is already readable and linkable in Obsidian today.
- Any hosted service. Everything runs locally, against backends the user starts.
- Migrating the driver's file-derived state machine to SQLite. The record moves;
  the state stays where it is.
