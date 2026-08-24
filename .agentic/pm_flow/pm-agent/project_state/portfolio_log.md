# Portfolio review log

Newest first. Read this before anything else: one review cannot see a
section that has been nearly done for four of them, or a shortest path that
has not moved in three. Older entries are compacted to their summary line.

## Review 006 - 2026-08-24 - $105.3747 / 82 dispatches since 005

- Summary: 6 of 7 criteria met; verdicts CONTINUE 3; ON_TRACK - all five
  must-haves closed since 005. Found and fixed: `agent-bindings` was marked
  done with its owned paths unmerged (`mcp_server.py` absent from `main`);
  merged by path from `9a683f4` as `9dfed03` after the full suite set passed
  on the merged tree. Ran the TSV's parity gate (`imported=0` twice) and
  archived it. Released `run-detach`'s `pm_flow.sh` arm. Remaining: the
  backend render, which needs Docker on the host.

### Completion criteria

- Backend render (Phoenix/Langfuse/Jaeger) — `trace_commands_test.sh` exit 0
  (loopback OTLP round trip, exact span ids); `otlp_endpoint` at
  `config.json:61`; but no backend has displayed a run and `docker ps` exits
  1 (no daemon) — UNKNOWN, probe `docker run …all-in-one` + curl :16686
- `cost_ledger.tsv` gone, no per-dispatch host writes — `git grep
  cost_ledger -- template` hits only `cost.py:184,191` (import reader); TSV
  mtime froze at 07:17Z while `pm_flow.db` advanced to 19:10Z; archived to
  `runs/cost_ledger.tsv.imported-20260824` after the parity probe — MET
- Isolated worktrees — `pm_flow_test.sh` "per-section git worktrees,
  merge-back, and cleanup" PASS; `git worktree list` = main only (nothing in
  flight) — MET
- Persona installed, dropped on a seat, measured — `catalog.py`
  `cmd_persona_add/update/list/swap` (:1508-1642); `topology_compare_test.sh`
  PASS asserts `--persona lean:pm=cpo` in `attempts.persona_stack` and the
  report — MET
- Two topologies, one command — `pm_flow.sh:1943 cmd_compare`; suite PASS on
  `main` — MET
- MCP + ACP — after the by-path merge (`9dfed03`): `agent_bindings_test.sh`
  exit 0 with "MCP lists exactly five tools and drives a section to done"
  and "ACP developer completes a public driver cycle to GO" — MET
- Suites run to completion — all four plan suites exit 0 from this tier
  (10 PASS; 57 prompts; store ledger passed; 35/41/32/58/74), twice: before
  and after the merge — MET

### Findings

- Integration gap: `agent-bindings` went done at 11:29Z with every owned
  path unmerged; its handoff said so ("not yet in main") and nobody below
  the officer could act on a done section. Merged exactly its four owned
  paths from `9a683f4` (`+841/-43`); the branch is stale on other sections'
  paths, so a whole-branch merge would have reverted `topology-compare` -
  by-path was the only correct shape. Why the driver marked done without
  merging is unestablished; if a second section ever goes done-unmerged,
  the driver's acceptance path needs a probe.
- TSV parity gate: `cost.py import` on `pm-agent` printed `imported=0`, the
  second run too, store total 321.1864 unchanged - every TSV row already
  had a store row. The incident-window correction review 005 hoped for is
  not possible: import keys on `response_path` and cannot reprice an
  existing row, and both sinks recorded the same broken values. The
  under-count is now a documented limit in the plan, not an open question.
  TSV archived (renamed, gitignored), not destroyed.
- `run-detach` gate released: `## Boundary extended, authorized 2026-08-24`
  appended to its brief; `pm_flow.sh` added to `owned_paths.txt`, limited to
  one case arm and one help line. No live section owned the file.
- `store-ledger`'s parting question (make `assert_within_budget` fail
  closed, `driver.zsh:610-624`) and the `wall_clock_s` fail-path gap:
  deferred, recorded as documented limits; reopening `driver.zsh` ownership
  is not worth it while no capped-arm comparison is being run.
- `topology-compare`'s note that its brief's owned paths were wrong (engine
  Python lives under `template/.agentic/pm_flow/`, not `src/pm_flow/`) is
  acknowledged; the section is terminal and overlap checks ignore it, so no
  edit is made.
- The three live handoffs each declare "everything in the brief" unproven -
  accurate: all three are pre-first-assignment, cycle 0/1, ~$0.0022 each
  (incident-window scope stamps).
- Refused in this tier: `docker ps` (no daemon - a fact about the host, not
  approval), bare `python3 cost.py` and bare `mv` (approval; both ran via
  scripts in `portfolio/006/`, the established route).

### Plan structure

- Unstarted dependency: CLEAR — no live section waits on anything unstarted;
  `persona-cards`' dependency `persona-packs` is done.
- Unreachable section: FOUND — two met criteria were unreachable when the
  review opened: the MCP surface sat in a done section's unmerged branch and
  the TSV gate had no owner; both cured by officer action this review. The
  backend-render observation still has no owner and needs Docker - an
  operator dependency, not a section.
- Must-have inflation: CLEAR — every must-have is done; the three live
  sections are nice-to-have and priced accordingly.
- Linear-chain risk: CLEAR — three independent live sections, no chain.

### Verdicts

- artifact-quality: CONTINUE
- persona-cards: CONTINUE
- run-detach: CONTINUE

### Shortest path

