# Portfolio log

## 2026-08-22 — `agents-md` panel adjudication

- Decision: SYNTHESIZE proposals 1 and 2.
- Priority: `agents-md` remains nice-to-have; no acceptance criterion is reduced.
- Product order: finish `packaging`, repair section checkout placement and manifest
  enumeration, then re-cut `agents-md` against the packaged layout.
- The repair must place linked checkouts outside the repository and Git metadata,
  filter manifest exclusions relative to `TEMPLATE`, and reject an empty generated
  manifest.
- The feature path remains one full `AGENTS.md` plus a managed `CLAUDE.md`
  `@AGENTS.md` compatibility import, preserving pre-existing content.
- Probe: the committed registry has `packaging` active and `agents-md` active;
  packaging owns `install.sh` and `MANIFEST`.
- Probe: the `agents-md` checkout resolves under `.git/pm-flow/worktrees/...`.
- Probe: `tools/manifest.py` enumerates 74 entries in the main checkout and zero
  in the section checkout.
- Probe: `worktrees_root()` derives its root from Git's common directory, and
  `iter_template_files()` tests exclusion parts on the absolute path.
- Rejected: another unchanged dispatch, a permission-control bypass, and an
  isolation-off main-tree rescue while overlapping packaging work is active.
- What is unproven: an external linked checkout accepts a real headless edit;
  manifest entry sets match between main and linked checkouts after repair; the
  post-packaging AGENTS/CLAUDE install and mutation probes pass.
