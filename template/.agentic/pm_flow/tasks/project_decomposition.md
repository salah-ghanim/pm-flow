---

# Task: decompose the product into sections

Nothing has been built. Cut the product into sections a manager can own
independently, in dependency order, then stop. You implement nothing and manage
nobody; each section gets its own manager.

Read:

{{CONTEXT_FILES}}

## What a section is

- It delivers something the product needs. A section that exists to complete a
  diagram is waste.
- Its owned paths are disjoint from every other section's. Sections run
  concurrently, and two may never write the same file.
- It can be judged: every acceptance bullet names an observation a reviewer can
  make without reading the diff.
- It is small enough for a handful of assignments and large enough to be worth
  a manager.

A section may depend only on sections listed above it; prefer a shallow graph.
Start with the smallest set that yields something usable end to end and leave
improvements to a later decomposition.

## Acceptance criteria

State the outcome in the running system, never the mechanism that produces it:
"the cost report shows non-zero tokens for that dispatch", not "an events file
is written". A criterion that stops short of the product's own goal leaves the
section disconnected. An integration with an external tool is proven against
that tool; where a real call cannot be made, the criterion says so and names
what would settle it. Each bullet begins with a stable ID: `A1`, `A2`, and so
on.

## Format

Emit one block per section, in dependency order, nothing before the first and
nothing after the last:

```
## Section: <short-kebab-case-name>

### Objective
- One sentence: what this section makes true.

### Current baseline
- What exists today that this section starts from, by path or command.

### Deliverables
- Each artifact or behaviour the section produces.

### User-visible scenarios
- Numbered scenarios a person could run, from command to observed result.

### Interfaces produced
- Files, commands, schemas or contracts other sections will consume. `- None.`

### Interfaces consumed
- What this section reads from other sections or the repository. `- None.`

### Scope
- In: what belongs here.
- Out: what explicitly does not.

### Non-goals
- Adjacent work that is tempting and excluded.

### Priority
- must-have: <what the product cannot do without this section>

### Owned paths
- src/example/**

### Dependencies
- None.

### Constraints and fixed decisions
- Decisions already taken that the manager must not reopen. `- None.`

### Acceptance
- A1: <observable outcome and how it is checked>

### Rejection conditions
- What makes delivered work unacceptable even when every criterion passes.

### Open questions
- Questions only the owner can settle. `- None.`
```

`Priority` is one bullet beginning `must-have` or `nice-to-have`, a colon, and
one line naming what the product loses without the section. `must-have` means
the product cannot meet its completion criteria without it; a decomposition in
which everything is must-have has not made a call. `Owned paths` takes at least
one repo-relative bullet and may use globs. Each `Dependencies` bullet is the
exact name of a section listed above this one.
