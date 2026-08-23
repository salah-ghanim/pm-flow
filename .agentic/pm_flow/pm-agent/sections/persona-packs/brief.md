### Objective
Make system prompts first-class, portable and swappable: installable from
elsewhere, droppable onto a seat, and measurable against what they replaced.

### Scope
The store already separates a portable `persona` from a local `binding`, stacks
persona layers onto a seat through `seat_personas`, and content-hashes every
version. `persona_packs` exists and is unused.

Build the surface: `persona add <path|url>`, `persona list`, `persona swap
<role> <persona>`, and a pack manifest carrying name, author, licence, version
and tags. A pack is a git repository of markdown personas with an index, so no
hosted infrastructure is needed for anyone to publish one.

A persona must never carry a CLI, a model or a tool grant. Those are properties
of the machine it lands on, and a persona that carries them is neither portable
nor safe to install.

### Priority
- must-have. This is the social surface of the project: the community writes
  excellent prompts for analysts, engineers and product managers, and nowhere
  today can tell you whether any of them work.

### Owned paths
- template/.agentic/pm_flow/catalog.py
- template/.agentic/pm_flow/store.py

### Dependencies
- installer

### Acceptance

Stable IDs `A1`–`A5` refer to the bullets below in order.
- A persona pack can be installed from a local path and from a git URL.
- Swapping one layer of a seat leaves the other layers intact.
- An installed persona keeps its provenance and can be updated from source
  without losing what was measured about it.
- Editing a persona produces a new version; the old one stays attributable.
- The suite still passes.

### Rejection conditions
- A persona file carries a model name, a CLI name, or a tool grant.
- Installing a pack executes anything from it.
- Any file outside catalog.py and store.py is modified.
