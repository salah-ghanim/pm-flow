### Objective
Make the store the ledger, and stop writing a text file on every dispatch into
somebody else's repository.

### Scope
`runs/cost_ledger.tsv` is appended on every dispatch, re-parsed from the start to
answer any question, and conflicts on every merge. The store already holds a
strict superset in `attempts`: the same facts plus tokens, duration, attempt
count and the span it belongs to.

Move `cost.py` and `watch.py` onto the store, and write a one-time importer for
existing TSV rows and response envelopes. Keep the TSV write for one release as
a fallback: a budget that silently reads zero authorises the whole limit again,
and this runs against a live install with ten workspaces.

### Priority
- must-have. This is the churn the whole store exists to remove.

### Owned paths
- template/.agentic/pm_flow/cost.py
- template/.agentic/pm_flow/watch.py

### Dependencies

- None.

Store accounting is independently implementable. Trace export is a downstream
consumer of stored telemetry, not a prerequisite for importing or reporting
attempts.

### Acceptance

Stable IDs `A1`–`A4` refer to the bullets below in order.
- Migrated totals equal the totals the old ledger reported, to the cent, on a
  project with existing history.
- `pm_flow.sh cost` and `watch.py` read the store.
- A project with a TSV and no store still reports correct spend after import.
- The suite still passes.

### Rejection conditions
- Budget enforcement reads zero for a project that has already spent money.
- The importer double-counts a dispatch present in both the TSV and an envelope.
- Any file outside cost.py and watch.py is modified.