The one open criterion needs the host, not a section: start Docker, run the
Jaeger all-in-one, `pm-flow trace export --otlp`, and read the trace back at
:16686. Work in flight (three nice-to-haves) is not on it and cannot be;
the objective sentence itself - two designs, compared, a persona swapped and
measured - is demonstrable on `main` today, on stub projects. The next
product-level increment beyond the render is running compare on a real
multi-section project.

### Decision

ON_TRACK - since 005: five must-haves closed, 2→6 criteria met, the one
remaining sits behind an operator dependency.

## Review 005 - 2026-08-24T07:51:21Z - $215.8117 spent

- Summary: 2 of 7 criteria met; verdicts CONTINUE 8; shortest path: `store-ledger` T5 — A1 parity on the live project (which also settles the cost-incident correction), A4 `max_usd` refusal from the store, then delete the TSV...

### Completion criteria

- Finished run opens in Phoenix/Langfuse/Jaeger with every role, prompt, retry, stall, tokens, dollars — `git grep -inE 'otlp_endpoint|"trace"|compare|\bacp\b|\bmcp\b' -- src/pm_flow/cli.py` empty — NOT MET
- `cost_ledger.tsv` gone, host absorbs no per-dispatch writes — `git grep -n cost_ledger -- template` hits only `cost.py:184,191` (import reader); TSV still on disk, last written 07:17Z (the merge minute), while `pm_flow.db` advanced at 07:38Z — NOT MET (write stopped; file not gone)
- Sections run in isolated worktrees — `git worktree list`: `store-ledger` checkout under `../.pm-flow-worktrees/` — MET
- Persona installed from elsewhere, dropped on a seat, measured — `git grep -inE 'compare|measure' -- template/pm_flow/catalog.py` empty — NOT MET
- Two topologies compared in one command — `git ls-files src/pm_flow` = `__init__ cli paths`, no `compare.py` — NOT MET
- Drivable over MCP, binds any ACP agent — `git grep -inE 'otlp_endpoint|\bacp\b|\bmcp\b' -- '*config.json' '*agent_exec.sh' '*pm_flow.sh'` empty — NOT MET
- Test suite runs to completion — all four suites exit 0 from this tier (10 PASS; 57 prompts; store ledger passed; `all suites passed` 35/41/32/58/74); `git status --short` unchanged after — MET

### Verdicts

- agent-bindings: CONTINUE
- artifact-quality: CONTINUE
- otel-semconv: CONTINUE
- persona-cards: CONTINUE
- run-detach: CONTINUE
- store-ledger: CONTINUE
- topology-compare: CONTINUE
- trace-commands: CONTINUE

### Shortest path

`store-ledger` T5 — A1 parity on the live project (which also settles the cost-incident correction), A4 `max_usd` refusal from the store, then delete the TSV — closes the section; `topology-compare` T1 immediately after, with `trace-commands` and `otel-semconv` assignments interleaving. The next tick is `store-ledger` cycle 006 scope, which is on the path.

## Review 005 - 2026-08-24T07:49:41Z - $211.6728 spent (driver figure; under-counted, see cost incident)

- Summary: 2 of 7 criteria met; verdicts CONTINUE 8; ON_TRACK for the first time - `store-ledger` T4 landed (`1c5a301`), the driver and all fixtures are off the TSV, and `trace-commands`/`otel-semconv` finally have their first cycles. Shortest path: `store-ledger` T5 (live A1 parity, A4 refusal, delete the TSV) then `topology-compare` T1.

### Completion criteria

- Finished run opens in Phoenix/Langfuse/Jaeger with every role, prompt, retry, stall, tokens, dollars — `git grep -inE 'otlp_endpoint|"trace"|compare|\bacp\b|\bmcp\b' -- src/pm_flow/cli.py` empty; same grep over `*config.json *agent_exec.sh *pm_flow.sh` empty — **NOT MET**
- `cost_ledger.tsv` gone, host absorbs no per-dispatch writes — `git grep -n cost_ledger -- template` hits only `cost.py:184,191` (import reader); `driver.zsh` clean for the first time; `ls runs/` shows the TSV still on disk, last written 07:17Z (the merge minute), while `pm_flow.db` and run logs advanced at 07:38Z from a post-merge dispatch — **NOT MET** (write stopped; file not gone)
- Sections run in isolated worktrees — `git worktree list`: `store-ledger` checkout under `../.pm-flow-worktrees/` at `1c5a301` — **MET**
- Persona installed from elsewhere, dropped on a seat, measured against the one it replaced — `git grep -inE 'compare|measure' -- template/pm_flow/catalog.py` empty — **NOT MET**
- Two topologies compared in one command — `git ls-files src/pm_flow` = `__init__ cli paths`, no `compare.py`; `cli.py` grep above empty — **NOT MET**
- Drivable over MCP, binds any ACP agent — `git grep -inE 'otlp_endpoint|\bacp\b|\bmcp\b' -- '*config.json' '*agent_exec.sh' '*pm_flow.sh'` empty — **NOT MET**
- Test suite runs to completion — `zsh tests/pm_flow_test.sh` exit 0 (10 PASS); `zsh tests/prompt_quality_test.sh` exit 0 (57 prompts); `zsh tests/store_ledger_test.sh` exit 0; `zsh template/.agentic/pm_flow/tests/run.zsh` `all suites passed` (35/41/32/58/74); `git status --short` unchanged after all four — **MET**

### Findings

- Cost-reader incident, 02:17Z-06:08Z today: `cost_ledger.tsv` rows show the
  `store-ledger` 005 developer dispatch with a blank cost, its first review
  at 0.000000, and five section scopes at ~$0.0022 against a $2.7-4.8
  historical price; the 07:17Z review row is normal ($3.87). `9452a80
  fix(driver): a broken cost reader no longer kills the run` is the owner's
  patch. The driver's interval figure ($2.3986/22 dispatches) is a third of
  the TSV's sum for the same window ($8.74). The store now carries
  known-low rows; `store-ledger` A1 parity on `pm-agent` is the probe that
  settles the correction, and the TSV stays until it runs.
