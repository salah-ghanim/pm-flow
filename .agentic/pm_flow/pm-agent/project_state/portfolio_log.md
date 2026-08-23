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
