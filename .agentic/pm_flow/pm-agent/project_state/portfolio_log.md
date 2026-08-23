# Portfolio review log

Newest first. Read this before anything else: one review cannot see a
section that has been nearly done for four of them, or a shortest path that
has not moved in three. Older entries are compacted to their summary line.

## Review 001 - 2026-08-23T13:50:52Z - $112.3201 spent

- Summary: 1 of 7 criteria met; verdicts CONTINUE 8, CUT 2; shortest path: `store-ledger` T1 now (it heads the chain to `compare`, the objective itself), with `trace-commands` T1 and `otel-semconv` T1 in parallel on disjoint paths; ...

### Completion criteria

- Finished run opens in Phoenix/Langfuse/Jaeger with every role, prompt, retry, stall, tokens, dollars — **NOT MET**: `git grep otlp_endpoint` on both `config.json` printed nothing; `trace_export.py` is reached only from `driver.zsh:736` autoexport; `src/pm_flow/cli.py` has no `trace`.
- `cost_ledger.tsv` gone, host absorbs no per-dispatch writes — **NOT MET**: `driver.zsh:441-471` still writes/reads `runs/cost_ledger.tsv`; `ls` shows it on disk beside `pm_flow.db` (both gitignored, so no *tracked* writes).
- Sections run in isolated worktrees — **MET**: `git worktree list` shows `codex-usage` and `persona-packs` checkouts under `../.pm-flow-worktrees/`, outside the repo; `driver.zsh:2268-2270` issues `worktree add`.
- Persona installed from elsewhere, dropped on a seat, measured against the one it replaced — **NOT MET**: `catalog.py:1665-1681` registers `persona add|list|swap`; no compare/measure exists anywhere in `src/` or `template/`.
- Two topologies compared in one command — **NOT MET**: `git grep -i compare src/pm_flow/cli.py` printed nothing; `src/pm_flow/compare.py` is not tracked.
- Drivable over MCP, binds any ACP agent — **NOT MET**: `git grep -iE 'acp|mcp'` on `agent_exec.sh`, `pm_flow.sh`, `config.json`, `cli.py` printed nothing.
- Test suite runs to completion — **NOT MET by probe**: `tests/pm_flow_test.sh`, `zsh -f tests/pm_flow_test.sh` and `zsh -f tests/prompt_quality_test.sh` were each refused under approval in this tier; last suite commit `988781c` (today); green-suite/packaging handoffs claim exit 0 and remain claims.

### Verdicts

- a2a-binding: CUT no plan bullet names A2A (the binding criterion is ACP); waits on an unstarted section; its own stated risk is an unauthenticated endpoint that spends budget. Product no longer guarantees an A2A-bound seat.
- agent-bindings: CONTINUE
- codex-usage: CONTINUE
- otel-semconv: CONTINUE
- persona-cards: CONTINUE
- persona-packs: CONTINUE
- repo-hooks: CUT advances no plan bullet; the driver already writes Conventional Commits; its failure mode (hook refusing the driver's subject) stops the flow. Product no longer guarantees a commit-message hook or an install registry. Reopen with a planned handoff once the must-haves close.
- store-ledger: CONTINUE
- topology-compare: CONTINUE
- trace-commands: CONTINUE

### Shortest path

`store-ledger` T1 now (it heads the chain to `compare`, the objective itself), with `trace-commands` T1 and `otel-semconv` T1 in parallel on disjoint paths; `topology-compare` the moment `store-ledger` lands; `agent-bindings` after. Nothing in flight is on that path: the two active sections (`codex-usage` T3, `persona-packs` COMPLETE) are closing scaffolding.