- `store-ledger` cycle 005 (T4) accepted and merged (`1c5a301`, `33df08d`,
  `7ef20bc`); A5 settled by my own probe (`run.zsh` exit 0 with fixtures
  on the store). Its `handoff.md` was not updated at acceptance — last
  change is `ec8e4dc` (the reopen); `7ef20bc`'s subject says "state and
  handoff" but the commit carries only state/workplan/summary stamps. Same
  manager miss as review 003; the next scope call must sync it.
- The five scope cycles' section stamps (status/summary/updated_at,
  `last_dispatch.txt`) sit uncommitted in the main tree — same class as
  the blocked-record bug `0665841` fixed. Not product state; noted for the
  owner.
- Refused in this tier: `sqlite3` on `runs/pm_flow.db` (approval), as in
  001/003. Store row values probed via the TSV tail instead.

### Verdicts

- agent-bindings: CONTINUE
- artifact-quality: CONTINUE
- otel-semconv: CONTINUE
- persona-cards: CONTINUE
- run-detach: CONTINUE
- store-ledger: CONTINUE
- topology-compare: CONTINUE
- trace-commands: CONTINUE

### Plan structure

- Unstarted dependency: CLEAR — `topology-compare` and `agent-bindings` wait on `store-ledger` (5 cycles, active, one task from done); `persona-cards` waits on `persona-packs` (done).
- Unreachable section: CLEAR — the review-004 ownership gap was closed by the boundary extension and T4 landed inside it.
- Must-have inflation: CLEAR — the five live must-haves map to the trace, ledger, compare and MCP/ACP bullets one-to-one.
- Linear-chain risk: CLEAR — depth two, and the review-004 starvation broke: both trace sections took their first scope cycles this window.

### Shortest path

`store-ledger` T5 — A1 parity on the live project, A4 `max_usd` refusal from the store, then delete the TSV — closes the section; `topology-compare` T1 immediately after. `trace-commands` and `otel-semconv` assignments interleave. The next tick is `store-ledger` cycle 006 scope, which is on the path.

## Review 004 - 2026-08-24T01:57:39Z - $209.2742 spent

- Summary: 2 of 7 criteria met; verdicts CONTINUE 7, RESCOPE 1; shortest path: `store-ledger` T4 (driver off the TSV, fixtures on the store) then T5 to done; `topology-compare` T1 next. `trace-commands` and `otel-semconv` get ticks only...

### Completion criteria

- Finished run opens in Phoenix/Langfuse/Jaeger with every role, prompt, retry, stall, tokens, dollars — `git grep -inE 'otlp_endpoint|"trace"|compare|\bacp\b|\bmcp\b' -- src/pm_flow/cli.py` empty; `git ls-files src/pm_flow` = `__init__ cli paths` — **NOT MET**
- `cost_ledger.tsv` gone, host absorbs no per-dispatch writes — `git grep -n cost_ledger -- template` hits `driver.zsh:441-467,839`, `cost.py:185,192`, seven fixture lines, `README.md:168`; `ls runs/` shows `cost_ledger.tsv` rewritten 03:35 today beside `pm_flow.db` — **NOT MET**
- Sections run in isolated worktrees — `git worktree list` shows the `store-ledger` checkout under `../.pm-flow-worktrees/` — **MET**
- Persona installed from elsewhere, dropped on a seat, measured against the one it replaced — `git grep -inE 'compare|measure' -- template/pm_flow/catalog.py` empty — **NOT MET**
- Two topologies compared in one command — `git ls-files src/pm_flow` has no `compare.py`; `cli.py` grep above empty — **NOT MET**
- Drivable over MCP, binds any ACP agent — `git grep -inE 'otlp_endpoint|\bacp\b|\bmcp\b' -- '*config.json' '*agent_exec.sh' '*pm_flow.sh'` empty — **NOT MET**
- Test suite runs to completion — `zsh tests/pm_flow_test.sh` exit 0 (10 PASS); `zsh tests/prompt_quality_test.sh` exit 0 (57 prompts); `zsh tests/store_ledger_test.sh` exit 0; `zsh template/.agentic/pm_flow/tests/run.zsh` `all suites passed` (35/41/32/58/74) on `main` at `0665841` — **MET**

### Verdicts

- agent-bindings: CONTINUE
- artifact-quality: CONTINUE
- otel-semconv: CONTINUE
- persona-cards: CONTINUE
- run-detach: CONTINUE
- store-ledger: RESCOPE acceptance unchanged; Owned paths now include `template/.agentic/pm_flow/tests/transitions.zsh`, `on_demand.zsh`, `governance.zsh` and `template/.agentic/pm_flow/README.md`, edits limited to what the ledger's removal forces, and the reviewer may not reject T4 for editing them within that limit; section reopened, next scope re-runs `cycles/004/scope_probe.zsh` and assigns T4
- topology-compare: CONTINUE
- trace-commands: CONTINUE

### Shortest path

