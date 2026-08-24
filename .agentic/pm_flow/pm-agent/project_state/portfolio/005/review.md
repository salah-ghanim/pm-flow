Review 005 committed as `c7561fc` and pushed to `origin/main`.

# What the product still lacks

The objective sentence is still unbought: no trace a backend can open, no compare, no persona measurement, no MCP/ACP surface. But the foundation under all four moved this window — the driver and every fixture came off `cost_ledger.tsv` (`store-ledger` T4, `1c5a301`), and the two trace sections took their first cycles after four reviews of starvation. One new lack appeared: the product is a measurement layer whose own dogfood recorded a $0.00 developer dispatch — the cost reader broke between 02:17Z and 06:08Z today, the store carries known-low rows for that window, and the driver's interval spend figure ($2.3986) is a third of what the TSV recorded for the same window ($8.74). Budget governance under-counts until `store-ledger` A1 parity settles the correction; the TSV must not be deleted before that parity check runs against it.

# Completion criteria

- Finished run opens in Phoenix/Langfuse/Jaeger with every role, prompt, retry, stall, tokens, dollars — `git grep -inE 'otlp_endpoint|"trace"|compare|\bacp\b|\bmcp\b' -- src/pm_flow/cli.py` empty — NOT MET
- `cost_ledger.tsv` gone, host absorbs no per-dispatch writes — `git grep -n cost_ledger -- template` hits only `cost.py:184,191` (import reader); TSV still on disk, last written 07:17Z (the merge minute), while `pm_flow.db` advanced at 07:38Z — NOT MET (write stopped; file not gone)
- Sections run in isolated worktrees — `git worktree list`: `store-ledger` checkout under `../.pm-flow-worktrees/` — MET
- Persona installed from elsewhere, dropped on a seat, measured — `git grep -inE 'compare|measure' -- template/pm_flow/catalog.py` empty — NOT MET
- Two topologies compared in one command — `git ls-files src/pm_flow` = `__init__ cli paths`, no `compare.py` — NOT MET
- Drivable over MCP, binds any ACP agent — `git grep -inE 'otlp_endpoint|\bacp\b|\bmcp\b' -- '*config.json' '*agent_exec.sh' '*pm_flow.sh'` empty — NOT MET
- Test suite runs to completion — all four suites exit 0 from this tier (10 PASS; 57 prompts; store ledger passed; `all suites passed` 35/41/32/58/74); `git status --short` unchanged after — MET

# Evidence I probed

- `git grep -inE 'otlp_endpoint|"trace"|compare|\bacp\b|\bmcp\b' -- src/pm_flow/cli.py` — empty; no trace/compare/acp/mcp surface.
- `git grep -n cost_ledger -- template` — only `cost.py:184,191`; `driver.zsh`, the three engine fixtures and the README are clean for the first time.
- `git worktree list` — `store-ledger` checkout at `1c5a301` under `../.pm-flow-worktrees/`.
- `git grep -inE 'compare|measure' -- template/pm_flow/catalog.py` — empty.
- `git ls-files src/pm_flow` — `__init__.py cli.py paths.py`; no compare module.
- `git grep -inE 'otlp_endpoint|\bacp\b|\bmcp\b' -- '*config.json' '*agent_exec.sh' '*pm_flow.sh'` — empty.
- `ls -la .agentic/pm_flow/pm-agent/runs` — `cost_ledger.tsv` mtime 07:17Z (merge minute); `pm_flow.db` and run logs 07:38Z from a post-merge dispatch: the write stopped, the file remains.
- `git show --no-patch 1c5a301` / `--stat 7ef20bc` — cycle 005 accepted 07:17Z; the "state and handoff" commit carries no `handoff.md`.
- `git log --oneline -3 -- sections/store-ledger/handoff.md` — last change `ec8e4dc` (the reopen); the handoff is stale after acceptance, same manager miss as review 003.
- `tail -12 runs/cost_ledger.tsv` — develop 005 blank cost, review 005 first run 0.000000, five scopes ~$0.0022 against a $2.7–4.8 historical price, 07:17Z review normal ($3.87); the incident window and the under-count.
- Four suites run, all exit 0; `git status --short` identical to baseline after (settles `store-ledger` A5 by my own probe: fixtures seed and read the store).
- Refused: `sqlite3` on `runs/pm_flow.db` (approval), as in 001/003 — store rows probed via the TSV tail instead.

# Plan structure

- Unstarted dependency: CLEAR — `topology-compare` and `agent-bindings` wait on `store-ledger` (5 cycles, active, one task from done); `persona-cards` waits on `persona-packs` (done).
- Unreachable section: CLEAR — review 004's ownership gap was closed by the boundary extension and T4 landed inside it.
- Must-have inflation: CLEAR — the five live must-haves map to the trace, ledger, compare and MCP/ACP bullets one-to-one.
- Linear-chain risk: CLEAR — depth two, and the starvation broke: both trace sections took their first scope cycles this window.

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

`store-ledger` T5 — A1 parity on the live project (which also settles the cost-incident correction), A4 `max_usd` refusal from the store, then delete the TSV — closes the section; `topology-compare` T1 immediately after, with `trace-commands` and `otel-semconv` assignments interleaving. The next tick is `store-ledger` cycle 006 scope, which is on the path.

# Decision

ON_TRACK — first time in five reviews: the path head moved decisively (T4 on `main`), the starved trace sections have cycles, all suites are green, and the one open risk (cost-row integrity) has a named probe on the very next task.
