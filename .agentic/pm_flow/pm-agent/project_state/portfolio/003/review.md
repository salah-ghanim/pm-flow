# What the product still lacks

The objective sentence, whole. Nothing can be compared, traced from a command, measured against a replaced persona, or driven over MCP/ACP. The ledger is half-moved: the importer and its test are on `main` (`558837f`), but `pm-flow cost`, `watch.py` and the driver still read and write `runs/cost_ledger.tsv`. The two parallel arms the plan has assumed since review 001 — `trace-commands` and `otel-semconv` — are must-have, wait on nothing, and have zero cycles after three reviews. The run is serial and interrupted, not parallel. Spend since 002 ($32.04, 15 dispatches) closed `codex-usage` and bought `store-ledger` its first accepted cycle; that is the first money on the path in three reviews.

# Completion criteria

- Finished run opens in Phoenix/Langfuse/Jaeger with every role, prompt, retry, stall, tokens, dollars — `git grep -inE 'otlp_endpoint|"trace"|compare|\bacp\b|\bmcp\b' -- src/pm_flow/cli.py` empty; `otlp_endpoint` absent from `config.json`; `trace_export.py` reached only from `driver.zsh:736` — **NOT MET**
- `cost_ledger.tsv` gone, host absorbs no per-dispatch writes — `git grep -n cost_ledger -- template` hits `driver.zsh:441-471`, `cost.py:186,193,221`, `watch.py:50`; `find` shows `runs/cost_ledger.tsv` beside `pm_flow.db` — **NOT MET**
- Sections run in isolated worktrees — `git worktree list` shows `store-ledger` under `../.pm-flow-worktrees/` — **MET**
- Persona installed from elsewhere, dropped on a seat, measured against the one it replaced — `git grep -inE 'compare|measure' -- template/pm_flow/catalog.py` empty — **NOT MET**
- Two topologies compared in one command — `git ls-files src/pm_flow` = `__init__.py cli.py paths.py`; `cli.py` grep above empty — **NOT MET**
- Drivable over MCP, binds any ACP agent — `git grep -inE 'otlp_endpoint|\bacp\b|\bmcp\b'` on `config.json`, `agent_exec.sh`, `pm_flow.sh` empty — **NOT MET**
- Test suite runs to completion — `zsh tests/pm_flow_test.sh` exit 0 (10 PASS); `zsh tests/prompt_quality_test.sh` exit 0; `zsh template/.agentic/pm_flow/tests/run.zsh` exit 0 (`all suites passed`); `zsh tests/store_ledger_test.sh` exit 0; `git status --short` unchanged after all four — **MET**

# Evidence I probed

