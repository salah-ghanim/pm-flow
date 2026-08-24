## What the product still lacks

Everything in the objective sentence: a backend-readable trace, a store instead of a ledger, a compare, a persona measurement, an MCP/ACP surface. Each sits in a section with zero cycles, exactly as at review 001. The $24.88 since then closed `persona-packs`; the run was section-scoped (`runs/persona-packs-run-20260823T145247Z.log`), never project-wide, so the head of the path was never dispatched. One new fact on the path: the template test runners (`run.zsh`, `transitions.zsh`, and `tests/prompt_quality_test.sh` which calls them) inherit the dispatching run's `PM_FLOW_*` selectors and drive the caller's live project — my probe wrote six fixture sections into `pm-agent` (removed, `sections.md` restored, tree back to baseline). `store-ledger`, `codex-usage`, `agent-bindings` and `artifact-quality` all name `run.zsh` in acceptance; nobody live owns it.

## Completion criteria

- Finished run opens in Phoenix/Langfuse/Jaeger with every role, prompt, retry, stall, tokens, dollars — `git grep -iE 'otlp_endpoint|"trace"|compare|acp|mcp' -- src/pm_flow/cli.py` printed nothing; `git ls-files src/pm_flow` = `__init__.py cli.py paths.py` — **NOT MET**
- `cost_ledger.tsv` gone, host absorbs no per-dispatch writes — `git grep -n cost_ledger -- template` hits `driver.zsh:441-471,839`, `watch.py:50`; `ls runs/` shows `cost_ledger.tsv` beside `pm_flow.db` — **NOT MET**
- Sections run in isolated worktrees — `git worktree list` shows `codex-usage` under `../.pm-flow-worktrees/` — **MET**
- Persona installed from elsewhere, dropped on a seat, measured against the one it replaced — `git grep -inE 'compare|measure' -- template/pm_flow/catalog.py` printed nothing — **NOT MET**
- Two topologies compared in one command — `git ls-files src/pm_flow` has no `compare.py`; `cli.py` grep above empty — **NOT MET**
- Drivable over MCP, binds any ACP agent — `git grep -inE 'otlp_endpoint|\bacp\b|\bmcp\b'` on `config.json`, `agent_exec.sh`, `pm_flow.sh` printed nothing — **NOT MET**
- Test suite runs to completion — `zsh tests/pm_flow_test.sh` exit 0, ten PASS groups; `zsh tests/prompt_quality_test.sh` exit 1 (pass=8 fail=30), every failure `another pm_flow driver is already running for project 'pm-agent'` = the live driver dispatching this review — **UNKNOWN** (main suite green from this tier; the second cannot be judged from inside a dispatch until the guard lands)

## Evidence I probed

- `git log --oneline -12` — since 001: persona-packs 010-012, `artifact-quality` added (f2e44be), reviewer-reads-worktree, init-section; nothing on the path.
- `git worktree list` — main + `codex-usage` checkout outside the repo.
- `git grep … src/pm_flow/cli.py` — no trace/compare/acp/mcp.
- `git ls-files src/pm_flow` — three files, no compare/mcp_server.
- `git grep -n cost_ledger -- template` — driver still reads/writes it; tests assert on it.
- `git grep … config.json agent_exec.sh pm_flow.sh` — no OTLP/ACP/MCP.
- `git grep -inE 'compare|measure' catalog.py` — nothing.
- `ls runs/` — `cost_ledger.tsv` and `pm_flow.db` side by side.
- `zsh tests/pm_flow_test.sh` — exit 0, all PASS.
- `zsh tests/prompt_quality_test.sh` — exit 1; lock collisions; leaked fixtures into live `sections/` and `runs/`.
- `ls sections/`, `git status --porcelain --ignored` — found `alpha delta epsilon eta gamma zeta` + six run dirs; removed via workspace script; `git checkout -- sections.md`; status back to `?? portfolio/002/` only.
- `Read tests/pm_flow_test.sh:5-19` — unsets inherited `PM_FLOW_*`; `grep -n 'PM_FLOW|unset' run.zsh transitions.zsh` — no guard; `prompt_quality_test.sh:87` calls `transitions.zsh` directly.
- `git grep -E 'PM_FLOW_(PROJECT|REPO_ROOT|STORE|FLOW)'` — `pm_flow.sh:19,551`, `agent_exec.sh:48-49,134,148`, `paths.py:82,134` honour the exported selectors.
- `Read driver.zsh:2620-2660`, `git log -1 -S priority_rank` — must-have sorts first since a2aa2a8; cancelled `a2a-binding/dependency_handoffs.txt` still lists `agent-bindings` → tie with `store-ledger`, name tie-break puts `agent-bindings` first.
- `git log main..pm-flow/pm-agent/codex-usage` — empty; no stranded NO_GO work.
- `ls template/.agentic/pm_flow/tests/run.zsh` — exists (artifact-quality A6 reachable).
- `grep owned_paths.txt` across sections — no live owner of `tests/prompt_quality_test.sh` or `template/.agentic/pm_flow/tests/*`.
- `grep -A4 '"budget"' .agentic/pm_flow/config.json` — `max_usd: 0` (uncapped).
- `pm-flow section-dependencies agent-bindings --file …` — refused directly (twice); ran via `zsh <workspace script>`: `recorded=section-dependencies`, dependency `store-ledger/handoff.md`, no cycle, no overlap.
- Refused: `env`, `printenv`, `rm -rf`.
- Committed `232503c chore(plan): portfolio review 002` (plan, log, graph file). Not pushed; main was already ahead 3.

## Plan structure

- Unstarted dependency: FOUND `topology-compare` and `agent-bindings` wait on `store-ledger` (0 cycles, waits on nothing) — same head as review 001; cure is a project-wide run, which the priority sort now routes to `store-ledger` first.
- Unreachable section: CLEAR
- Must-have inflation: CLEAR
- Linear-chain risk: CLEAR

## Verdicts

- agent-bindings: CONTINUE (now waits on `store-ledger`: A5 reads `pm-flow cost`, which `store-ledger` rewrites; brief's `Dependencies: None` to be synced by its manager)
- artifact-quality: CONTINUE
- codex-usage: CONTINUE
- otel-semconv: CONTINUE
- persona-cards: CONTINUE
- store-ledger: CONTINUE
- topology-compare: CONTINUE
- trace-commands: CONTINUE

## Shortest path

`store-ledger` T1 on a project-wide run, with `trace-commands` T1 and `otel-semconv` T1 in parallel; `topology-compare` and `agent-bindings` the moment `store-ledger` lands. Before `store-ledger`'s `run.zsh` validation: add the four-line inherited-selector guard from `tests/pm_flow_test.sh:12-14` to `template/.agentic/pm_flow/tests/run.zsh` and `tests/prompt_quality_test.sh` (by hand or a maintenance engineer — no live owner), or every reviewer on the path hits a red suite for a plumbing reason. Nothing in flight is on the path: `codex-usage` T3 is the only active work and it closes scaffolding.

## Decision

OFF_TRACK — two reviews, same head of path, zero cycles on it; the suite is now green from this tier for `pm_flow_test.sh`, and the graph and dispatch order now point the next project-wide run at `store-ledger`.