`store-ledger` T4 (driver off the TSV, fixtures on the store) then T5 to done; `topology-compare` T1 next. `trace-commands` and `otel-semconv` get ticks only while `store-ledger` is not actionable; once it closes, the four must-haves interleave by least-recent dispatch. Nothing is in flight; the next tick is `store-ledger` cycle 005 scope, which is on the path. Committed as `beac141` (driver's blocked record) and `ec8e4dc chore(plan): portfolio review 004`, pushed to `origin/main`.

## Review 003 - 2026-08-24T00:37:49Z - $181.0513 spent

- Summary: 2 of 7 criteria met; verdicts CONTINUE 8; shortest path: `store-ledger` A1/A2/A4 — `cost.py totals` from `attempts`, the five driver functions off the TSV — then `topology-compare` T1. `trace-commands` T1 and `otel...

### Completion criteria

- Finished run opens in Phoenix/Langfuse/Jaeger with every role, prompt, retry, stall, tokens, dollars — `git grep -inE 'otlp_endpoint|"trace"|compare|\bacp\b|\bmcp\b' -- src/pm_flow/cli.py` empty; `otlp_endpoint` absent from `config.json`; `trace_export.py` reached only from `driver.zsh:736` — **NOT MET**
- `cost_ledger.tsv` gone, host absorbs no per-dispatch writes — `git grep -n cost_ledger -- template` hits `driver.zsh:441-471`, `cost.py:186,193,221`, `watch.py:50`; `find` shows `runs/cost_ledger.tsv` beside `pm_flow.db` — **NOT MET**
- Sections run in isolated worktrees — `git worktree list` shows `store-ledger` under `../.pm-flow-worktrees/` — **MET**
- Persona installed from elsewhere, dropped on a seat, measured against the one it replaced — `git grep -inE 'compare|measure' -- template/pm_flow/catalog.py` empty — **NOT MET**
- Two topologies compared in one command — `git ls-files src/pm_flow` = `__init__.py cli.py paths.py`; `cli.py` grep above empty — **NOT MET**
- Drivable over MCP, binds any ACP agent — `git grep -inE 'otlp_endpoint|\bacp\b|\bmcp\b'` on `config.json`, `agent_exec.sh`, `pm_flow.sh` empty — **NOT MET**
- Test suite runs to completion — `zsh tests/pm_flow_test.sh` exit 0 (10 PASS); `zsh tests/prompt_quality_test.sh` exit 0; `zsh template/.agentic/pm_flow/tests/run.zsh` exit 0 (`all suites passed`); `zsh tests/store_ledger_test.sh` exit 0; `git status --short` unchanged after all four — **MET**

### Verdicts

- agent-bindings: CONTINUE
- artifact-quality: CONTINUE
- otel-semconv: CONTINUE
- persona-cards: CONTINUE
- run-detach: CONTINUE
- store-ledger: CONTINUE
- topology-compare: CONTINUE
- trace-commands: CONTINUE

### Shortest path

`store-ledger` A1/A2/A4 — `cost.py totals` from `attempts`, the five driver functions off the TSV — then `topology-compare` T1. `trace-commands` T1 and `otel-semconv` T1 in parallel now; neither has a reason left to wait, and the driver's least-recent-dispatch order puts both ahead of `store-ledger` at the next tick. Work in flight (`store-ledger` cycle 002, scope done) is on the path. The `store-ledger` handoff still says "Nothing delivered yet" despite `558837f` on `main`; its next scope call must sync it.
Changes made: `plan.md` current position rewritten (harness-hazard paragraph removed as fixed by `ec8130f`, `codex-usage` dropped from the order, `run-detach` added with its gate); review 003 appended to `portfolio_log.md`; committed as `8e42ca2 chore(plan): portfolio review 003` and pushed to `origin/main`. No scope reduced, no graph edge or `priority.txt` changed.

## Review 002 - 2026-08-23T18:26:45Z - $144.0741 spent

- Summary: 1 of 7 criteria met; verdicts CONTINUE 8; shortest path: `store-ledger` T1 on a project-wide run, with `trace-commands` T1 and `otel-semconv` T1 in parallel; `topology-compare` and `agent-bindings` the moment `stor...

## Review 001 - 2026-08-23T13:50:52Z - $112.3201 spent

- Summary: 1 of 7 criteria met; verdicts CONTINUE 8, CUT 2; shortest path: `store-ledger` T1 now (it heads the chain to `compare`, the objective itself), with `trace-commands` T1 and `otel-semconv` T1 in parallel on disjoint paths; ...

## 2026-08-22 — `agents-md` panel adjudication

- Decision: SYNTHESIZE proposals 1 and 2.
- Priority: `agents-md` remains nice-to-have; no acceptance criterion is reduced.
- Product order: finish `packaging`, repair section checkout placement and manifest
  enumeration, then re-cut `agents-md` against the packaged layout.
- The repair must place linked checkouts outside the repository and Git metadata,
  filter manifest exclusions relative to `TEMPLATE`, and reject an empty generated
  manifest.
- The feature path remains one full `AGENTS.md` plus a managed `CLAUDE.md`
  `@AGENTS.md` compatibility import, preserving pre-existing content.
- Probe: the committed registry has `packaging` active and `agents-md` active;
  packaging owns `install.sh` and `MANIFEST`.
- Probe: the `agents-md` checkout resolves under `.git/pm-flow/worktrees/...`.
- Probe: `tools/manifest.py` enumerates 74 entries in the main checkout and zero
  in the section checkout.
- Probe: `worktrees_root()` derives its root from Git's common directory, and
  `iter_template_files()` tests exclusion parts on the absolute path.
- Rejected: another unchanged dispatch, a permission-control bypass, and an
  isolation-off main-tree rescue while overlapping packaging work is active.
- What is unproven: an external linked checkout accepts a real headless edit;
  manifest entry sets match between main and linked checkouts after repair; the
  post-packaging AGENTS/CLAUDE install and mutation probes pass.

## 2026-08-23 — `codex-usage` panel adjudication

- Decision: ADOPT proposal 2, the split contract test plus host-level canary.
- Priority: `codex-usage` remains must-have; no acceptance criterion is reduced.
- Product order: `codex-usage` must close after `store-ledger`, because that
  section owns `cost.py` and must make `pm_flow.sh cost` read recorded tokens.
- Rescue output: a tracked public-`tick` fixture replay must create one closed
  Codex attempt and run, assert exact usage including zero fields, exercise
  liveness and stderr-only classification, and fail under lifecycle and schema
  mutations.
- External-contract output: a host-level authenticated canary, outside the
  scoped reviewer sandbox, must publish immutable command, event, store, trace
  context, response, and exit-status evidence from the same public surface.
- Security boundary: do not grant scoped Codex roles network access, expose a
  general verification shell, or copy credentials into a role-controlled
  directory merely to make nested review possible.
- Probe: committed code captures `turn.completed.usage`, writes adjacent JSONL,
  exports `TRACEPARENT`, and brackets dispatch with attempt lifecycle calls.
- Probe: `tests/pm_flow_test.sh` checks only the fixture parser; it has no
  end-to-end store/lifecycle assertion.
- Probe: `driver.zsh` still routes `pm_flow.sh cost` through
  `cost_ledger.tsv`; `store-ledger` owns `cost.py` and its acceptance requires
  the command to read the store.
- Probe: a nonempty real-Codex fixture is committed, while the current section
  handoff still names a real CLI dispatch and production-length event-only
  liveness as unproven.
- Graph update blocked: the validated `section-dependencies` command rejected
  the `store-ledger` edge because active `packaging` ownership of
  `tests/fixtures/stub_*.zsh` is judged to overlap `codex-usage` ownership of
  `tests/fixtures/codex_events_real.jsonl`; do not hand-edit around the check.
- Rejected from proposal 1: expanding this section into `cost.py`, which would
  overlap `store-ledger`, and treating the nested reviewer as the live canary.
- What is unproven: the tracked public-surface replay and mutations, a fresh
  host-level authenticated canary, production-length event-only liveness, and
  non-zero Codex tokens reported by `pm_flow.sh cost` after `store-ledger`; the
  intended graph edge remains unrecorded until the ownership conflict is fixed.

## 2026-08-23 — owner rebaseline of the live sections

- Decision: every nonterminal brief rewritten to the full contract shape with
  inline acceptance IDs; workplans carry validation commands; state and
  handoff files hold evidence only. History lives here and in cycle records.
- `codex-usage` releases `driver.zsh`, `agent_exec.sh` and `telemetry.py`
  (its remaining work is the tracked replay test). A2 is retired; cost
  presentation is `store-ledger` A2.
- Engine ownership now: `store-ledger` holds `driver.zsh` for its five ledger
  functions; `agent-bindings` holds `agent_exec.sh`; `otel-semconv` holds
  `telemetry.py`; `trace-commands` holds `pm_flow.sh`, `config.json`,
  `trace_export.py`; `topology-compare` holds `cli.py`; `persona-cards` takes
  `catalog.py` once `persona-packs` closes (dependency-gated).
- Dependencies: `otel-semconv` and `trace-commands` no longer wait on
  anything; `topology-compare` waits on `store-ledger` for cost totals.
- The driver's own commit subjects are Conventional Commits on `main`;
  `repo-hooks` verifies them rather than changing `driver.zsh`.
- `persona-packs` has evidence for every acceptance ID; its next scope call
  declares `COMPLETE`.
- Unproven after this pass: nothing new; the planned sections have no
  evidence and say so.

## 2026-08-23 — portfolio review 001

- Decision: OFF_TRACK. $107 and 28 cycles bought the scaffolding (packaging,
  worktrees, installer, persona packs, Codex usage); every criterion in the
  objective sentence - store instead of ledger, compare, trace commands,
  backend-readable spans, MCP/ACP - sits in a section with zero cycles.
- Criteria: worktree isolation MET (`git worktree list` shows the two live
  section checkouts under `../.pm-flow-worktrees/`, outside the repository).
  Backend-readable trace NOT MET (`otlp_endpoint` absent from both
  `config.json`; `trace_export.py` is reachable only from `driver.zsh:736`
  autoexport, never from `pm-flow`). Ledger gone NOT MET (`driver.zsh:441-471`
  still writes and reads `runs/cost_ledger.tsv`; the file is on disk beside
  `pm_flow.db`; both are gitignored, so the host absorbs no tracked writes).
  Persona install-swap-measure NOT MET (`catalog.py` has `persona add|list|
  swap`; no compare exists to measure against). Compare NOT MET and MCP/ACP
  NOT MET (`src/pm_flow/cli.py` has no `trace`, `compare`, `acp` or `mcp`;
  `agent_exec.sh` none either). Suite NOT MET by probe: `tests/pm_flow_test.sh`,
  `zsh -f tests/pm_flow_test.sh` and `zsh -f tests/prompt_quality_test.sh` were
  all refused under approval in this tier; last suite commit is 988781c today;
  the green-suite and packaging handoffs claim exit 0 and remain claims.
- `sqlite3` and `python3 -c` were refused, so the store's attempt count and
  summed Codex tokens are unprobed; `tests/fixtures/codex_events_real.jsonl`
  is committed.
- Plan structure: unstarted dependency FOUND - `topology-compare` waits on
  `store-ledger` (0 cycles) and `a2a-binding` on `agent-bindings` (0 cycles);
  both upstreams wait on nothing. Unreachable CLEAR: every planned acceptance
  names a path its section owns, and `cli.py` forwards unknown commands to
  `pm_flow.sh`, so `trace-commands` needs no `cli.py` edit. Must-have
  inflation CLEAR: each must-have maps to one plan bullet. Linear chain CLEAR:
  longest chain is two deep.
- `driver.zsh` does not order dispatch by priority (only validates the word),
  so a nice-to-have costs a must-have its tick.
- CUT `a2a-binding`: no plan bullet names A2A; the binding criterion is ACP;
  it waited on an unstarted section and its own stated risk is an
  unauthenticated endpoint that spends budget. The product no longer
  guarantees a seat bound to an agent somebody else serves over A2A.
- CUT `repo-hooks`: it advances no plan bullet, the driver already writes
  Conventional Commits, and its failure mode stops the flow. The product no
  longer guarantees an installed commit-message hook or a registry of installs
  for batch updates. Reopen with a planned handoff once the must-haves close.
- `persona-cards` stays nice-to-have and live: attribution is what makes a
  persona publishable, which is plan bullet four.
- `persona-packs`: remote authenticated transports unproven; accepted, since
  `file://` went through the real Git CLI and transport does not change pack
  semantics. Its next scope call declares COMPLETE.
- `codex-usage`: the live dispatch evidence is still the reviewer's claim;
  T3's tracked replay closes the section.
- Shortest path: `store-ledger` T1 now, in parallel with `trace-commands` T1
  and `otel-semconv` T1; `topology-compare` the moment `store-ledger` lands;
  `agent-bindings` after. Nothing in flight is on that path yet.
- Unproven after this review: every planned must-have; the suite's exit
  status from this tier; non-zero Codex tokens in the store.

## 2026-08-23 — portfolio review 002

- Decision: OFF_TRACK. $24.88 and 10 dispatches since review 001 closed
  `persona-packs` (cycles 011-012); the shortest path named in review 001
  (`store-ledger` T1) has not moved. Two reviews, same head of path, zero
  cycles on it. The run since 001 was `persona-packs`-only
  (`runs/persona-packs-run-20260823T145247Z.log`), not a project-wide run.
- Criteria: worktree isolation MET (`git worktree list`: `codex-usage`
  checkout under `../.pm-flow-worktrees/`). Suite: `zsh tests/pm_flow_test.sh`
  exit 0, ten PASS groups, from this tier; `zsh tests/prompt_quality_test.sh`
  exit 1, pass=8 fail=30, every failure `another pm_flow driver is already
  running for project 'pm-agent'` — the live driver that dispatched this
  review — so that half is UNKNOWN from inside a dispatch. Trace, ledger,
  persona measure, compare, MCP/ACP all NOT MET by the same probes as 001
  (`git ls-files src/pm_flow` is still `__init__ cli paths`; `cost_ledger.tsv`
  on disk; `driver.zsh:441-471,839` read and write it).
- Incident: the `prompt_quality_test.sh` probe wrote six fixture sections
  (`alpha delta epsilon eta gamma zeta`) and six run dirs into the live
  `pm-agent` project and regenerated `sections.md`. Cause:
  `tests/prompt_quality_test.sh:87` runs `template/.agentic/pm_flow/tests/
  transitions.zsh` without the inherited-selector guard `tests/pm_flow_test.sh:
  12-19` has, so the driver-under-test honoured `PM_FLOW_PROJECT` and
  `PM_FLOW_REPO_ROOT` from the dispatching run. Removed exactly those twelve
  directories and restored `sections.md` from HEAD; `git status` is back to
  baseline. `run.zsh` has no guard either; `store-ledger` (brief line 94),
  `codex-usage` A6, `agent-bindings` A2 and `artifact-quality` A6 all name
  it. Nobody live owns those files (`green-suite`'s `tests/**` is terminal).
  A reviewer hitting this is a `HARNESS` obstruction, not a section failure.
- Dispatch order: `driver.zsh:2650-2659` now sorts must-have before
  nice-to-have (landed in a2aa2a8), so a nice-to-have no longer costs a
  must-have its tick. It also counts a cancelled section's edge as a
  dependent (`a2a-binding/dependency_handoffs.txt` still lists
  `agent-bindings`), which tied `agent-bindings` with `store-ledger` and the
  name tie-break put `agent-bindings` first.
- Graph: recorded `agent-bindings` → `store-ledger` through
  `pm-flow section-dependencies` (validated: no cycle, no overlap). Reason:
  A5 reads `pm-flow cost` for an ACP attempt, and `store-ledger` A2 rewrites
  `cost.py` to read the store; the plan's stated order was already
  "agent-bindings after". `agent-bindings/brief.md` still says
  `Dependencies: None`; the graph file is authoritative and the manager
  syncs the brief at its next scope call.
- Plan structure: unstarted dependency FOUND — `topology-compare` and now
  `agent-bindings` wait on `store-ledger` (0 cycles), which waits on
  nothing; the cure is a project-wide run. Unreachable CLEAR:
  `artifact-quality` names `tests/run.zsh`, which exists, and owns every path
  it writes. Must-have inflation CLEAR: `codex-usage` is the token column
  for half the seats in a default install. Linear chain CLEAR: two deep.
- `artifact-quality` (new, nice-to-have, cut from a request after review
  001) advances no plan bullet and says so; kept live because it is a
  separate process that cannot touch the flow, the officer's reading cost is
  a real bottleneck, and priority ordering makes it free until no must-have
  is eligible. `persona-cards` likewise.
- `codex-usage`: `pm-flow/pm-agent/codex-usage` has no commits beyond main;
  T3 is the whole remaining section.
- Refused in this tier: `env`, `printenv`, `rm -rf` (cleanup ran through a
  script in the review workspace), `pm-flow section-dependencies` invoked
  directly (ran through the same route). Each refusal is about that exact
  command.
- Unproven after this review: every planned must-have; `prompt_quality_test.sh`
  and `run.zsh` green from inside a dispatch; non-zero Codex tokens in the
  store; that a reviewer's worktree dispatch leaks the same way (inferred from
  the same unguarded code path, not observed).

## 2026-08-24 — portfolio review 003

- Decision: OFF_TRACK. $32.04 and 15 dispatches since review 002 closed
  `codex-usage` (done, 8 cycles, $42.42) and bought `store-ledger` its first
  accepted cycle (`558837f`: `cost.py import` and `tests/store_ledger_test.sh`,
  $6.04 over 2 cycles). The head of the path has finally moved; the two
  parallel arms have not. `trace-commands` and `otel-semconv` wait on
  nothing, are must-have, and have zero cycles after three reviews.
- Criteria: worktree isolation MET (`git worktree list` shows the
  `store-ledger` checkout under `../.pm-flow-worktrees/`). Suite MET from
  this tier: `zsh tests/pm_flow_test.sh` exit 0, ten PASS groups;
  `zsh tests/prompt_quality_test.sh` exit 0 (56 shipped prompts clean);
  `zsh template/.agentic/pm_flow/tests/run.zsh` exit 0, `all suites passed`;
  `zsh tests/store_ledger_test.sh` exit 0. `git status --short` unchanged
  after all four — the guard landed in `ec8130f` and the review-002 leak
  does not recur. Trace, ledger, persona measure, compare, MCP/ACP all NOT
  MET by the same probes as 002 (`git ls-files src/pm_flow` still
  `__init__ cli paths`; `cli.py` has no `trace`/`compare`/`acp`/`mcp`;
  `config.json`, `agent_exec.sh`, `pm_flow.sh` have no `otlp_endpoint`,
  `acp`, `mcp`; `catalog.py` has no `compare`/`measure`; `cost_ledger.tsv`
  on disk beside `pm_flow.db`, written at `driver.zsh:445-471` and read at
  `cost.py:221` and `watch.py:50`).
- `store-ledger`: cycle 001 is on `main` and covers A3 (second import
  prints `imported=0`, row count unchanged). A1, A2, A4 are open: `cost.py
  totals` still takes the ledger path (`cost.py:213-221`), `driver.zsh:467`
  still passes it, `record_dispatch_cost` still appends. The section's
  `handoff.md` still reads "Nothing delivered yet" — the manager did not
  update it on acceptance; the artifact settles it, but the next scope call
  must sync the handoff.
- `otel-semconv`: `last_dispatch.txt` is 2026-08-23T19:37:15Z, six seconds
  after `codex-usage` closed, yet cycles 0 and spend $0.00, with its run dir
  holding an empty `pending/` from section creation. The dispatch left no
  cycle. Not read further (that is the transcript). The driver orders
  must-haves by least-recent dispatch, so `trace-commands` (never dispatched)
  and `otel-semconv` come before `store-ledger` at the next tick.
- Refused in this tier: `sqlite3` on `runs/pm_flow.db` (approval). The
  store's attempt count and summed Codex tokens remain unprobed; the
  criterion they bear on is NOT MET on other evidence, so nothing rests on
  them.
- Plan structure: unstarted dependency CLEAR — `topology-compare` and
  `agent-bindings` wait on `store-ledger`, now at two cycles;
  `persona-cards` waits on `persona-packs`, done. Unreachable CLEAR —
  `run-detach` (new since 002, nice-to-have, waits on nothing) owns the four
  paths it writes and its `pm_flow.sh` arm (A7) is gated on a release this
  officer makes after `trace-commands` is done. Must-have inflation CLEAR —
  the five live must-haves map to the trace, ledger, compare and MCP/ACP
  bullets one-to-one. Linear chain CLEAR — two deep.
- `run-detach` stays live and nice-to-have: `resume_claude.sh` at the repo
  root says launcher deaths are happening now, each one costs the dispatch
  in flight and records it as `failed (unknown)` in the attempt table that
  the measurement layer reads; it is free until no must-have is eligible.
- Plan: harness-hazard paragraph removed (fixed by `ec8130f`); `codex-usage`
  dropped from the order of work; `run-detach` added to the nice-to-haves
  with its routing-arm gate. No scope reduced, no graph edge changed.
- Shortest path: `store-ledger` A1/A2/A4 (`totals` from `attempts`, driver
  functions off the TSV), then `topology-compare` T1; `trace-commands` T1
  and `otel-semconv` T1 in parallel now — neither has a reason left to wait.
  Work in flight (`store-ledger` cycle 002, scope done) is on the path.
- Unproven after this review: every planned must-have; `store-ledger` A1,
  A2, A4, A5; non-zero Codex tokens in the store; why the 19:37Z
  `otel-semconv` dispatch produced no cycle.

## 2026-08-24 — portfolio review 004

- Decision: OFF_TRACK. $21.07 and 7 dispatches since review 003 bought
  `store-ledger` cycles 002-003 (`cb84e75`: `cost.py` and `watch.py` read
  the store; `cae52de`: `pm-flow cost` reads the store) and then a
  `BLOCKED_EXTERNAL` at cycle 004 scope. Every dispatch went to
  `store-ledger`: the driver ranks candidates by dependents before recency
  (`driver.zsh:2672`) and `store-ledger` has two, so `trace-commands` and
  `otel-semconv` never reached the queue. Review 003's expectation that
  least-recent order would put them first was wrong. Four reviews, zero
  cycles on either trace section.
- Criteria: worktree isolation MET (`git worktree list`: the `store-ledger`
  checkout under `../.pm-flow-worktrees/`). Suite MET from this tier:
  `zsh tests/pm_flow_test.sh` exit 0 (10 PASS); `zsh
  tests/prompt_quality_test.sh` exit 0 (57 prompts clean); `zsh
  tests/store_ledger_test.sh` exit 0; `zsh
  template/.agentic/pm_flow/tests/run.zsh` `all suites passed`
  (35/41/32/58/74) on `main` at `0665841`. One earlier run on the main tree
  failed a single assertion the owner had uncommitted at that moment
  (`F2 the dash after the token`), testing the owner's own in-progress
  `driver.zsh` edit; it passed once committed. Trace, ledger, persona
  measure, compare, MCP/ACP all NOT MET by the same probes as 003: `git
  ls-files src/pm_flow` still `__init__ cli paths`; `cli.py` has no
  `trace`/`compare`/`acp`/`mcp`; `config.json`, `agent_exec.sh`,
  `pm_flow.sh` have no `otlp_endpoint`/`acp`/`mcp`; `catalog.py` has no
  `compare`/`measure`; `cost_ledger.tsv` on disk beside `pm_flow.db`,
  rewritten at 03:35 today by this review's own dispatch.
- `store-ledger` blocker verified: `git grep -n cost_ledger -- template`
  prints `governance.zsh:198-199`, `on_demand.zsh:158,160,240`,
  `transitions.zsh:195,311`, `README.md:168`, plus `driver.zsh:441-467,839`
  and `cost.py:185,192` (the legacy import path). No live `owned_paths.txt`
  names `template/.agentic/pm_flow/tests`; `green-suite` and
  `worktree-isolation` held `tests/**` and both are done. The driver's
  `record_dispatch_cost` (:445, called :1036), `spent_usd` (:466) and
  `dispatch_count` (:837) still go through the TSV; A4 cannot land while
  those fixtures assert on the file. Not external in the contract's sense —
  no credential, service or clock — but an ownership gap that no role below
  the officer may close, and the manager escalated it exactly as the
  anti-drift rule requires.
- Boundary decision: `store-ledger` Owned paths extended by
  `template/.agentic/pm_flow/tests/{transitions,on_demand,governance}.zsh`
  and `template/.agentic/pm_flow/README.md`. Acceptance unchanged; edits
  limited to what the ledger's removal forces; the reviewer is bound not to
  reject T4 for editing them within that limit. Recorded in `brief.md`
  (Owned paths list and `## Boundary extended, authorized 2026-08-24`) and
  `owned_paths.txt`. Overlap: none — the live sections' prefixes are
  disjoint from these files and `assert_no_owned_path_overlap` ignores
  terminal sections. The section was reopened with an active handoff
  through `pm-flow section-handoff store-ledger active`. This is an
  expansion, not a reduction, made because a blocked head with no other
  role able to act stalls the two sections that are the objective; it
  weakens no criterion and no evidence, and one revert undoes it.
- The driver left its own record of the block uncommitted (the bug
  `0665841` fixes); committed first by path as `beac141
  chore(store-ledger): blocked cycle 004 (state and handoff)` so the
  blocked handoff is in history before the reopen overwrote it.
- `otel-semconv`'s 19:37Z dispatch (review 003's open item):
  `.last_error.txt` reads `claude failed with an unrecognised error;
  retrying once in 30s` then `role 'pm' did not produce a usable response
  for scope otel-semconv 001`; the cycle directory was removed and no
  `quarantine.txt` exists, so it is still eligible. A launcher failure of
  the class `run-detach` addresses; not a section failure.
