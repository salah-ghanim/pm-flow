### Objective
- Every section is visible as a GitHub issue — created with its objective, commented on each accepted cycle, closed on completion — via an idempotent sync command for which the files are the truth and the tracker only a view.

### Current baseline
- No ticket or `gh` code exists anywhere in `template/`, `src/`, or `tests/` (grep-verified). The plan bullet is unserved. `boundary-schema` (planned) will provide `template/.agentic/pm_flow/schemas/**` and a `pm-flow export --json`-style verb; its brief names this section as the consumer. `init-section` is at `template/.agentic/pm_flow/pm_flow.sh:1667`; `fetch.sh` documents the credential-isolation pattern to follow.

### Deliverables
- `template/.agentic/pm_flow/ticket_sync.py` (with `ticket_sync.zsh` as an optional wrapper): a sync engine that, per section, creates or updates one GitHub issue (title from key and objective, body from the validated export's acceptance state and latest handoff), posts one comment per accepted cycle not yet posted, closes on `done`, labels or reopens on `cancelled`/reopen.
- Idempotency state (issue number, posted-cycle markers) stored in the section's own workspace, so re-runs never duplicate issues or comments.
- A `pm-flow` sync verb wired into `pm_flow.sh`'s dispatch, and an `init-section` flag accepting a GitHub issue URL or number that feeds the issue's title/body into the existing officer-mediated proposal path — both landing after `boundary-schema` releases `pm_flow.sh`.
- Graceful degradation: `gh` absent or unauthenticated means a clear message, exit 0, and no changes.
- `tests/ticket_exhaust_test.sh` with a stubbed `gh` and fixtures under `tests/fixtures/ticket_exhaust/**`.

### User-visible scenarios
1. In a flow project with live sections and `gh` authenticated against a scratch repository, run the sync verb: one issue per section appears on GitHub, titled with the section key and objective, body showing acceptance state and latest handoff.
2. Re-run the same command immediately: exit 0, and the scratch repository shows no new issues and no new comments.
3. After a cycle is accepted, run sync: the section's issue gains exactly one comment for that cycle. Mark a section `done` and sync: its issue closes. A `cancelled` section's issue is labelled or reopened accordingly.
4. Remove `gh` from PATH and run sync: a message names the missing prerequisite, exit is 0, nothing changed, and a driver tick is not blocked.
5. Run `pm-flow init-section <name> --from-issue <url-or-number>`: a proposal request built from the issue's title and body enters the officer-mediated path; the officer writes the brief, not the issue.
6. Run `zsh tests/ticket_exhaust_test.sh`: exits 0 on `main`.

### Interfaces produced
- The sync verb and its CLI contract (exit codes, no-op message) — the driver's future hook point.
- The per-section ticket-state file shape in the section workspace, the pattern later tracker adapters reuse.
- The stubbed-`gh` test harness under `tests/fixtures/ticket_exhaust/**`.

### Interfaces consumed
- `boundary-schema`'s validated JSON export verb and `template/.agentic/pm_flow/schemas/**`.
- The `gh` CLI as found on PATH, and the operator's existing `gh` authentication.
- Section workspace directories for idempotency state.

### Scope
- In: the GitHub adapter, its idempotency state, the sync verb and `--from-issue` intake wiring in `pm_flow.sh` (post-dependency), degradation behavior, the test suite.
- Out: any edit to `driver.zsh` or `install.sh`; other trackers; two-way sync; webhooks; any change to what the export emits.

### Non-goals
- Jira, Plane, Linear, or Asana adapters — later sections against the same export.
- Two-way state sync or making the tracker authoritative (the CCPM failure the owner named).
- Any webhook listener or polling daemon.
- The one-line driver hook itself — a hand-over once `outcome-record` frees `driver.zsh`.

### Priority
- must-have: the plan's completion criterion "a section is visible in an external ticket tracker, GitHub Issues first … the tracker is a view; the files stay the truth" cannot be met by anything else on `main` or in a live section.

### Owned paths
- template/.agentic/pm_flow/ticket_sync.py
- template/.agentic/pm_flow/ticket_sync.zsh
- tests/ticket_exhaust_test.sh
- tests/fixtures/ticket_exhaust/**

### Dependencies
- boundary-schema

### Constraints and fixed decisions
- Files remain the truth; nothing read from GitHub may alter flow state except the inbound proposal intake, which still terminates at the officer (owner decision).
- Sync consumes the validated JSON export, never the project markdown; if the export lacks per-cycle decision records needed for comment-per-cycle, request the field through the officer rather than parsing markdown.
- `pm_flow.sh` belongs to `boundary-schema` until it closes; the dispatch arm and `--from-issue` flag land only after that (the dependency guarantees the ordering).
- `driver.zsh` belongs to `outcome-record`: do not edit it. Acceptance must pass with operator-run sync alone, so sync replays unsynced accepted cycles rather than assuming it runs on every tick.
- `install.sh` belongs to `real-install`: hand the new engine filenames over for registration; acceptance is checked against the checkout, not an installed layout.
- Credentials and `gh` invocations never enter role prompts; sync is reachable only from operator or driver command paths, in the spirit of `fetch.sh`'s isolation (owner decision).
- A missing or unauthenticated `gh` must never block a tick: message, exit 0, no changes (owner decision).
- Issue numbers live in the section's own workspace, not in a central file (owner decision).

### Acceptance
- A1: sync against a scratch GitHub repository creates one issue per section with the key-and-objective title and export-derived body — checked by running scenario 1 and reading the issues in the GitHub UI.
- A2: an immediate re-run creates nothing — checked by scenario 2 in the live repository and by the stub suite asserting zero create calls on a second run.
- A3: lifecycle tracking holds: one comment per accepted cycle, close on `done`, label/reopen on `cancelled` — checked by scenario 3 against the scratch repository.
- A4: with `gh` absent or unauthenticated, sync prints why, exits 0, and a subsequent driver tick completes — checked by scenario 4.
- A5: `init-section --from-issue` produces an officer-mediated proposal whose request carries the issue's title and body, and no brief is written by the intake itself — checked by scenario 5 and the resulting proposal files.
- A6: `zsh tests/ticket_exhaust_test.sh` exits 0 on `main`, and no file under `template/.agentic/pm_flow/roles/` changes — checked by the suite and `git diff --stat`.

### Rejection conditions
- The tracker becomes a state store: any flow decision depends on reading GitHub, or sync mutates project state beyond its own idempotency file.
- Sync parses project markdown anywhere, even as a fallback.
- A failed, slow, or rate-limited `gh` call fails or blocks a tick.
- Idempotency proven only against the stub while a live re-run duplicates issues or comments.
- Credentials, tokens, or `gh` calls appear in any role prompt or dispatch payload.

### Open questions
- The request says nice-to-have, but the plan's completion criteria promise the tracker view, which forces must-have. Keep must-have, or issue a dated decision weakening that plan bullet?
- Label-versus-reopen on `cancelled` is left to the manager unless the owner has a preference.
