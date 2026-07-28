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

### Owned paths

- src/example/**

### Dependencies

- None.

### Acceptance

- The evidence that proves this section is done.

### Rejection conditions

- What would make this section's work unacceptable.
```

Every block needs all six headings. `Owned paths` takes at least one
repo-relative bullet and may use globs. Each `Dependencies` bullet is the exact
name of a section listed above this one, or `None.` when there are none.

Emit nothing before the first section block and nothing after the last one. No
preamble, no summary, no closing commentary.
