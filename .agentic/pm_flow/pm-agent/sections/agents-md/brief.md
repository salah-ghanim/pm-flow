### Objective
Write AGENTS.md rather than a vendor-named instructions file.

### Scope
pm-flow installs `CLAUDE.md` into the host repository. AGENTS.md is now the file
every agent looks for, and writing a vendor-named one contradicts this project's
own stated invariant that roles are named, never vendors.

Install AGENTS.md as the source of truth. Leave a CLAUDE.md that points at it if
compatibility is wanted, rather than duplicating content that will drift.

### Priority
- nice-to-have. Nothing breaks today; the project contradicts itself in public,
  which matters more once this is published than it does now.

### Owned paths
- template/CLAUDE.md
- template/AGENTS.md
- README.md

### Dependencies
- installer

### Acceptance
- A fresh install writes AGENTS.md carrying the role router and invariants.
- An existing CLAUDE.md is preserved, not silently overwritten.
- README describes AGENTS.md as the instructions file.
- The suite still passes.

### Rejection conditions
- Content is duplicated between the two files rather than one pointing at the other.
- An existing CLAUDE.md is destroyed.
