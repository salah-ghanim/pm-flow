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
- Section state - brief, acceptance, handoff - is exportable as validated JSON
  in one command, so an external system consumes the flow without parsing
  markdown, and one schema settles what the flow's own validators accept.
- A section is visible in an external ticket tracker, GitHub Issues first:
  created with its objective, updated on every accepted cycle, closed on
  completion. The tracker is a view; the files stay the truth.
- A plan-level request made while a run holds the driver lock is queued and
  applied at the next safe point, never refused and lost.
- A finished run carries its outcomes, not only its costs: every cycle decision
  the driver parses and a real end time land in the store and the exported
  trace.
- The product's one real install (golden-grid) runs the packaged engine:
  migrated by `install.sh` with project data intact, driven through a real
  cycle, its legacy costs imported and matching, its spans exportable.
- The test suite runs to completion.

## Current position

- Seven of the twelve criteria above are settled on `main`. All thirteen
  suites exit 0 from the officer's own runs, including the two red at review
  007: `packaged_layout_test.sh` (run-detach's three `install.sh` registry
  entries landed; the section closed at cycle 006) and `otel_semconv_test.sh`
  (isolation fixed; the section closed at cycle 008). The Jaeger all-in-one
  (`pm-flow-jaeger`, operator-started) has been up 7 days and re-served the
  `invoke_agent -> chat` tree during the semconv suite's own
  `curl :16686/api/traces?service=pm-flow`.
- Unmet: the three criteria the owner added in `01ea0da` (JSON export,
  tracker view, queued plan requests) and the two recorded above (outcome
  record, real install). Five planned sections own them one-to-one:
  `boundary-schema` → export; `ticket-exhaust` → tracker, waits on
  boundary-schema; `plan-inbox` → queued requests, waits on boundary-schema
  and outcome-record; `outcome-record` and `real-install` wait on nothing.
  All five sit at zero cycles; nothing has dispatched since 2026-08-25
  except the ticket-exhaust registration on 2026-09-01, whose first
  proposal died on a usage limit and was re-run.
- The TSV was retired after its gate ran: `cost.py import` on `pm-agent`
  printed `imported=0` twice (every TSV row already had a store row, reruns
  are no-ops), and the file is archived as
  `runs/cost_ledger.tsv.imported-20260824`, gitignored.
- Documented limits, deliberately not worked around: the store under-counts
  the 2026-08-24 02:17-06:08Z window (the broken reader wrote the same low
  rows to both sinks; import cannot reprice an existing row); no shipped ACP
  agent or stock MCP SDK client has connected, only the suites' protocol
  clients; compare arms have only run on stub projects (`real-install`
  supplies the first real ground); `spent_usd` fails open on a broken
  reader, deferred until capped-arm measurement matters. The runs-left-
  `running`/NULL `ended_at` leak now has an owner: `outcome-record` owns
  `driver.zsh` and must close runs on every exit path.
- Known test defects without a live owner, tolerated: `trace_commands_test.sh`
  has an order-sensitive assertion over an unordered span-id set (passed
  first try this review; `pm_flow.sh` now belongs to `boundary-schema`, so
  `trace-commands` still cannot reopen without overlap — deflake when that
  frees); `maintenance_accounting_test.sh` requires an installed driver at
  `.agentic/pm_flow`, a layout this repository deliberately does not have;
  `persona-cards` closed without the `catalog.py` rewording, so
  `otel-semconv`'s A4 comment exemption stays.
- Live sections: `boundary-schema`, `outcome-record`, `plan-inbox`,
  `real-install`, `ticket-exhaust` — all must-have, all planned at zero
  cycles. `ticket-exhaust` stays must-have by decision at review 008: the
  owner's tracker criterion stands, so the brief's open question is closed.
- Cut: `a2a-binding` and `repo-hooks`. The product does not guarantee an A2A
  seat, a commit-message hook, or an install registry.

## Deliberately out of scope

- A visual editor. The vault format has to survive real use first; the markdown
  is already readable and linkable in Obsidian today.
- Any hosted service. Everything runs locally, against backends the user starts.
- Migrating the driver's file-derived state machine to SQLite. The record moves;
  the state stays where it is.
