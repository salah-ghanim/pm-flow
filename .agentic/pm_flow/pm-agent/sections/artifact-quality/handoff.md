## Outcome
- A1 — `rank` prints one line per artifact, worst first, each naming the file and any of `length`/`echo`/`shape`/`boundaries`/`stale`; on `main`, 65 lines for 65 artifacts, `grep -Ec 'composite|quality:[0-9]|score[=:][0-9]'` → 0. `bbf704c`, `adba805`.
- A2 — `git status --porcelain` before vs after `rank` → `cmp` exit 0; `find sections \( -name 'quality*' -o -name '*.score' \)` empty. `67d200c`.
- A3 — the run wrote `quality/latest.md`, `latest.json` and a `<utc>.json` snapshot; `show` stdout vs `rank` stdout and vs `latest.md` both `cmp` exit 0. `67d200c`, `1fb989b`.
- A4 — fixture echo finding flips with the copied paragraph; disabling echo detection fails that assertion. `bbf704c`.
- A5 — fixture shape (uncovered `A2`) and stale findings flip likewise, mutation-proven. `bbf704c`.
- A6 — on `main`: `artifact_quality_test.sh` exit 0 (11 PASS), `pm_flow_test.sh` exit 0, `template/.agentic/pm_flow/tests/run.zsh` exit 0 (`pass=74 fail=0`). `1fb989b`.

## Decisions
- No composite score; dimensions stay separate, ranked by finding count then overage.
- Ranking is its own process: no `tick`/`dispatch_role` hook; `cli.py`, `pm_flow.sh`, `driver.zsh` and `prompt_quality.py` unedited. A `pm-flow quality` arm belongs to whoever owns `cli.py`.
- `quality.py` loads `prompt_quality.py` by path (`spec_from_file_location` from `paths.engine_root()`) because `pm_flow/engine/` has no `__init__.py` and sits outside `src/` in a checkout. The 12-word echo rule stays owned there.
- Live dimension counts drift as sections write: diff two builds over one tree rather than a remembered count, and measure `boundaries` by token, not by file.

## Interfaces
- `python -m pm_flow.quality rank [--project <key>] [--out <dir>]`; `show [--project <key>]` reprints the record and exits non-zero naming the directory when absent.
- `.agentic/pm_flow/<project>/quality/{latest.md,latest.json,<utc>.json}` — gitignored by `.gitignore:24`.
- `template/.agentic/pm_flow/artifact_quality.md` — budgets parsed at runtime from its `| File | Word budget |` table, so changing a budget needs no code change.
- `tests/artifact_quality_test.sh`.

## Risks
- `resolve_record_dir` treats `git check-ignore` exit 128 (outside repository) as permission, so `--out` into another checkout writes into its tracked tree. Observed; kept because the fixture needs it.
- ~3% of flagged `boundaries` tokens are slash-bearing non-paths. Settled by census at scope 003; a census above ~10% reopens it.
- Rollback: delete the three owned paths; records are untracked.

## What is unproven
- `echo` and `stale` are fixture-only: no live artifact has produced either finding in any cycle. A real repeated paragraph or pasted design summary surfacing in `rank` would settle it.
- The developer's sandbox denies writes to the host `quality/` directory, so the host write branch was only ever exercised from PM probes.
- One mutation (`--out` bypassing `resolve_record_dir`) trips the absence assertion before the refusal one, so the suite catches that bypass under the wrong name.

## Next action
- None. The workplan is closed and no section depends on further work here. A `pm-flow quality` CLI arm, a `tick` gate or model-graded clarity would each need a new section.
