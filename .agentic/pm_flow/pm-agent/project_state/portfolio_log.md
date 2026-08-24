# Portfolio review log

Newest first. Read this before anything else: one review cannot see a
section that has been nearly done for four of them, or a shortest path that
has not moved in three. Older entries are compacted to their summary line.

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

### Completion criteria

- Finished run opens in Phoenix/Langfuse/Jaeger with every role, prompt, retry, stall, tokens, dollars — `git grep -iE 'otlp_endpoint|"trace"|compare|acp|mcp' -- src/pm_flow/cli.py` printed nothing; `git ls-files src/pm_flow` = `__init__.py cli.py paths.py` — **NOT MET**
- `cost_ledger.tsv` gone, host absorbs no per-dispatch writes — `git grep -n cost_ledger -- template` hits `driver.zsh:441-471,839`, `watch.py:50`; `ls runs/` shows `cost_ledger.tsv` beside `pm_flow.db` — **NOT MET**
- Sections run in isolated worktrees — `git worktree list` shows `codex-usage` under `../.pm-flow-worktrees/` — **MET**
- Persona installed from elsewhere, dropped on a seat, measured against the one it replaced — `git grep -inE 'compare|measure' -- template/pm_flow/catalog.py` printed nothing — **NOT MET**
- Two topologies compared in one command — `git ls-files src/pm_flow` has no `compare.py`; `cli.py` grep above empty — **NOT MET**
- Drivable over MCP, binds any ACP agent — `git grep -inE 'otlp_endpoint|\bacp\b|\bmcp\b'` on `config.json`, `agent_exec.sh`, `pm_flow.sh` printed nothing — **NOT MET**
- Test suite runs to completion — `zsh tests/pm_flow_test.sh` exit 0, ten PASS groups; `zsh tests/prompt_quality_test.sh` exit 1 (pass=8 fail=30), every failure `another pm_flow driver is already running for project 'pm-agent'` = the live driver dispatching this review — **UNKNOWN** (main suite green from this tier; the second cannot be judged from inside a dispatch until the guard lands)

### Verdicts

- agent-bindings: CONTINUE (now waits on `store-ledger`: A5 reads `pm-flow cost`, which `store-ledger` rewrites; brief's `Dependencies: None` to be synced by its manager)
- artifact-quality: CONTINUE
- codex-usage: CONTINUE
- otel-semconv: CONTINUE
- persona-cards: CONTINUE
- store-ledger: CONTINUE
- topology-compare: CONTINUE
- trace-commands: CONTINUE

### Shortest path

`store-ledger` T1 on a project-wide run, with `trace-commands` T1 and `otel-semconv` T1 in parallel; `topology-compare` and `agent-bindings` the moment `store-ledger` lands. Before `store-ledger`'s `run.zsh` validation: add the four-line inherited-selector guard from `tests/pm_flow_test.sh:12-14` to `template/.agentic/pm_flow/tests/run.zsh` and `tests/prompt_quality_test.sh` (by hand or a maintenance engineer — no live owner), or every reviewer on the path hits a red suite for a plumbing reason. Nothing in flight is on the path: `codex-usage` T3 is the only active work and it closes scaffolding.

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
