# What the product still lacks

Everything in the objective sentence: no backend-readable trace (`otlp_endpoint` absent, no `pm-flow trace`), the driver still writes `runs/cost_ledger.tsv` on every dispatch, no `compare`, no persona measurement, no MCP or ACP surface. Since review 003, $21.07 bought `store-ledger` T2/T3 (readers and `pm-flow cost` on the store) and then a `BLOCKED_EXTERNAL` over an ownership gap; every one of the 7 dispatches went to `store-ledger` because the driver ranks by dependents before recency (`driver.zsh:2672`), so `trace-commands` and `otel-semconv` — must-haves waiting on nothing — are at zero cycles after four reviews. The blocker was real (four engine files no live section owns, whose ledger lines cannot survive A4) and only this role could close it, so I extended `store-ledger`'s boundary, reopened it, and committed the record.

# Completion criteria

- Finished run opens in Phoenix/Langfuse/Jaeger with every role, prompt, retry, stall, tokens, dollars — `git grep -inE 'otlp_endpoint|"trace"|compare|\bacp\b|\bmcp\b' -- src/pm_flow/cli.py` empty; `git ls-files src/pm_flow` = `__init__ cli paths` — **NOT MET**
- `cost_ledger.tsv` gone, host absorbs no per-dispatch writes — `git grep -n cost_ledger -- template` hits `driver.zsh:441-467,839`, `cost.py:185,192`, seven fixture lines, `README.md:168`; `ls runs/` shows `cost_ledger.tsv` rewritten 03:35 today beside `pm_flow.db` — **NOT MET**
- Sections run in isolated worktrees — `git worktree list` shows the `store-ledger` checkout under `../.pm-flow-worktrees/` — **MET**
- Persona installed from elsewhere, dropped on a seat, measured against the one it replaced — `git grep -inE 'compare|measure' -- template/pm_flow/catalog.py` empty — **NOT MET**
- Two topologies compared in one command — `git ls-files src/pm_flow` has no `compare.py`; `cli.py` grep above empty — **NOT MET**
- Drivable over MCP, binds any ACP agent — `git grep -inE 'otlp_endpoint|\bacp\b|\bmcp\b' -- '*config.json' '*agent_exec.sh' '*pm_flow.sh'` empty — **NOT MET**
- Test suite runs to completion — `zsh tests/pm_flow_test.sh` exit 0 (10 PASS); `zsh tests/prompt_quality_test.sh` exit 0 (57 prompts); `zsh tests/store_ledger_test.sh` exit 0; `zsh template/.agentic/pm_flow/tests/run.zsh` `all suites passed` (35/41/32/58/74) on `main` at `0665841` — **MET**

# Evidence I probed

- `git log --oneline -14` → `store-ledger` cycles 002/003 merged (`cb84e75`, `cae52de`); later `0665841 fix(driver): record a blocked section cleanly` landed from the owner mid-review.
- `git grep -n cost_ledger -- template` → 16 lines: driver functions, `cost.py` legacy import, `governance.zsh:198-199`, `on_demand.zsh:158,160,240`, `transitions.zsh:195,311`, `README.md:168`.
- `git grep -n -E 'record_dispatch_cost|spent_usd\(\)|dispatch_count\(\)' -- driver.zsh` → `:445` (called `:1036`), `:466`, `:837` — all still on the TSV.
- `grep -rH . sections --include=owned_paths.txt` → no live section names `template/.agentic/pm_flow/tests`; `tests/**` belonged to `green-suite` and `worktree-isolation`, both done. Blocker confirmed.
- `grep -rH . sections --include=last_dispatch.txt` → `trace-commands` never dispatched; `otel-semconv` unchanged at 2026-08-23T19:37Z.
- `cat sections/otel-semconv/.last_error.txt` → `claude failed with an unrecognised error; retrying once` then `role 'pm' did not produce a usable response for scope otel-semconv 001`; `cycles/` empty, no `quarantine.txt`. Review 003's open item settled: launcher failure.
- `Read runs/run-20260824T003057Z.log` → ticks 2-8 all `store-ledger`; tick 8 `BLOCKED_EXTERNAL`.
- `Read driver.zsh:2654-2673` → sort key `(priority, -dependents, last_dispatch, name)`; `:2164` blocked sections are skipped.
- `Read pm_flow.sh:1384-1445, 1800-1874` → overlap check ignores terminal sections; `section-handoff` accepts `active` from `blocked`.
- `git worktree list` → main at `6f469b9`, `store-ledger` checkout at `915911a`, clean (`git status --short` in it empty).
- `run.zsh` from the main tree before `0665841` was committed → exit 1 on one uncommitted assertion (`F2 the dash after the token`), the owner's own in-progress edit; re-run after the commit → all suites passed.
- `git status --short` at start → `driver.zsh` and `transitions.zsh` modified in the main tree by the owner, since committed; driver's cycle-004 record uncommitted, committed by me as `beac141`.
- `Read topology-compare/brief.md`, `persona-cards/brief.md` → A5 and A3 cover persona measurement in the compare report; no orphan bullet.
- `zsh portfolio/004/reopen.zsh` (`pm-flow section-handoff store-ledger active …`) → `status=active`, registry line regenerated.
- Refused: `pm-flow --help` (approval). Not probed: store token sums via `sqlite3` (refused in 003; nothing rests on it).

# Plan structure

- Unstarted dependency: CLEAR
- Unreachable section: FOUND `store-ledger` A4/A5 required editing `template/.agentic/pm_flow/tests/{transitions,on_demand,governance}.zsh` and `README.md`, owned by no live section; closed by adding them to its Owned paths (`brief.md` `## Boundary extended, authorized 2026-08-24`, `owned_paths.txt`, no overlap).
- Must-have inflation: CLEAR
- Linear-chain risk: FOUND depth two, but the head (`store-ledger`) blocked and both dependents — `topology-compare` and `agent-bindings`, the objective — stalled for a full review interval while the dependents-first sort starved the two independent trace sections; cured by the reopen, nothing structural changed.

# Verdicts

- agent-bindings: CONTINUE
- artifact-quality: CONTINUE
- otel-semconv: CONTINUE
- persona-cards: CONTINUE
- run-detach: CONTINUE
- store-ledger: RESCOPE acceptance unchanged; Owned paths now include `template/.agentic/pm_flow/tests/transitions.zsh`, `on_demand.zsh`, `governance.zsh` and `template/.agentic/pm_flow/README.md`, edits limited to what the ledger's removal forces, and the reviewer may not reject T4 for editing them within that limit; section reopened, next scope re-runs `cycles/004/scope_probe.zsh` and assigns T4
- topology-compare: CONTINUE
- trace-commands: CONTINUE

# Shortest path

`store-ledger` T4 (driver off the TSV, fixtures on the store) then T5 to done; `topology-compare` T1 next. `trace-commands` and `otel-semconv` get ticks only while `store-ledger` is not actionable; once it closes, the four must-haves interleave by least-recent dispatch. Nothing is in flight; the next tick is `store-ledger` cycle 005 scope, which is on the path. Committed as `beac141` (driver's blocked record) and `ec8e4dc chore(plan): portfolio review 004`, pushed to `origin/main`.

# Decision

OFF_TRACK — four reviews with the trace sections at zero cycles and the head of the chain blocked for the whole interval; the blocker is cleared as of this review, so the next interval is the test.