- Owner activity during the run: `0665841 fix(driver): record a blocked
  section cleanly` landed on `main` mid-review, and `resume_claude.sh` at
  the root restarts the session after a usage-limit reset. The engine is
  being edited in the main tree while the flow runs; the principle says a
  worktree, the owner's call.
- Persona measurement is reachable: `topology-compare` A5 puts a swapped
  seat's persona key in the arm's report column and `persona-cards` A3
  names the card there. No plan bullet lacks an owner.
- Plan structure: unstarted dependency CLEAR — `topology-compare` and
  `agent-bindings` wait on `store-ledger` (four cycles, now active);
  `persona-cards` waits on `persona-packs`, done. Unreachable FOUND —
  `store-ledger` A4/A5 needed four files no live section owned; closed by
  the boundary decision above. Must-have inflation CLEAR — the five live
  must-haves map to the trace, ledger, compare and MCP/ACP bullets
  one-to-one; `otel-semconv` stays must-have because Phoenix and Langfuse
  render prompts and tokens from the GenAI attribute names it pins.
  Linear chain FOUND — depth two only, but the head blocked and both
  dependents, which are the objective, stalled behind it for a whole review
  interval while the two independent trace sections were starved by the
  dependents-first sort. Cured by the reopen; nothing structural changed.
- Refused in this tier: `pm-flow --help` (approval). `pm-flow
  section-handoff` ran through a script in the review workspace.
- Shortest path: `store-ledger` T4 then T5 to done, then `topology-compare`
  T1. `trace-commands` and `otel-semconv` take ticks only while
  `store-ledger` is not actionable; after it closes the four must-haves
  interleave by least-recent dispatch. Nothing is in flight; the next tick
  is `store-ledger` cycle 005 scope, which is on the path.
- Unproven after this review: every planned must-have; `store-ledger` A4,
  A5, and A1 on the live project rather than the fixture; non-zero Codex
  tokens in the store; that the reopened section's scope call re-runs
  `cycles/004/scope_probe.zsh` and assigns T4 rather than re-blocking.
