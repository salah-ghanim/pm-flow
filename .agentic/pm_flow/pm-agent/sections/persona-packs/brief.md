## Objective

- A system prompt is a first-class, portable artifact: installable from a
  path or a Git URL, droppable onto one seat layer, versioned by content, and
  attributable after it has been replaced.

## Current baseline

- The store separates a portable `persona` from a local `binding`, stacks
  persona layers onto a seat through `seat_personas`, and content-hashes
  every version; `persona_packs` exists.
- `catalog.py` provides `persona add <path|git-url>`, `persona list`,
  `persona update`, `persona swap <seat> <layer> <persona>`.

## Deliverables

- The pack format: one JSON index plus Markdown persona files.
- The four `persona` commands with provenance (source URL, commit, content
  hash) on every installed version.

## User-visible scenarios

1. `pm-flow persona add https://…/reviewer-pack.git` installs the pack;
   `persona list` shows each persona with its source and commit.
2. `persona swap developer base sharper-developer` changes only that layer;
   the next dispatch's prompt carries the new layer and the other layers are
   unchanged.
3. After editing a persona and `persona update`, the old version's attempts
   still name the old version.

## Interfaces produced

- Pack index schema; the `persona` commands; provenance columns on
  `personas`.

## Interfaces consumed

- `installer`'s layout; the store's `personas`, `persona_packs`,
  `seat_personas`, `topology_agents.overrides`.

## Scope

- In: the pack format, install from path and Git, update, swap, provenance.
- Out: persona identity cards (`persona-cards`), remote authenticated Git
  transports.

## Non-goals

- Executing anything from a pack at install time.
- A hosted registry.

## Priority

- must-have: this is the social surface of the project — prompts are what
  people will share and measure.

## Owned paths

- `template/.agentic/pm_flow/catalog.py`
- `template/.agentic/pm_flow/store.py`

## Dependencies

- installer

## Constraints and fixed decisions

- A persona never carries a CLI, a model or a tool grant; the install refuses
  one that does.
- Versions are immutable content rows; a second pack cannot claim an already
  attributed persona; cross-pack collisions reject the whole install.

## Acceptance

- A1: `persona add` installs the same pack from a local path and from a
  `file://` Git URL through the real Git CLI, recording source URL and
  commit.
- A2: `persona swap` on one layer leaves the seat's other layers and its
  binding unchanged, and the next dispatch's composed prompt carries the new
  layer.
- A3: `persona update` from a changed source installs a new version and keeps
  the old version's rows and attempts attributable.
- A4: Editing a persona produces a new content version; the old one stays
  listed with its attempts.
- A5: `zsh tests/pm_flow_test.sh` exits 0.

## Rejection conditions

- A persona file carrying a model name, a CLI name or a tool grant installs.
- Installing a pack executes anything from it.
- A file outside Owned paths is modified.

## Open questions

- None.