- `git worktree list` → `main` at `c1f3363`, `store-ledger` checkout at `558837f` under `../.pm-flow-worktrees/`.
- `git ls-files src/pm_flow` → `__init__.py cli.py paths.py`; no `compare.py`, no `trace`.
- `git grep -inE 'otlp_endpoint|"trace"|compare|\bacp\b|\bmcp\b' -- src/pm_flow/cli.py` → nothing.
- `git grep -inE 'otlp_endpoint|\bacp\b|\bmcp\b' -- template/.agentic/pm_flow/{config.json,agent_exec.sh,pm_flow.sh}` → nothing.
- `git grep -inE 'compare|measure' -- template/pm_flow/catalog.py` → nothing.
- `git grep -n cost_ledger -- template` → `driver.zsh:441-471,839`, `cost.py:186,193`, `watch.py:50`, README, three test suites.
- `git grep -n ledger -- template/.agentic/pm_flow/cost.py` → `totals(project_dir, ledger_path)` at 213-221 still reads the TSV; `import` at 107-193 reads the store (`SELECT response_path FROM attempts` at 181).
- `git grep -n 'record_dispatch_cost|trace_export' -- driver.zsh pm_flow.sh` → `driver.zsh:445` defines, `:1036` calls; `trace_export` only at `driver.zsh:736`; nothing in `pm_flow.sh`.
- `find .agentic -maxdepth 4 -name cost_ledger.tsv -o -name pm_flow.db` → both under `.agentic/pm_flow/pm-agent/runs/`.
- `git log --oneline main..pm-flow/pm-agent/store-ledger` and `git diff --stat main...pm-flow/pm-agent/store-ledger` → both empty: the branch is merged.
- `git show --stat 558837f` → `cost.py +117`, `tests/store_ledger_test.sh +104`; `git show --stat 1dee8a2` → state, workplan, status, summary (no `handoff.md` content change: handoff still says "Nothing delivered yet").
- `grep -n 'A[0-9]|twice|second' tests/store_ledger_test.sh` → asserts `imported=0` and equal row count on the second import (A3); no A1/A2/A4 assertion.
- `git log --oneline -4 -- tests/prompt_quality_test.sh template/.agentic/pm_flow/tests/run.zsh` → `ec8130f fix(tests): stop the stub suites writing into the caller's live project`; both files now unset `PM_FLOW_*` at lines 15-17 / 19-21.
- `zsh tests/pm_flow_test.sh` → exit 0, 10 PASS. `zsh tests/prompt_quality_test.sh` → exit 0, `every composed shipped prompt (56) is clean`. `zsh template/.agentic/pm_flow/tests/run.zsh` → exit 0, `all suites passed`, 0 FAIL. `zsh tests/store_ledger_test.sh` → exit 0.
- `git status --short` after the suites → only `portfolio/003/`, `resume_claude.*` and my `plan.md` edit; no fixture leak.
- `git grep -n '' -- sections/*/dependency_handoffs.txt sections/*/priority.txt sections/*/last_dispatch.txt` → edges: `agent-bindings`→`store-ledger`, `topology-compare`→`store-ledger`, `persona-cards`→`persona-packs`; `run-detach`, `otel-semconv`, `trace-commands`, `artifact-quality`, `store-ledger` have none; `otel-semconv` last dispatch `1787513835` (2026-08-23T19:37:15Z), `trace-commands` never.
- `ls -la runs/20260822T222645Z-otel-semconv-ccea9f8c` → `meta.json`, empty `pending/`, `task_brief.md`, `transcript.md`, all dated section creation; facts say cycles 0, spend $0.00 despite the 19:37Z dispatch.
- `grep -n 'max_usd|parallel|portfolio_review|concurren|otlp' .agentic/pm_flow/config.json` → `max_usd: 0`, `max_usd_per_section: 0`, review triggers 12 dispatches / $20 / 8 idle cycles; no concurrency key, no `otlp`.
- `git grep -n 'nice-to-have' -- driver.zsh` → `:2603-2662` orders must-have first, then least-recent dispatch, then key.
- `git ls-files tests docs` → `docs/prompt-qa.md` only; `tests/store_ledger_test.sh`, `tests/codex_usage_test.sh` tracked; no `run_detach*` yet.
- `sqlite3 runs/pm_flow.db "select count(*), sum(cost_usd), sum(input_tokens>0) from attempts"` → **refused (approval)**; attempt count and Codex tokens unprobed.
- `git status -sb` → `main...origin/main` in sync before my commit.

# Plan structure

- Unstarted dependency: CLEAR — `topology-compare` and `agent-bindings` wait on `store-ledger`, now at 2 cycles; `persona-cards` waits on `persona-packs`, done.
- Unreachable section: CLEAR — `run-detach` owns the four paths it writes; its `pm_flow.sh` arm (A7) is gated on a release this officer makes after `trace-commands` is done.
- Must-have inflation: CLEAR — the five live must-haves map one-to-one to the trace, ledger, compare and MCP/ACP bullets.
- Linear-chain risk: CLEAR — longest chain is two deep.

# Verdicts

- agent-bindings: CONTINUE
- artifact-quality: CONTINUE
- otel-semconv: CONTINUE
- persona-cards: CONTINUE
- run-detach: CONTINUE
- store-ledger: CONTINUE
- topology-compare: CONTINUE
- trace-commands: CONTINUE

# Shortest path

`store-ledger` A1/A2/A4 — `cost.py totals` from `attempts`, the five driver functions off the TSV — then `topology-compare` T1. `trace-commands` T1 and `otel-semconv` T1 in parallel now; neither has a reason left to wait, and the driver's least-recent-dispatch order puts both ahead of `store-ledger` at the next tick. Work in flight (`store-ledger` cycle 002, scope done) is on the path. The `store-ledger` handoff still says "Nothing delivered yet" despite `558837f` on `main`; its next scope call must sync it.

Changes made: `plan.md` current position rewritten (harness-hazard paragraph removed as fixed by `ec8130f`, `codex-usage` dropped from the order, `run-detach` added with its gate); review 003 appended to `portfolio_log.md`; committed as `8e42ca2 chore(plan): portfolio review 003` and pushed to `origin/main`. No scope reduced, no graph edge or `priority.txt` changed.

# Decision

OFF_TRACK — one of six product criteria met plus the suite; the path head moved for the first time (`store-ledger` cycle 001), but $176 in, the two unblocked parallel arms have never been dispatched and no criterion in the objective sentence is closer than one section's first accepted cycle.
