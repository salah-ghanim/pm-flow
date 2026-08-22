### Objective
Give the flow a `trace` command and a telemetry config block, so a run can be
shipped to Phoenix, Langfuse or Jaeger without knowing any internals.

### Scope
`store.py`, `telemetry.py`, `catalog.py` and `trace_export.py` exist and work;
`driver.zsh` already records spans. What is missing is the surface: a
`telemetry` block in config.json (enabled, topology, otlp_endpoint), and
`pm_flow.sh trace export|follow|status` wrapping trace_export.py.

Endpoints worth documenting: Phoenix on 6006, Jaeger on 4318, Langfuse on
`/api/public/otel` with Basic auth. All three take OTLP, so only the URL differs.

### Priority
- must-have. The recording layer is finished and invisible; this is what makes
  it usable.

### Owned paths
- template/.agentic/pm_flow/pm_flow.sh
- template/.agentic/pm_flow/config.json

### Dependencies
- green-suite

### Acceptance
- `pm_flow.sh trace export --otlp <url>` ships recorded spans and reports a count.
- `pm_flow.sh trace export --file <path>` writes OTLP/JSON with no dependency
  installed.
- Re-running exports nothing already shipped.
- `telemetry.enabled: false` in config.json disables recording without error.
- The suite still passes.

### Rejection conditions
- Telemetry failure can abort a run. Every call must be guarded.
- The OTLP endpoint is hardcoded to one vendor.
- Any file outside pm_flow.sh and config.json is modified.
