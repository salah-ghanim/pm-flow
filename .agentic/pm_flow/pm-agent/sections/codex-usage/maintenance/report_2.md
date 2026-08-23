# Obstruction

The reviewer for `codex-usage` is a `codex`-bound, `scoped`-tier role, and the acceptance it was given requires that reviewer to independently run a real authenticated Codex dispatch — which its access tier deliberately forbids, so the review can never pass however correct the implementation is.

# Cause

Two boundaries sit in front of a nested Codex dispatch, and only the first was plumbing.

**First (fixed).** A nested `codex` inherits `CODEX_HOME=$HOME/.codex`, which is outside the outer codex role's `workspace-write` sandbox, so it died at `failed to initialize in-process app-server client` before emitting a single event. That is a harness fault: the harness never told the child where it was allowed to keep its state. The fix is to relocate `CODEX_HOME` into the dispatch's own work dir — inside the writable area the sandbox already grants — rather than widening the sandbox to reach the user's real credentials. Attempt 1 of this maintenance had written that; I confirmed it, and hardened the one unsafe edge in it (below).

**Second (not plumbing).** With `CODEX_HOME` fixed the nested codex authenticates and then fails on DNS, because a codex role's sandbox gives its child commands no network. That is not an accident of the backend. `agent_exec.sh` builds the `scoped` tier on the claude backend from an explicit allowlist (`DEFAULT_SCOPED_BASH`, agent_exec.sh:229) that grants `git`, `pytest`, `ls`/`cat`/`grep`, `nc` — and deliberately withholds a general shell and `pm_flow.sh run`/`tick`, with the comment *"a dispatched role must not be able to dispatch the flow."* Network reaches roles only through `fetch.sh`, a context-free reader. So on both backends the scoped tier means: no arbitrary shell, no outbound calls, no dispatching the flow. Codex's network denial is that same tier being enforced, just with an uglier error.

Enabling `sandbox_workspace_write.network_access` for codex roles, or moving `pm` into `write_roles`, would each hand every managing role the capability the tier exists to withhold. Both are defeating the gate, so I did neither.

The developer role (`claude`, `write` tier) *can* do a real Codex dispatch, and did — cycle 005's review says the implementation shows "no confirmed task defect". Only the independent re-run at review time is impossible.

# What I changed

- `template/.agentic/pm_flow/agent_exec.sh` + the installed engine copy: made the refreshed-credential copy-back atomic. It was `cp -p` straight over `$HOME/.codex/auth.json`; sections run in parallel, so two dispatches finishing at once could leave a starting dispatch reading a half-written credential and lose the run its login. Now staged in the same directory and landed by `mv`.
- Nothing else. I did not touch the section's deliverable (`driver.zsh`, `telemetry.py`, the fixture), its brief, or its acceptance.

The `CODEX_HOME` relocation itself was already in the working tree from attempt 1 (which ran out of usage limit before it could report). It is still uncommitted — see below.

# Evidence

The obstruction, reproduced in both halves.

`CODEX_HOME` unwritable — the exact failure the reviews recorded:

```text
$ CODEX_HOME=/tmp/cu-home/ro codex exec --json --ephemeral --sandbox read-only 'say hi'
RO_EXIT=1
Error: failed to initialize in-process app-server client: Permission denied (os error 13)
```

`CODEX_HOME` relocated to a writable dir seeded with `auth.json`/`config.toml` — same command, passing:

```text
$ CODEX_HOME=/tmp/cu-home/rw codex exec --json --ephemeral --sandbox read-only 'reply with the single word: ok'
RW_EXIT=0
{"type": "item.completed", "item": {"type": "agent_message", "text": "ok"}}
{"type": "turn.completed", "usage": {"input_tokens": 13738, "cached_input_tokens": 9984, "output_tokens": 5, "reasoning_output_tokens": 0}}
```

End to end through the live harness, a real codex dispatch with the relocated home and the atomic copy-back in place:

```text
$ env -i HOME=$HOME PATH=$PATH TMPDIR=$TMPDIR .agentic/pm_flow/agent_exec.sh pm \
    --prompt-file /tmp/cu-probe/p.md --output /tmp/cu-probe/resp.json --work-root /tmp/cu-probe
role=pm
cli=codex
response=/tmp/cu-probe/resp.json
attempts=1
AGENT_EXEC_EXIT=0
{"type": "turn.completed", "usage": {"input_tokens": 14085, "cached_input_tokens": 9984, "output_tokens": 5, "reasoning_output_tokens": 0}}
{'model': 'gpt-5.6-sol', 'is_error': False, 'failure_reason': 'none'}
result: 'ok'
```

`$HOME/.codex/auth.json` intact afterwards, no staged file left behind (`stray staged files: 0`).

The second boundary, reproduced directly — a child command of a codex `workspace-write` role has no network:

```text
$ codex exec --sandbox workspace-write ... 'run: curl -sS -o /dev/null -w "%{http_code}" https://api.openai.com/v1/models'
curl: (6) Could not resolve host: api.openai.com
000 exit=6
```

Full suite, unchanged and green:

```text
PASS: codex token accounting against a real event stream
PASS: per-dispatch access observation
PASS: dependency scheduling and blocked sections
PASS: headless driver, escalation, and parallel rescue
PASS: per-section git worktrees, merge-back, and cleanup
PASS: concurrent section runs, serialised merges, and lock exclusion
PASS: product decomposition and a full headless project run
PASS: section-scoped PM flow
PASS: role personas, agent dispatch, and supervision
PASS: independent consultant panel and CPO adjudication
SUITE_EXIT=0
```

The section's own failing command — the cycle-004/005 real-dispatch probe run *as the reviewer* — I did not make pass, and cannot without crossing the boundary above.

# What I did not fix

- **The `CODEX_HOME` relocation is uncommitted.** It sits in the main working tree as a modification to `template/.agentic/pm_flow/agent_exec.sh` (attempt 1's work plus my atomic-rename hardening). Committing engine changes is not a maintenance-engineer act here and nothing I ran needed it, but an uncommitted engine fix does not survive the next fresh process — someone must land it.
- **The live install is stale against `main`.** `.agentic/pm_flow/telemetry.py` still carries the `attempts.agent_definition_id` INSERT that `store.py` has no column for — the cycle-004 obstruction — even though `template/` on `main` no longer does, and the installed `agent_exec.sh` predates the `FLOW_DIR` refactor. Every dispatch of *this* flow runs the stale copy. I did not upgrade it: regenerating the install is `packaging`'s ground, and doing it mid-run would swap the engine under sections that are live.
- **The codex backend cannot express the `scoped` tier at all.** `agent_exec.sh` already says so in a comment: `--extra-dir` and the write boundary are prompt-level only on codex. Network is the one part of the tier codex *does* enforce, which is why the asymmetry surfaced here and not earlier. Nothing enforces the "may not dispatch the flow" rule on a codex role except the absence of network.
- The cycle-002 blocker (git object/ref writes denied to the reviewer) I did not revisit; cycle 005 got past it, so it appears environmental rather than standing.

# Decision

NOT_PLUMBING — the harness fault I could repair (nested codex denied its own `CODEX_HOME`) is fixed and proven, but the remaining blocker is the `scoped` access tier working exactly as designed, and only a product decision can resolve it: either the reviewer verifies the developer's recorded real-dispatch artifacts and the real-stream fixture the brief already asks for, or the access model changes to give this review a bounded, allowlisted way to make one outbound dispatch.
