---

# Task: decompose the research programme into desks

Nothing has been researched yet. Cut this programme into desks that can be owned
independently, then stop. You are not researching anything and you will not
manage the work directly — each desk gets its own lead.

Read:

{{CONTEXT_FILES}}

## What makes a good desk

- It produces something the overview actually needs. A desk that exists to make
  the coverage map look symmetrical is waste.
- It owns a disjoint set of paths. Two desks must never be able to write the
  same file, because they may run at the same time. Jurisdictions, source
  families and synthesis outputs partition cleanly; topics do not.
- It can be judged. If you cannot say what evidence would prove it done, it is
  not scoped yet. "Cover Germany" is not judgeable. "Every German software
  insolvency opened in the window has a record with court, case number,
  administrator and stage, each primary-sourced or explicitly marked
  unobtainable" is.
- It is small enough that a lead can drive it in a handful of assignments, and
  large enough to be worth a lead at all.

## What this kind of programme almost always needs

Decide for yourself, but know the shape of the problem before you cut it.

- **The schema comes first and everything depends on it.** Records written to
  different shapes cannot be compared, and comparison is the entire product. A
  desk that defines the record format, the source-tier rules and the stage
  vocabulary is the one dependency worth serialising the whole programme behind.
- **Sourcing differs by jurisdiction, not by taste.** Some registers publish the
  asset; some publish only the proceeding, and the asset is marketed privately.
  A desk per jurisdiction is a desk per method, which is why it partitions well.
- **Comparables are a desk of their own.** Verified appraisals and closed
  transaction prices are what everything else is priced against, and they are
  found in different places than live proceedings.
- **Synthesis is work, not a by-product.** The overview that answers the mission
  is written by someone whose job it is, from verified records, last.

Order matters. A desk may only depend on desks you have already listed above it,
so emit them in dependency order. Prefer a shallow graph: a long dependency
chain means the programme cannot make progress in parallel and one failure
stalls everything behind it.

Start with the smallest set of desks that could produce a usable answer to the
mission end to end. Depth in one jurisdiction beats a thin line in six. Desks
that merely broaden coverage can be added by a later decomposition.

## Format

Emit one block per desk, in dependency order, using exactly this shape:

```
## Section: <short-kebab-case-name>

### Objective

- What this desk must establish.

### Scope

- In: what belongs here.
- Out: what explicitly does not.

### Priority

- must-have: what the overview cannot answer at all without this desk.

### Owned paths

- research/example/**

### Dependencies

- None.

### Acceptance

- The evidence that proves this desk is done.

### Rejection conditions

- What would make this desk's work unacceptable.
```

Every block needs all seven headings. `Owned paths` takes at least one
repo-relative bullet and may use globs. Each `Dependencies` bullet is the exact
name of a desk listed above this one, or `None.` when there are none.

`Priority` takes exactly one bullet, beginning with `must-have` or
`nice-to-have`, then a colon and one line naming what the overview loses without
this desk. Be honest: `must-have` means the programme does not meet its
completion criteria without this work. Everything else is `nice-to-have`, and a
`nice-to-have` is a desk you are agreeing can be cut later without renegotiating
the mission. A decomposition where every desk is `must-have` has not made a
priority call.

Write acceptance criteria that a lead can actually close. A criterion phrased as
a count of records invites padding; a criterion phrased as a standard of
evidence per record does not.

Emit nothing before the first section block and nothing after the last one. No
preamble, no summary, no closing commentary.
