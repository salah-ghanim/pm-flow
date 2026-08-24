---

# Task: cut one section from the owner's request

The owner has asked for a capability in their own words and wants it named
`{{SECTION_NAME}}`. Decide whether it deserves a section of this product, and
if so cut exactly one, under that name, in the same form the decomposition
uses, so a manager can own it.

Read:

{{CONTEXT_FILES}}

Paths already owned by live sections, which this section may not claim:

{{OWNED_PATHS}}

## What to settle

- Whether the plan needs it. Tie the section to the plan's objective or to one
  of its completion criteria, or say which plan bullet it serves; if none
  does, decline rather than invent a need. The owner's reasons are evidence,
  not a verdict.
- Whether it is already covered: a live section's scope, a cancelled section's
  reason, or something `main` already does. Probe the repository with bounded
  commands before claiming either.
- Its priority against the plan. `must-have` only when the product cannot meet
  a completion criterion without it.
- Its owned paths: new paths, or paths no live section owns. A capability that
  has to change a file another section owns depends on that section and says
  so under `Dependencies` and `Constraints and fixed decisions`.
- Acceptance as outcomes in the running system, with an inline ID on every
  bullet, and at least one criterion a person could check from the user-visible
  scenarios without reading the diff.

## Respond with these sections only, each as a Markdown heading

1. `## Assessment` - what the request is for, which plan bullet it serves or
   why none does, and what already covers it, with the probes you ran
2. one section block, for `CUT`, in exactly this shape, or `Not applicable.`
   for `DECLINE`:

{{SECTION_BLOCK}}

3. `## Decision` - exactly one line beginning `CUT` or `DECLINE`, then a short
   reason; `DECLINE` names what already covers the request or which plan
   bullet would have to change

A `Dependencies` bullet is the exact key of a live section and nothing else on
the line, or `None.`. It holds this section until that one is done, so name
only a section without which this one's acceptance cannot pass; a later
hand-over of one file is a constraint, not a dependency. `Priority` is one
bullet beginning `must-have` or `nice-to-have`, a colon, and what the product
loses without the section.
