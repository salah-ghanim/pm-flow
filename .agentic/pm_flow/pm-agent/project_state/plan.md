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
- **Operational knowledge belongs in SQLite.** Tasks, responsibilities,
  dependencies, reviews, evidence and bounded handovers must survive fresh
  processes without tracked-file churn or a commit for each review. Version
  prompts independently from task contracts and bind attempts to exact source
  commits. Portable definitions and explicit exports may remain files; avoid
  competing writable sources of truth. This owner decision supersedes the
  previous Markdown-state restriction once the migration is validated.
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
  completion. The tracker is a view; the authoritative local project store stays
  the truth (files until the validated knowledge-store migration).
- A plan-level request made while a run holds the driver lock is queued and
  applied at the next safe point, never refused and lost.
- A finished run carries its outcomes, not only its costs: every cycle decision
  the driver parses and a real end time land in the store and the exported
  trace.
- The product's one real install (golden-grid) runs the packaged engine:
  migrated by `install.sh` with project data intact, driven through a real
  cycle, its legacy costs imported and matching, its spans exportable.
- OpenTelemetry is mandatory across every supported dispatch and workflow path,
  including the new database/API/UI paths: task, attempt, agent/model/effort,
  prompt version and source commit remain correlated in spans and persisted
  records. Input/output and provider-reported cache/reasoning token usage must
  reconcile without retry double counting or representing missing usage as zero.
  Success, rejection, retries, errors, interruption and resume must remain
  observable. Unsupported token fields are explicitly unavailable. Exported
  traces must be inspected in a real OpenTelemetry backend and reconcile with
  provider usage and local records, including after restart or exporter outage.
  No new workflow backend can be declared complete on a UI counter or stub-only
  token evidence. Secrets must not be copied into telemetry.
- The test suite runs to completion.
- Tasks, responsible and accountable assignments, dependencies, knowledge,
  acceptance evidence and handovers persist transactionally in SQLite. A review
  and a fresh-agent handover cause no tracked-file modification or Git commit;
  accepted source changes still retain their source commits. Existing projects
  migrate without losing task, cycle or evidence identity.
- A task revision and its target/base commit are independent of immutable prompt
  revisions and agent/CLI/model/effort bindings. Re-run that same task and commit
  with a different prompt or binding in isolated checkouts, then compare measured
  cost, acceptance results and evaluation quality with provenance and uncertainty.
- A lightweight local visual application lets an operator create, edit, validate,
  save, reopen and launch reusable collaborative workflows. Responsibility,
  accountability, communication and dependency relationships are explicit data
  interpreted by the runtime, not just a diagram over a fixed hierarchy.
- From the visual application, instantiate a trading-research example with paper
  researchers handing cited hypotheses to developers who implement and evaluate
  them, and a reviewer deciding the next step. Inspect task/handovers/results and
  compare prompt variants without editing JSON or enabling live trading.

## Current position

- The 2026-09-06 repository review at `460f60b` found 22 sections: 17 done,
  2 planned, 1 blocked and 2 cancelled. `boundary-schema` and `outcome-record`
  completed cycles 001–005 and are merged. `plan-inbox` and `ticket-exhaust`
  have zero cycles and completed dependencies. `real-install` accepted T1–T4;
  cycle 005 blocked T5 on access to the real golden-grid target.
- Seven selected regression suites passed on 2026-09-06, including the main
  integration suite, 241 engine assertions, schema, bindings, outcome records,
  packaging and real-install fixtures. Fixtures do not settle real-target
  migration or live GitHub acceptance.
- Before dispatching current consumer sections, settle shared-file ownership:
  both need `pm_flow.sh`, and plan-inbox also needs `driver.zsh`; their declared
  owned paths omit these integrations. Serialize shared-file changes. The inbox
  brief names nonexistent `tests/run.zsh`; the engine runner is
  `template/.agentic/pm_flow/tests/run.zsh`. Ticket-exhaust needs stable accepted
  cycle records, which the delivered JSON export does not yet expose.
- Acceptance export has a concrete false positive: real-install A2 and A4 are
  marked met from mentions in state prose despite missing real-target evidence.
  Explicit accepted evidence must replace mention-based completion before a
  tracker or the new knowledge store consumes it as truth.
- Recorded spend is $488.9174, incomplete: all 56 recorded Codex attempts have
  NULL dollar costs. There are 132 historical runs still marked running with no
  end time; recent runs now close correctly. Do not invent missing costs or end
  times. Named-topology model lists also need Astra/Fable 5.1 support before
  explicitly overriding those models in comparison arms.
- A fresh operator read can list `/Users/salah/code/personal/golden-grid`;
  whether a newly scoped developer can perform the real-install work remains
  to be probed. The target migration must preserve its existing project data.
- Owner extension, 2026-09-06: `knowledge-handover` and `workflow-studio` were
  registered through `pm-flow init-section` with CUT decisions. There are now
  24 sections: 17 done, 4 planned, 1 blocked and 2 cancelled. These are
  required capabilities, replacing the earlier exclusions of SQLite state and
  a visual editor. Reuse the store, persona catalog, topology comparison and
  protocol adapters; do not create a parallel orchestrator.
- Integration ordering: knowledge-handover owns shared scheduler/CLI/export/
  telemetry files and supplies the inbox/tracker hooks. The dependency interface
  now places plan-inbox and ticket-exhaust after knowledge-handover, as well as
  their completed prerequisites; workflow-studio also depends on it. Their
  module/UI paths stay disjoint. CPO must verify the interface handovers. Existing file-based handoff and commit
  rules govern the current engine until the knowledge-store migration is proven;
  that section owns updating the affected runtime contracts and role guidance.
- Live OpenTelemetry probe: the knowledge-handover CPO proposal used Astra;
  its provider event and stored attempt 349 agree on input=222208, output=4792,
  cached-input=179328 and reasoning=331. Jaeger trace
  `cb1f68ead78ca1e4d931be4c330d1831` was fetched and inspected: correlated
  invoke_agent/chat spans carry the same input/output and parent cache/reasoning
  values. This proves that one live dispatch, not all required recovery paths
  or transports; Codex dollars remain unknown.
- Cut sections remain `a2a-binding` and `repo-hooks`; this extension does not
  restore them. The separately drafted hosted OS-Agents product is not this plan.

## Deliberately out of scope

- Any hosted service. Everything runs locally, against backends the user starts.
- Live trading, placing orders, and deploying a trading system. The research
  example evaluates ideas and produces evidence; it does not operate capital.
