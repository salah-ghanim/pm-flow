# Portfolio log

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
