## Outcome

- **A1** `installed --project legacy-two cost` prints `TOTAL\t4.3750`,
  computed by `awk`/`python3` from the TSV and the envelope-only file, not by
  `cost.py`; the blank-cost row's `7.777` envelope stays out. `558837f`,
  `c6c3c3b`, `79b7dd9`.
- **A2** `pm_flow.cli.main` prints
  `ATTEMPT…alpha developer codex-one codex 0.0400 13937 5`,
  `grep -c cost_ledger watch.py` → `0`. `c6c3c3b`, `915911a`, `79b7dd9`.
- **A3** Two runs byte-identical (`cmp`), a later `cost.py import` →
  `imported=0`, no `response_path` twice. `558837f`, `79b7dd9`.
- **A4** One CLI dispatch adds one `ATTEMPT` at `0.5000`, `runs/` holds
  `pm_flow.db`, no `cost_ledger.tsv`, `grep -c cost_ledger_file driver.zsh`
  → `0`; at the ceiling the next prints `project budget exhausted`, count
  unchanged, no fallback warning. `1c5a301`, `79b7dd9`.
- **A5** Four suites exit 0 (`store ledger tests passed`, 10 `PASS:`,
  `all suites passed` 35/41/32/58/74, 13 `PASS:`) on `main` `75462bd`.

## Decisions

- Section = `attempts.task_id → tasks.key`, `(project)` when NULL. Readers
  never filter `project_id`: the importer keys on `basename(project_dir)`, the
  driver on `PROJECT_KEY`, and a filter reads zero.
- Import keys on `response_path`. A TSV row wins for its path even with a
  blank cost; only envelopes the TSV lacks are priced. Sums are
  `COALESCE(cost_usd,0)` over every `status`.
- `record_dispatch_cost` is a no-op whose call (`driver.zsh:1036`) sits
  outside the five owned functions; nothing may import before
  `telemetry_end_attempt` (`:1056`).

## Interfaces

- `cost.py total <dir> [section]` → one number; `report <dir>` → section
  lines, `TOTAL`,
  `ATTEMPT\t<started_at>\t<section>\t<role>\t<label>\t<cli>\t<cost>\t<in>\t<out>`;
  `import <dir>` → `imported=N`. The `.tsv` arities exit 2.
- Store: `<dir>/runs/pm_flow.db` (`store.default_path`), ignored by
  `*/runs/*`. `pm-flow cost`, `spent_usd`, `dispatch_count`, `watch.py` read
  it; count dispatches as `^ATTEMPT` lines.
- Fixtures seed spend via `telemetry.py attempt-start|attempt-end`
  (`governance.zsh:198`); a TSV registers nowhere.

## Risks

- `spent_usd` fails open (`9452a80`): a broken reader returns `0` and
  re-authorises the whole budget — the brief's first rejection condition by
  another route. Truncate a store and tick.
- `pm-flow status|cost` between the envelope landing and `attempt-end`
  (`:1041-1056`) counts it twice — two rows share a `response_path`.
- `spent_usd` globs `**/*.response.json`, so tick latency grows with envelope
  count; `watch.py` shows `$0.00` on any `sqlite3.Error`, display only.

## What is unproven

- No real install imported; every parity figure is a 3-5 row fixture. Settle:
  `cost.py import` on `pm-agent` and each golden-grid workspace, against its
  own TSV arithmetic.
- "Installed" means `pm_flow.cli.main` with `PM_FLOW_ENGINE_ROOT` at the
  suite's stubbed copy, not a pip wheel. Settle: `pm-flow cost` from a venv
  wheel on a legacy-TSV project.
- No priced row came from a live agent — stub `0.5000` or fixture, Codex
  tokens replayed from `tests/fixtures/codex_events_real.jsonl`. Settle: one
  real dispatch against the billed figure.
- A4's `git status | grep runs/` cannot fail under `*/runs/*`; A4 rests on
  `ls "$PROJECT_DIR/runs"`. Settle: unignore `runs/` in a fixture. Live sign
  only: `pm-agent`'s `cost_ledger.tsv` mtime stopped at T4's merge while
  `pm_flow.db` kept growing.
- The double-count window and fail-open path are recorded, never exercised.

## Next action

- Portfolio review: decide whether `assert_within_budget`
  (`driver.zsh:610-624`) must fail closed — outside these five functions, so
  it needs a boundary extension.
- Import the real installs before trusting their spend figures.
