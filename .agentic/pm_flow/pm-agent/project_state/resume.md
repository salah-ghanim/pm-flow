# Resume here

Written 2026-08-22 at the end of a long session. Read this and `plan.md`; you do
not need the conversation that produced them.

## Where the work stands

Shipped and verified on main (`b864674`):

- **The store.** SQLite schema with runs, attempts, spans, outcomes, and a
  persona/binding split. A persona names no model, so it is portable; a binding
  is machine-local. `seat_personas` stacks layers, and the existing
  `roles/` + `domains/<d>/roles/` files already map onto base + domain.
- **Telemetry recording and export.** Both GenAI and OpenInference attributes on
  one span, verified against a live OTLP listener. Codex token counts read from
  its JSONL event stream, which is the only place they exist.
- **The catalogue.** Syncs definitions into the store and renders a linked
  markdown vault. Idempotent.
- **Manifest-driven install**, a shipped `.gitignore`, `pm-flow version` and
  `pm-flow upgrade`, and a `.agentic` migration that also rewrites recorded paths.
- **Packaging.** `pyproject.toml` ships the engine as package data; a wheel was
  built and run from a clean venv with no checkout present. `paths.py` holds the
  layout for both languages, with IntelliJ-style `$PROJECT$` macros so persisted
  paths survive a move.

## Do these in order

The first two are hand work and the reason is the same for both: they edit files
the driver executes while it is running, and the mitigation for that is itself
one of them.

## Priority

1. **green-suite** - by hand, not by the flow. It owns the acceptance check
   everything else is graded on, and its fix is inside `driver.zsh`, which the
   flow executes while running.
2. **worktree-isolation** - by hand, same reason. It is the mitigation that makes
   self-hosting safe, and it cannot isolate its own work.
3. **packaging** - the re-baselining. Foundational: several sections below become
   cheaper or unnecessary once the engine stops being copied.
4. Then the rest, re-cut against the packaged layout: codex-usage,
   trace-commands, store-ledger, persona-packs, agents-md.

Steps 3 and 4 are the flow's work once 1 and 2 land, because worktree isolation
removes the self-modification hazard. Close `installer` first - it is finished
and only needs its completion review - or `persona-packs` and `agents-md` stay
blocked behind it.

Re-cutting in step 4 is not optional bookkeeping. Those five sections were scoped
against a layout where the engine lives in the repository. After packaging it
does not, so their owned paths are wrong by construction. Re-cut them from the
briefs rather than editing `owned_paths.txt`, and note that editing a brief alone
does not update the enforced scope - see the defect below.

## Before handing anything to the flow

- The suite must run to completion. Every brief's acceptance says "the suite
  still passes"; today it halts at one pass, so no review has mechanical
  evidence and a PM can only take the developer's word.
- `installer` is finished but still reads `planned`. Governance requires a PM
  completion review to close it, and `persona-packs` and `agents-md` wait behind
  it. Closing it costs one dispatch.
- Telemetry is recorded but **not wired into dispatch**. The helpers in
  driver.zsh are deliberately uncalled: wiring them regressed the scheduling
  tests with no error on any stream, and the cause is unexplained. Re-wire only
  with a test proving a dispatch still happens.
- `budget.max_usd` is now 40 with 8 per section. Those are rails, not estimates.

## Known defects

- **The dispatch-output guard does not fire in the harness.** Extracted and run
  standalone against the exact fixture the suite writes, it refuses correctly and
  names the offending path. Inside the harness it does not, so `tick` succeeds
  where it should have re-scoped.

  Two hypotheses, one already dead:

  - *Dead:* a symlinked temp path (`/var` vs `/private/var` on macOS) making the
    guard's computed path differ from the fixture's. `repo_relative_path`
    resolves both sides before comparing, so this cannot be it. Do not spend
    time here.
  - *Live:* the harness builds `DRIVER_REPO="$TEST_ROOT/driver repo"` - **with a
    space**. That is deliberate, and it is the only structural difference between
    the standalone reproduction, which works, and the harness, which does not.

  Cheapest next step is not more reading: instrument `assert_output_not_writable`
  to print the `relative` and `basename` it computes and the first 200 bytes of
  the assignment it is matching against, run the suite once, and compare them to
  what the fixture wrote. That answers it in one run.
- **Editing `brief.md` does not re-derive `owned_paths.txt`.** Scope is captured
  at `init-section` and never refreshed, so a brief and the scope actually
  enforced can disagree silently. green-suite hit this; its file was corrected by
  hand. This is a real pm-flow bug, found by using it.
- **`packaging` is scoped narrowly on purpose.** The registry refused a wider
  scope because it overlapped three sections scoped against the layout packaging
  replaces. That refusal was correct: packaging is a re-baselining, not a peer.
  Move the engine into the package only after those sections land or are re-cut.
