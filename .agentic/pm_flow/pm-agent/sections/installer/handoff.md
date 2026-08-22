# installer handoff

## Outcome

A stock install produces a complete flow directory. Verified by hand against a
fresh empty target rather than by reading install.sh: seven python modules land
(`catalog.py`, `cost.py`, `store.py`, `telemetry.py`, `trace_export.py`,
`upgrade.py`, `watch.py`), `requirements-telemetry.txt` names the two
OpenTelemetry packages, and the installed `.gitignore` ignores the store
(`*/runs/pm_flow.db{,-wal,-shm}`) and `__pycache__/`.

## Decisions

The store is gitignored deliberately. It is local, it is rewritten on every
dispatch, and committing it recreates exactly the churn the store exists to
remove. Definitions are committed; records are not.

Telemetry packages are optional and recording never depends on them. A missing
import must cost an observation, not a dispatch — so `trace export --file`
needs nothing installed at all, and only `--otlp` needs the SDK.

Installation became MANIFEST-driven rather than a hand-maintained copy list,
which is why "add four modules" did not turn into a fifth place to forget them.

## Interfaces

`install.sh <target> [--name] [--project-key] [--domain] [--add-project]`.
Reinstalling into an existing target refreshes the shared engine and preserves
config.json, the recorded domain, the plan and run history — asserted by the
suite, not assumed.

## Risks

Installing a second project workspace refreshes the shared scripts for every
workspace in that flow directory but only refreshes the selected workspace's
contract and prompts. The installer warns and names the others; the suite
covers that path.

## What is unproven

Nothing above. Each claim was checked against a real install performed for this
review.

## Next action

packaging. Its acceptance deletes most of what this section shipped — MANIFEST,
`upgrade.py` and the file-lifecycle machinery exist to manage N copies of the
engine, and packaging removes the copying. That is not waste: the installer is
what makes today's flow reproducible, and packaging cannot be verified without
a working install to migrate from.
