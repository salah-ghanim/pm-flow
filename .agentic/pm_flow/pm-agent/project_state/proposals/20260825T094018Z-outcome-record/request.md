Owner request. Priority: must-have. The product's mission line — run the same
work under two team designs and know whether it helped — has no outcome data to
compare. Today the store's `outcomes` table holds only four derived
`section_status` rows; per-cycle review verdicts (GO / GO_WITH_CHANGES / NO_GO /
UNPARSED), obstruction classifications (NONE / HARNESS / TASK), scope decisions
and completion decisions never reach the store or the exported traces. Also 123
of 128 `runs` rows are stuck at status `running` because run end is never
recorded.

Wanted outcome: every cycle decision the driver records lands as (a) a row in
`outcomes` tied to its attempt/run, written through the existing
`telemetry.py outcome` subcommand which exists and is never called, and (b) a
`gen_ai.evaluation.result` span event per the OTel GenAI semantic conventions
(added in semconv v1.38.0; the repo pins v1.37.0 in `src/pm_flow/semconv.py`
with a revision-swap test that shows how to move the pin). `runs` rows must be
closed with a real end status by both `run` and `tick`, including when a tick
fails. Everything must be visible end-to-end in a real OTLP backend (Arize
Phoenix or Jaeger run locally for the check) after `pm-flow trace export`, not
only in a loopback test receiver — the telemetry config block already points at
`http://localhost:4318`.

Failure to record an outcome must never fail a dispatch (same swallow-and-exit-0
invariant `telemetry.py` already holds). Suggested owned paths:
`template/.agentic/pm_flow/telemetry.py`, `template/.agentic/pm_flow/driver.zsh`
(the record_cycle_decision / run begin-end call sites), `src/pm_flow/semconv.py`
if the pin moves, and a new test suite. The otel-semconv section owned
`telemetry.py` and `semconv.py`; it must be terminal before this section is
created, or its ownership must be respected. `pm-flow compare` (topology-compare,
done) is the consumer that should gain a real outcome column once this data
exists, but extending compare is not required here.
