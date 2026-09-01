Review 008 complete, committed as `2d2432e`. Plan and log updated.

# What the product still lacks

Motion, not design. Every previously live section closed and the suite regression cured itself into green — but the three criteria the owner added (JSON export, tracker view, queued plan requests) plus outcome records and the real install are all owned by sections at zero cycles, and nothing has dispatched since 2026-08-25 except today's ticket-exhaust registration. The product also still lacks explicit plan bullets for `outcome-record` and `real-install` — added this review, so the plan now states twelve criteria and the sections trace one-to-one.

# Completion criteria

- Backend render, hours later — `docker ps`: `pm-flow-jaeger` up 7 days; the semconv suite's own `curl :16686/api/traces?service=pm-flow` re-served `invoke_agent -> chat` from the live backend — **MET**
- `cost_ledger.tsv` gone, no per-dispatch host writes — `ls runs/`: only `cost_ledger.tsv.imported-20260824` beside `pm_flow.db` — **MET**
- Sections in isolated worktrees — `pm_flow_test.sh` worktree group PASS; `git worktree list` = main only, nothing in flight — **MET**
- Persona installed, dropped on a seat, measured — `persona_cards_test.sh` exit 0 — **MET**
- Two topologies compared in one command — `topology_compare_test.sh` exit 0 — **MET**
- MCP drivable, binds any ACP agent — `agent_bindings_test.sh` exit 0 — **MET**
- Section state exportable as validated JSON — `ls template/.agentic/pm_flow/schemas` exit 1; no export verb in `pm_flow.sh` — **NOT MET**
- Section visible in a ticket tracker — `git grep -in ticket_sync -- template src tests` exit 1 — **NOT MET**
- Plan-level request queued under a held lock — `git grep -in inbox -- template src` exit 1 — **NOT MET**
- Outcomes and end times in store and trace (bullet added this review) — `git grep -n gen_ai.evaluation -- template src` exit 1 — **NOT MET**
- Real install migrated and driven (bullet added this review) — `ls tests/real_install_test.sh` exit 1 — **NOT MET**
- Test suite runs to completion — all thirteen suites exit 0 from this tier, including both 007 reds — **MET**

# Evidence I probed

- `pgrep -lf driver.zsh` — exit 1, no driver running.
- `docker ps` — `pm-flow-jaeger` all-in-one, up 7 days, ports 4318/16686.
- `curl :16686/api/services` — refused (approval); settled instead by the semconv suite's internal Jaeger query, which printed the re-served trace.
- `git worktree list` — main at `085c82a` only.
- `ls .agentic/pm_flow/pm-agent/runs` — archived TSV, `pm_flow.db`, run logs; no live ledger.
- `zsh tests/packaged_layout_test.sh` — exit 0, 13 PASS (red at 007); "a copied-engine repository migrates losslessly" confirms run-detach's registry entries landed.
- `zsh tests/otel_semconv_test.sh` — exit 0 (red at 007); secondary resolves its own sed-pinned `semconv.py` under the test temp dir.
- `zsh tests/pm_flow_test.sh`, `prompt_quality_test.sh` (57 prompts), `store_ledger_test.sh`, `template/.../tests/run.zsh` (35/41/32/59/74, `all suites passed`), `topology_compare_test.sh`, `agent_bindings_test.sh`, `trace_commands_test.sh` (first try, no flake), `run_detach_test.sh`, `persona_cards_test.sh`, `artifact_quality_test.sh`, `codex_usage_test.sh` — all exit 0.
- `git status --short` after all suites — unchanged: only this dispatch's portfolio workspace and the operator's three untracked root files; no leakage.
- `ls template/.agentic/pm_flow/schemas` exit 1; `git grep` for `ticket_sync`, `inbox`, `gen_ai.evaluation` each exit 1; `ls tests/real_install_test.sh` exit 1 — the five unmet criteria have no code on `main`.
- `git grep "extra.dir" -- driver.zsh pm_flow.sh` — `DISPATCH_EXTRA_DIRS`/`--extra-dir` at `driver.zsh:1059,2534-2561`: real-install's off-repo evidence mechanism exists.
- `gh auth status` — refused (approval); ticket-exhaust's live-GitHub half is UNKNOWN from this tier. `ls` of golden-grid — refused (session directory allowlist).
- `git log --oneline -25` — run-detach closed at cycle 006, otel-semconv at 008; owner added the three criteria in `01ea0da`; ticket-exhaust's first proposal died on a usage limit (`6d1b3e8`).

# Plan structure

- Unstarted dependency: FOUND — plan-inbox waits on boundary-schema and outcome-record (both 0 cycles); ticket-exhaust waits on boundary-schema (0 cycles); both upstreams wait on nothing and are dispatchable, so one run cures it.
- Unreachable section: CLEAR
- Must-have inflation: CLEAR
- Linear-chain risk: CLEAR

# Verdicts

- boundary-schema: CONTINUE
- outcome-record: CONTINUE
- plan-inbox: CONTINUE
- real-install: CONTINUE
- ticket-exhaust: CONTINUE — and its brief's open question is decided: stays must-have, the owner's tracker criterion stands.

# Shortest path

Start a run. The next unmet criterion is the JSON export: boundary-schema T1 (schemas, checker, export verb), which alone also unblocks ticket-exhaust and half of plan-inbox's dependencies; outcome-record and real-install interleave in parallel, waiting on nothing. Nothing is in flight — all five sections are at zero cycles and no driver is running — so no work is on the path until a run starts.

# Decision

ON_TRACK — the suite criterion re-probed MET, both 007 reopens closed as prescribed, and every unmet criterion has exactly one dispatchable owner; the only thing between here and motion is starting the run.
