## Outcome
- A1 — wheel-driven `pm-flow compare lean heavy --max-ticks 6`: store reads exactly `heavy|wheel-topology-project` / `lean|wheel-topology-project`, arm `copy_path`s differ, `starting_commit` equals fixture HEAD.
- A2 — eight contract columns in order against a hand-computed fixture (`cost_usd 4.0000 2.5000`, `tokens 310 250`, …), reconciled to `cost.py total` `6.5000`; driven `wall_clock_s` non-zero.
- A3 — last line `Limits: lean n=1; heavy n=1. No difference between the arms can be inferred.`; deleting it turns the suite red, and per-topology run counts are asserted separately, so it counts runs not dispatches.
- A4 — `compare heavy missing`, run after a successful compare, exits non-zero, prints no stdout, names both flow and engine document paths, and leaves a non-zero attempt count unchanged.
- A5 — `--persona lean:pm=cpo` yields `lean|cpo` / `heavy|pm` in `attempts.persona_stack` and in the report; neutralising the swap turns the suite red.
- A6 — six suites exit 0 post-merge: `topology_compare_test.sh`, `pm_flow_test.sh`, `packaged_layout_test.sh`, `store_ledger_test.sh`, `prompt_quality_test.sh`, `agent_bindings_test.sh`.
- Every ID's evidence lives on `main` at `a81a9a0`/`b5e667a`.

## Decisions
- Engine Python lives in `template/.agentic/pm_flow/`, not `src/pm_flow/`; the brief's owned paths are wrong.
- Packaged `topologies`/`roles`/`domains` resolve flow-first, engine-second, never copied into a repository.
- One accounting: `cost_usd` from `cost.py`; the `topology_comparison` view gives attempts, tokens, duration only.
- Persona swaps are an operator argument (`--persona t:role=persona`), never implicit.
- A `runs` row is one `run`/`tick` invocation, not one dispatch — that is `n_runs`.
- New files under `template/.agentic/pm_flow/` must join `install.sh`'s `COPIED_ENGINE_*` lists the same cycle.

## Interfaces
- `pm-flow compare <a> <b> [--max-ticks n] [--persona t:role=p] [--keep-copies]`; `pm-flow compare --report <run-a> <run-b>`.
- Topology documents: `<flow>/topologies/<key>.json`, else the wheel's `pm_flow/engine/topologies/`.
- Columns, in order: cost_usd, tokens, cycles_to_done, rescue_rate, abandon_rate, escalation_depth, wall_clock_s, n_runs; then per-arm persona lines; then the limits sentence.
- Breaking: `pm-flow cost`'s `ATTEMPT` line is now ten tab fields, field 10 the run's topology key (`-` if none); fields 1-9 unchanged. It edits `store-ledger`'s `cost.py`.

## Risks
- Arm wall clock is unbounded — 702.4s vs 4.4s at cycle 005, 49s at 006. A suite timeout reveals it; bound the arm rather than loosening `wall_clock_s > 0`.
- `rescue_rate` keys on `role_key='10x_developer'`, `abandon_rate` on `outcomes` rows emitted at `do_abandon`/`do_complete`; a new rescue site or moved abandon path silently zeroes a column.

## What is unproven
- Budget-exhausted runs: `assert_within_budget` exits via `fail` after `telemetry_begin_run`, so `runs.ended_at` stays NULL and that run drops out of `wall_clock_s`. An arm hitting the cap would settle it; the fix is an `EXIT` trap at driver top level.
- Arms only ever compared at 5-6 ticks on stub projects; no real multi-section project has run both arms.
- Field 10 was confirmed by a data probe, not a source mutation — a PM does not edit source.

## Next action
- Product officer: fix the brief's owned paths. `store-ledger` and any `pm-flow cost` reader: adopt the ten-field `ATTEMPT` line. Open a task for the `fail`-path run if it must be measurable.
