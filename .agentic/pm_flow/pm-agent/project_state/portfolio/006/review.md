# What the product still lacks

One thing on the critical line: **no trace backend has ever displayed a run.** Export, semconv spans, and the OTLP round trip are all proven against a schema-validated loopback receiver, but Phoenix/Langfuse/Jaeger have never been contacted and Docker is absent on this host — an operator dependency, not a section. Beyond that, only documented limits: no shipped ACP agent or stock MCP SDK client has connected (suites used protocol-equivalent clients), compare arms have only run on stub projects, the store under-counts the 02:17–06:08Z broken-reader window (unrepairable — both sinks recorded the same low rows), and budget-capped arms drop out of `wall_clock_s`. Two gaps found this review were cured in it: the accepted `agent-bindings` work (including `mcp_server.py`) had never been merged to `main` — merged by path from `9a683f4` as `9dfed03` after the full suite set passed — and the TSV's parity gate had no owner, so I ran it and retired the file.

# Completion criteria

- Backend render (Phoenix/Langfuse/Jaeger) — everything local passes (`trace_commands_test.sh` exit 0, exact span ids re-fetched; `otlp_endpoint` at `config.json:61`), but no backend has displayed a run and `docker ps` exits 1 (no daemon) — **UNKNOWN**, probe `docker run -d -p 4318:4318 -p 16686:16686 jaegertracing/all-in-one` + `curl :16686/api/traces?service=pm-flow`
- `cost_ledger.tsv` gone, no per-dispatch host writes — `git grep cost_ledger -- template` hits only `cost.py:184,191` (import reader); TSV mtime froze at 07:17Z while `pm_flow.db` advanced to 19:10Z; parity gate ran (`imported=0` twice, idempotent), file archived to gitignored `runs/cost_ledger.tsv.imported-20260824` — **MET**
- Sections run in isolated worktrees — `pm_flow_test.sh` "per-section git worktrees, merge-back, and cleanup" PASS; `git worktree list` = main only, nothing in flight — **MET**
- Persona installed elsewhere, dropped on a seat, measured — `catalog.py:1508-1642` `persona add/update/list/swap`; `topology_compare_test.sh` PASS asserts `--persona lean:pm=cpo` in `attempts.persona_stack` and the report — **MET**
- Two topologies compared in one command — `pm_flow.sh:1943 cmd_compare`, usage lines 43-44; suite PASS on `main` — **MET**
- Drivable over MCP, binds any ACP agent — after `9dfed03`: `agent_bindings_test.sh` exit 0 incl. "MCP lists exactly five tools and drives a section to done" and "ACP developer completes a public driver cycle to GO" — **MET**
- Test suite runs to completion — all four plan suites exit 0 from this tier (10 PASS; 57 prompts; store ledger passed; 35/41/32/58/74), run twice: before and after the merge — **MET**

# Evidence I probed

- `git grep otlp_endpoint -- template src` → `config.json:61`, `driver.zsh:771`, `trace_export.py` — endpoint wiring exists
- `git grep cost_ledger -- template` → only `cost.py:184,191` (legit import reader); no driver/fixture hit
- `ls`/`ls -l` on `runs/` → TSV present at start, mtime 07:17Z vs `pm_flow.db` 19:10Z (writes stopped); absent after the archive
- `git ls-files src/pm_flow` → `acp.py`, `semconv.py` present, **no `mcp_server.py`** — the merge gap
- `git diff --stat main pm-flow/pm-agent/agent-bindings` → branch stale on other sections' paths (would delete `compare.py`, `topology.py`); scoped to its four `owned_paths.txt` entries: `+841/-43` only
- `git grep` on `pm_flow.sh` → `compare` and `trace` arms at :1943/:1947; `catalog.py` persona commands at :1508-1642
- Suites, all exit 0: `pm_flow_test.sh`, `prompt_quality_test.sh`, `store_ledger_test.sh`, `tests/run.zsh` (35/41/32/58/74), `topology_compare_test.sh`, `trace_commands_test.sh`, `agent_bindings_test.sh` (main version pre-merge, cycle-006 version post-merge with 5 MCP PASSes)
- `portfolio/006/parity_probe.zsh` → store total 321.1864; `cost.py import` on `pm-agent` → `imported=0`; rerun → `imported=0`; total unchanged
- `docker ps` → exit 1, no daemon — the one probe that could not run
- Note: `git grep -E '\bacp\b'` matches nothing on this host even where `acp` exists — reviews 003-005's MCP/ACP probes used `\b` and were unreliable; I re-probed without it
- Looked for and did not find: `mcp_server.py` history on `main` (`git log -- src/pm_flow/mcp_server.py` empty pre-merge); any live owner for `pm_flow.sh`; a repricing path for the incident-window rows

# Plan structure

- Unstarted dependency: CLEAR — no live section waits on anything unstarted; `persona-cards`' dependency `persona-packs` is done.
- Unreachable section: FOUND — the MCP criterion sat in a done section's unmerged branch and the TSV gate had no owner (both cured by officer action this review); the backend-render observation still has no owner and needs Docker, an operator dependency.
- Must-have inflation: CLEAR — every must-have is done; the three live sections are nice-to-have.
- Linear-chain risk: CLEAR — three independent live sections, no chain.

# Verdicts

- artifact-quality: CONTINUE
- persona-cards: CONTINUE
- run-detach: CONTINUE

# Shortest path

The one open criterion needs the host, not a section: start Docker, run the Jaeger all-in-one, `pm-flow trace export --otlp http://localhost:4318/v1/traces`, read the trace back at `:16686`. The three nice-to-haves in flight are not on it and cannot be. The objective sentence — two designs run, compared, a persona swapped and measured — is demonstrable on `main` today, on stub projects; the next product-level increment beyond the render is running `compare` on a real multi-section project.

# Decision

ON_TRACK — since review 005: five must-haves closed, 2→6 criteria met by my own probes, the remainder behind an operator dependency; the accepted-but-unmerged MCP surface and the TSV gate were closed inside this review.
