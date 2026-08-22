# Resume here

Rewritten 2026-08-22, late. Read this and `plan.md`; you do not need the
conversation that produced them.

## The one rule for this session

**Never run more than three sections at once.** Everything below assumes it.

## What is running right now

`packaging`, `persona-packs`, `codex-usage`, each as its own background process:

```bash
./.agentic/pm_flow/pm_flow.sh --section <key> run --max-ticks 14
```

Watch them with `./.agentic/pm_flow/watch.py -w`. Spend so far is about $28 of a
$100 rail, $25 per section. Spend is not billed against an API budget here, so
the rails exist as runaway guards, not as cost control.

## The goal

Finish every section in the registry. Not start more of them - finish them.

When one of the three finishes, start the next from this queue, keeping three:

1. `agents-md` - was blocked by a harness defect that is now fixed
2. `topology-compare` - the plan's headline promise
3. `agent-bindings` - MCP and ACP
4. `trace-commands` - blocked until `packaging` lands; it needs `pm_flow.sh`,
   which packaging is rewriting. This is a real file collision, not bookkeeping
5. `store-ledger` - waits on `trace-commands`

## Done

`green-suite`, `installer`, `worktree-isolation`. All three were finished by
hand, not by the flow.

`codex-usage` was closed by the flow on its own - the first section to do that -
and then reopened, because it passed an acceptance that a stub satisfied while
the feature did not work. That reopening is the most important thing in this
file; see below.

## What was learned today, and must not be re-learned

**Acceptance criteria must state an outcome in the running system.** Not a
mechanism, not an artifact appearing. `codex-usage` asked for "a Codex dispatch
writes a non-empty .events.jsonl" and got exactly that from a fake codex
emitting a key real codex never sends, while the code that would carry those
tokens into the store was never called. Every criterion passed; the feature did
not exist. The standard is now written into `tasks/project_decomposition.md`,
`tasks/section_scope.md`, `tasks/section_review.md` and the contract. Hold new
briefs to it.

**Every escalation so far was the harness, not the work.** Four of them: a
sandbox denying `~/.cache/uv`, a flaky test, worktrees placed under `.git`
where write controls refuse them, and a commit obligation no codex-bound role
could discharge. A consultant panel could not have fixed any of them, and a
person rescued each one by hand.

That is now automatic. Every review classifies its rejection as `NONE`,
`HARNESS` or `TASK`. `HARNESS` routes to a single **maintenance engineer** that
repairs the plumbing and hands the section straight back with its failure
streak wiped; `TASK` convenes the panel. Maintenance is bounded by
`escalation.max_maintenance_attempts`; an unclassified rejection is read as
`TASK`, the conservative and expensive answer. **This has not yet fired on a
real run.** Watch for the first one and check it behaves.

## Known defects

- **`install.sh` overwrites `project_state/resume.md`.** It treats this file as
  engine prose alongside `task_contract.md`. Reinstalling destroys it; restore
  from git afterwards. It leaves a misleadingly named `resume.pre-sections.md`.
- **Editing `brief.md` does not re-derive `owned_paths.txt`.** Scope is captured
  at `init-section` and never refreshed, so a brief and the enforced scope can
  disagree silently. Correct both by hand.
- **Killing a run can orphan its model dispatch.** Two `claude -p` processes
  were found alive 38 minutes after their driver was killed, burning quota. The
  suite tests orphan cleanup on a *stall*, not on an external kill of the
  driver. Check with `ps -eo pid,etime,command | grep -E "claude -p |codex exec"`
  after stopping anything.
- **`packaging`'s worktree copy of `tests/packaged_layout_test.sh` makes a real
  codex dispatch.** A test that spends money and minutes. Judge it when that
  cycle comes up for review; it should use a double.
- **Telemetry is still not wired into dispatch.** `telemetry_begin_attempt` and
  `telemetry_end_attempt` are defined in `driver.zsh` and never called, so no
  attempt is recorded and no tokens reach the store. This is now named in
  `codex-usage`'s brief as its own blocker.

## Traps that fail silently

- `local path` in zsh is tied to `PATH` and empties it, so `git` stops being
  findable and the code reports success while doing nothing.
- `git rev-parse --is-inside-work-tree` prints `false` and exits **zero** from
  inside a `.git` directory.
- A glob closure like `<->(.<->)#` needs `EXTENDED_GLOB`, which the engine does
  not set. Without it the pattern matches nothing and every value is refused.
- `python3 - <<'PY'` feeds the *script* on stdin, so `sys.stdin.read()` inside
  returns nothing. A hook written that way logs empty records and looks fine.

## The suite

`zsh tests/pm_flow_test.sh` - 10 PASS groups, exit 0, about 2m45. It runs the
real driver against real installs, which is why it caught the defects above. Do
not mock it and do not trim it to go faster; the last speed-up came from the
engine, not from the tests.
