# persona-packs handoff

## Outcome

Complete on main through cycle 009. Persona packs install from local paths and
Git URLs, retain source/commit/content provenance, update without rewriting old
versions, and swap exactly one seat layer without changing its siblings or
binding. The next dispatch records the new stack while prior attempts retain
the old one.

## Decisions

- A pack is a validated JSON index plus Markdown persona files; nothing from a
  pack executes at install time.
- Versions are immutable content rows. Identical standalone personas can be
  adopted; a second pack cannot claim an already attributed persona.
- Swap uses existing topology overrides and seat-persona ordering.

## Interfaces

- `catalog.py ... persona add <path|git-url>`, `persona list`, `persona update`,
  and `persona swap <seat> <layer> <persona>`.
- Source URL, source commit, manifest version, and content hash remain queryable.

## Risks

- HTTPS/SSH Git transports were not exercised; `file://` used the real Git CLI.
- Inherited `PM_FLOW_*` variables can misroute a standalone catalog test; clean
  them in acceptance harnesses.

## What is unproven

- Remote authenticated Git transports. They do not change pack semantics.

## Next action

Declare the section complete; `persona-cards` then takes `catalog.py`.
