### Objective
Ship the new modules in a stock install, and stop the store and bytecode leaking
into the host repository.

### Scope
install.sh does not copy store.py, telemetry.py, catalog.py or trace_export.py,
so a stock install has a driver that calls modules which are not there. Add them
alongside cost.py and watch.py, add `requirements-telemetry.txt` naming
`opentelemetry-sdk` and `opentelemetry-exporter-otlp-proto-http`, and make the
installed repo ignore `runs/pm_flow.db*` and `__pycache__/`.

The store is deliberately gitignored: it is local, it is written on every
dispatch, and committing it recreates the churn the store exists to remove.

### Priority
- must-have. Without it every other section works only on this machine.

### Owned paths
- install.sh
- .gitignore

### Dependencies
- green-suite

### Acceptance
- A fresh install into an empty repo produces a flow directory containing all
  six python modules.
- The installed repo ignores the store and bytecode.
- Reinstalling preserves config.json, recorded domains, plan and run history.
- The suite still passes.

### Rejection conditions
- The store is committed into the host repository.
- A reinstall overwrites a project's recorded domain or plan.
- Any file outside install.sh and .gitignore is modified.
