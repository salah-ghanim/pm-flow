# What the product still lacks

Everything in the objective sentence. $107 and 28 cycles bought scaffolding — packaging, worktrees, installer, persona packs, Codex usage capture — and every criterion that makes pm-flow "the measurement layer" sits in a section with zero cycles: the store has not replaced the ledger, there is no `compare`, no `pm-flow trace`, no configured backend, no MCP or ACP surface. A persona can be installed and swapped but not measured against what it replaced, because nothing measures. The driver also does not order dispatch by priority, so nice-to-haves cost must-haves their ticks.

# Completion criteria

- Finished run opens in Phoenix/Langfuse/Jaeger with every role, prompt, retry, stall, tokens, dollars — **NOT MET**: `git grep otlp_endpoint` on both `config.json` printed nothing; `trace_export.py` is reached only from `driver.zsh:736` autoexport; `src/pm_flow/cli.py` has no `trace`.
- `cost_ledger.tsv` gone, host absorbs no per-dispatch writes — **NOT MET**: `driver.zsh:441-471` still writes/reads `runs/cost_ledger.tsv`; `ls` shows it on disk beside `pm_flow.db` (both gitignored, so no *tracked* writes).
- Sections run in isolated worktrees — **MET**: `git worktree list` shows `codex-usage` and `persona-packs` checkouts under `../.pm-flow-worktrees/`, outside the repo; `driver.zsh:2268-2270` issues `worktree add`.
- Persona installed from elsewhere, dropped on a seat, measured against the one it replaced — **NOT MET**: `catalog.py:1665-1681` registers `persona add|list|swap`; no compare/measure exists anywhere in `src/` or `template/`.
- Two topologies compared in one command — **NOT MET**: `git grep -i compare src/pm_flow/cli.py` printed nothing; `src/pm_flow/compare.py` is not tracked.
- Drivable over MCP, binds any ACP agent — **NOT MET**: `git grep -iE 'acp|mcp'` on `agent_exec.sh`, `pm_flow.sh`, `config.json`, `cli.py` printed nothing.
- Test suite runs to completion — **NOT MET by probe**: `tests/pm_flow_test.sh`, `zsh -f tests/pm_flow_test.sh` and `zsh -f tests/prompt_quality_test.sh` were each refused under approval in this tier; last suite commit `988781c` (today); green-suite/packaging handoffs claim exit 0 and remain claims.

# Evidence I probed

- `ls` repo root → `AGENTS.md CLAUDE.md docs install.sh pyproject.toml README.md src template tests VERSION`.
- `git grep cost_ledger -- driver.zsh pm_flow.sh` → nothing (wrong path); `-- template` → `driver.zsh:441,442,451,467,471,839`, `watch.py:50`, three test files.
- `git ls-files` for `trace_export.py cost.py acp* mcp* compare* topologies/*` → only `template/.agentic/pm_flow/cost.py`, `trace_export.py`.
- `git grep 'git worktree add' driver.zsh` → comment at 1847; `-E 'worktree (add|remove|prune)'` → 2266, 2268, 2270, 2420, 2422, 2432.
- `git grep -iE 'trace|compare|persona' pm_flow.sh` → persona composition only; no trace or compare command.
- `git grep -iE 'acp|mcp' agent_exec.sh pm_flow.sh config.json` → nothing.
- `git grep persona catalog.py` → `persona add` 1503, `list` 1550, `swap` 1586; parser 1665-1681.
- `git grep -E 'trace_export|compare'` driver/src → `driver.zsh:736` only.
- `ls tests src src/pm_flow` → `cli.py paths.py`; four `*_test.sh` plus fixtures.
- `git grep -c 'gen_ai\.' telemetry.py trace_export.py` → `telemetry.py:14`.
- `git worktree list` → main at `3ba4ea7`; two linked checkouts under `/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/`.
- `git grep -iE 'trace|compare|acp|mcp' src/pm_flow/cli.py` → nothing.
- `git ls-files runs/cost_ledger.tsv runs/pm_flow.db` → nothing tracked; `git check-ignore -v` → both ignored by `.gitignore:24`.
- `git grep -E 'usd|gen_ai\.usage|stall|retry' telemetry.py` → `gen_ai.usage.input_tokens/output_tokens/cost` at 257-260, `pm_flow.cost_usd` 279; no stall/retry attribute.
- `git grep otlp_endpoint` both `config.json` → nothing.
- `git log -1 -- tests/pm_flow_test.sh` → `988781c 2026-08-23`.
- `git grep -A2 '^telemetry_store_file()'` → `runs/pm_flow.db`; `ls -la` → `cost_ledger.tsv` 15067 B, `pm_flow.db` 319488 B.
- `sqlite3 … attempts` and `python3 -c sqlite3 …` → refused; attempt count and Codex token sums unprobed.
- `git grep -E '^- A[0-9]+:'` store-ledger/topology-compare/agent-bindings/trace-commands/otel-semconv briefs → every acceptance names a path in that section's `owned_paths.txt`.
- `git grep pm_flow.sh src/pm_flow/cli.py` → line 26 forwards to `pm_flow.sh`; no subcommand table.
- `git grep -E 'must-have|nice-to-have' driver.zsh` → 2994 (review token), 3429 (validation) only; no dispatch ordering.
- `cat priority.txt` ×4 → two lines, `must-have` + loss sentence.
- `git ls-files tests/fixtures` → `codex_events_real.jsonl` present.

# Plan structure

- Unstarted dependency: FOUND `topology-compare` → `store-ledger` (0 cycles); `a2a-binding` → `agent-bindings` (0 cycles); both upstreams wait on nothing.
- Unreachable section: CLEAR
- Must-have inflation: CLEAR
- Linear-chain risk: CLEAR

# Verdicts

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

# Shortest path

`store-ledger` T1 now (it heads the chain to `compare`, the objective itself), with `trace-commands` T1 and `otel-semconv` T1 in parallel on disjoint paths; `topology-compare` the moment `store-ledger` lands; `agent-bindings` after. Nothing in flight is on that path: the two active sections (`codex-usage` T3, `persona-packs` COMPLETE) are closing scaffolding.

# Decision

OFF_TRACK — one of seven criteria met after $107; every criterion in the objective sentence is in a section with zero cycles.

Log and plan committed as `chore(plan): portfolio review 001 cuts a2a-binding and repo-hooks` and pushed to `main`; the driver's untracked `portfolio/001/facts.md` was left for it to commit.
