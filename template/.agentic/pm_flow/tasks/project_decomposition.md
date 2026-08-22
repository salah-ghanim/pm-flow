---

# Task: decompose the product into sections

Nothing has been built yet. Cut this product into sections that can be owned
independently, then stop. You are not implementing anything and you will not
manage the work directly — each section gets its own project manager.

Read:

{{CONTEXT_FILES}}

## What makes a good section

- It delivers something the product actually needs. A section that exists only
  to satisfy the diagram is waste.
- It owns a disjoint set of paths. Two sections must never be able to write the
  same file, because they may run at the same time.
- It can be judged. If you cannot say what evidence would prove it done, it is
  not scoped yet.
- It is small enough that a manager can drive it in a handful of assignments,
  and large enough to be worth a manager at all.

Order matters. A section may only depend on sections you have already listed
above it, so emit them in dependency order. Prefer a shallow graph: a long
dependency chain means the project cannot make progress in parallel and one
failure stalls everything behind it.

Start with the smallest set of sections that could produce something usable
end to end. Sections that merely improve a working product can be added later
by a later decomposition.

## Format

Emit one block per section, in dependency order, using exactly this shape:

```
## Section: <short-kebab-case-name>

### Objective

- What this section must deliver.

### Scope

- In: what belongs here.
- Out: what explicitly does not.

### Priority

- must-have: what the product cannot do at all without this section.

### Owned paths

- src/example/**

### Dependencies

- None.

### Acceptance

- The evidence that proves this section is done.

### Rejection conditions

- What would make this section's work unacceptable.
```

## What an acceptance criterion has to be

State the outcome in the running system, not the mechanism that produces it. A
criterion is only worth writing if failing it would mean the product is worse
off, and passing it would mean a user of this project can do something they
could not do before.

This is not style. `codex-usage` was accepted, marked done, and delivered
nothing usable. Its acceptance read "a Codex dispatch writes a non-empty
`.events.jsonl` beside its response" - a mechanism. It was met by a *fake*
codex emitting a key real codex never sends, so every real dispatch recorded no
tokens at all; and the code that would have carried those tokens into the store
was never called, so even correct parsing would have reached nothing. Every
criterion passed. The feature did not exist.

So:

- Name the observable, not the artifact. Not "a file is written" but "`pm-flow
  cost` reports non-zero tokens for that dispatch". Not "the parser handles the
  schema" but "the recorded run shows the tokens the provider charged for".
- A section that integrates with an external tool is proven against that tool.
  A stub proves the stub. Where a real call cannot be made, say so in the
  criterion itself and name what would settle it, rather than letting a double
  stand in silently.
- End the chain where the project's own goal begins. `plan.md` says what this
  product is for; a criterion that stops short of it leaves the section
  disconnected, and a disconnected section can be complete and worthless at the
  same time.
- Prefer a criterion someone else could check without reading the diff.

Every block needs all seven headings. `Owned paths` takes at least one
repo-relative bullet and may use globs. Each `Dependencies` bullet is the exact
name of a section listed above this one, or `None.` when there are none.

`Priority` takes exactly one bullet, beginning with `must-have` or
`nice-to-have`, then a colon and one line naming what the product loses without
this section. Be honest: `must-have` means the product does not meet its
completion criteria without this work. Everything else is `nice-to-have`, and a
`nice-to-have` is a section you are agreeing can be cut later without
renegotiating the mission. A decomposition where every section is `must-have`
has not made a priority call.

Emit nothing before the first section block and nothing after the last one. No
preamble, no summary, no closing commentary.
