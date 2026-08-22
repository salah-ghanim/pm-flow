#!/bin/zsh -f
# Exercise the driver's transitions against a synthetic project with a stubbed
# dispatcher, so nothing is spent and every branch is reachable.
set -uo pipefail

TEMPLATE="$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)"
W="${1:?work dir required}"
rm -rf "$W"; mkdir -p "$W/src"
cd "$W"
git init -q .; git config user.email t@t; git config user.name t

mkdir -p "$W/agentic"
cp -R "$TEMPLATE" "$W/.agentic/pm_flow"
FLOW="$W/.agentic/pm_flow"
rm -rf "$FLOW/project"
mkdir -p "$FLOW/demo/project_state" "$FLOW/demo/sections" "$FLOW/demo/runs"
printf 'demo\n' > "$FLOW/.project-key"
printf '{"domain":"generic"}\n' > "$FLOW/demo/project.json"
printf '# Demo Task Contract\n\nrules\n' > "$FLOW/demo/task_contract.md"
printf '# Plan\n\nbuild the thing\n' > "$FLOW/demo/project_state/plan.md"
printf 'print("hi")\n' > src/main.py
mkdir -p lib docs tools pkg1 pkg2 pkg3
printf 'x\n' > lib/a.py; printf 'x\n' > docs/a.md; printf 'x\n' > tools/a.py
printf 'x\n' > pkg1/a.py; printf 'x\n' > pkg2/a.py; printf 'x\n' > pkg3/a.py

set_config() {
  python3 -c '
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
raw = p.read_text().replace(chr(34) + "{{DOMAIN}}" + chr(34), chr(34) + "generic" + chr(34))
c = json.loads(raw)
section, key = sys.argv[2].split(".")
value = sys.argv[3]
c.setdefault(section, {})[key] = float(value) if "." in value else int(value)
p.write_text(json.dumps(c, indent=2))
' "$FLOW/config.json" "$1" "$2"
}
set_config escalation.failures_before_consultant 2
set_config escalation.cycles_before_convergence_review 0

# Stub dispatcher: canned response from PM_FLOW_STUB, canned exit from STUB_EXIT.
cat > "$FLOW/agent_exec.sh" <<'STUB'
#!/bin/zsh -f
set -euo pipefail
OUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) OUT="$2"; shift 2 ;;
    --prompt-file|--heartbeat|--label|--seat) shift 2 ;;
    *) shift ;;
  esac
done
[[ "${STUB_SLEEP:-0}" == "0" ]] || sleep "$STUB_SLEEP"
if [[ "${STUB_EXIT:-0}" != "0" ]]; then
  printf 'stub: simulated fatal dispatch failure\n' >&2
  python3 -c '
import json, sys
from pathlib import Path
Path(sys.argv[1]).parent.mkdir(parents=True, exist_ok=True)
Path(sys.argv[1]).write_text(json.dumps(
    {"is_error": True, "result": "", "failure_reason": "permanent",
     "total_cost_usd": 0.25}))
' "$OUT"
  exit 3
fi
python3 -c '
import json, sys
from pathlib import Path
out, body = sys.argv[1], sys.argv[2]
Path(out).parent.mkdir(parents=True, exist_ok=True)
Path(out).write_text(json.dumps(
    {"is_error": False, "result": body, "failure_reason": "none",
     "total_cost_usd": 0.5}))
' "$OUT" "${PM_FLOW_STUB:-}"
STUB
chmod +x "$FLOW/agent_exec.sh"

FLOWSH="$FLOW/pm_flow.sh"
chmod +x "$FLOWSH"

pass=0; failn=0
ok()   { printf 'PASS  %s\n' "$1"; (( pass += 1 )); return 0 }
bad()  { printf 'FAIL  %s\n        got: %s\n' "$1" "$2"; (( failn += 1 )); return 0 }
eq()   { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1" "$2 != $3"; fi }
has()  { if [[ "$2" == *"$3"* ]]; then ok "$1"; else bad "$1" "$2"; fi }
absent() { if [[ "$2" != *"$3"* ]]; then ok "$1"; else bad "$1" "$2"; fi }

brief() {
  printf '## Objective\n\n- %s\n\n## Scope\n\n- one thing\n\n## Priority\n\n- must-have: the product cannot ship without it\n\n## Owned paths\n\n- `%s`\n\n## Dependencies\n\n%s\n\n## Acceptance\n\n- `.venv/bin/python -m pytest -q` exits 0\n\n## Rejection conditions\n\n- nothing runs\n' \
    "$1" "$2" "$3"
}

next_action_for() {
  "$FLOWSH" next 2>/dev/null | awk -v key="$1" '$2 == key {print $3; exit}'
}

printf '\n===== setup: seven sections, disjoint owned paths =====\n'
brief alpha   "lib/"   "- None." > "$W/b.md"; "$FLOWSH" init-section alpha   --file "$W/b.md" >/dev/null
brief gamma   "tools/" "- None." > "$W/b.md"; "$FLOWSH" init-section gamma   --file "$W/b.md" >/dev/null
brief beta    "src/"   "- alpha" > "$W/b.md"; "$FLOWSH" init-section beta    --file "$W/b.md" >/dev/null
brief delta   "docs/"  "- alpha" > "$W/b.md"; "$FLOWSH" init-section delta   --file "$W/b.md" >/dev/null
brief epsilon "pkg1/"  "- None." > "$W/b.md"; "$FLOWSH" init-section epsilon --file "$W/b.md" >/dev/null
brief zeta    "pkg2/"  "- None." > "$W/b.md"; "$FLOWSH" init-section zeta    --file "$W/b.md" >/dev/null
brief eta     "pkg3/"  "- None." > "$W/b.md"; "$FLOWSH" init-section eta     --file "$W/b.md" >/dev/null
git add -A >/dev/null; git commit -qm sections

printf '\n===== F3: the scheduler ranks by dependents, not lexically =====\n'
"$FLOWSH" next
eq "F3 alpha (2 dependents) outranks the lexically-first zero-dependent section" \
   "$("$FLOWSH" next | sed -n 1p | awk '{print $2}')" "alpha"

SCOPE_ASSIGN='## Where the section stands

Editorial that the developer must never see.

## Assignment

Write lib/a.py.

## Acceptance

- `.venv/bin/python -m pytest -q` exits 0

## Rejection conditions

- nothing runs

## Decision

ASSIGN start here'
DEV_PARTIAL='## What I changed

lib/a.py

## Validation

output

## Status

PARTIAL only two of three cases pass'

printf '\n===== F20: only Assignment/Acceptance/Rejection reach the developer =====\n'
PM_FLOW_STUB="$SCOPE_ASSIGN" PM_FLOW_SECTION=alpha "$FLOWSH" tick >/dev/null
assignment="$(cat "$FLOW/demo/sections/alpha/cycles/001/assignment.md")"
has    "F20 the Assignment section is kept" "$assignment" "Write lib/a.py."
absent "F20 the editorial is dropped"       "$assignment" "Editorial"

printf '\n===== F11: the lifecycle is stamped on every tick =====\n'
eq  "F11 status.txt advances past planned" "$(cat "$FLOW/demo/sections/alpha/status.txt")" "active"
has "F11 summary.txt is no longer the creation text" \
    "$(cat "$FLOW/demo/sections/alpha/summary.txt")" "last action"

printf '\n===== F7: the dispatch cost is recorded =====\n'
has "F7 the ledger has a priced row" "$(cat "$FLOW/demo/runs/cost_ledger.tsv")" "0.500000"
has "F7 status reports the total"    "$("$FLOWSH" status)" "total spent: \$0.5000"

printf '\n===== F2: the developer status is parsed =====\n'
PM_FLOW_STUB="$DEV_PARTIAL" PM_FLOW_SECTION=alpha "$FLOWSH" tick >/dev/null
eq "F2 dev_status.txt records PARTIAL" \
   "$(cat "$FLOW/demo/sections/alpha/cycles/001/dev_status.txt")" "PARTIAL"

printf '\n===== F5: an unreadable verdict becomes UNPARSED and is re-asked =====\n'
PM_FLOW_STUB='## Assessment

Looks fine to me.

## Decision

Probably fine, ship it' PM_FLOW_SECTION=alpha "$FLOWSH" tick >/dev/null
eq "F5 decision.txt records UNPARSED" \
   "$(cat "$FLOW/demo/sections/alpha/cycles/001/decision.txt")" "UNPARSED"
if [[ -f "$FLOW/demo/sections/alpha/cycles/001/verdict_feedback.md" ]]; then
  ok "F5 the parser complaint is fed back"; else bad "F5 the parser complaint is fed back" missing; fi
eq "F5 the section is re-asked, not advanced past" "$(next_action_for alpha)" "review"

printf '\n===== F5: duplicate Decision sections resolve to the last =====\n'
PM_FLOW_STUB='## Assessment

The output is pasted.

## Decision

## Decision

GO_WITH_CHANGES rename the fixture' PM_FLOW_SECTION=alpha "$FLOWSH" tick >/dev/null
eq "F5 the re-ask parses" "$(cat "$FLOW/demo/sections/alpha/cycles/001/decision.txt")" "GO_WITH_CHANGES"
if [[ ! -f "$FLOW/demo/sections/alpha/cycles/001/verdict_feedback.md" ]]; then
  ok "F5 the feedback file is cleared"; else bad "F5 the feedback file is cleared" "still present"; fi

printf '\n===== F5: UNPARSED counts as a failure for escalation =====\n'
PM_FLOW_STUB='## Decision

NO_GO' PM_FLOW_SECTION=eta "$FLOWSH" tick >/dev/null 2>&1 || true
PM_FLOW_STUB="$SCOPE_ASSIGN"  PM_FLOW_SECTION=eta "$FLOWSH" tick >/dev/null
PM_FLOW_STUB="$DEV_PARTIAL"   PM_FLOW_SECTION=eta "$FLOWSH" tick >/dev/null
PM_FLOW_STUB='## Decision

NO_GO it does not run' PM_FLOW_SECTION=eta "$FLOWSH" tick >/dev/null
eq "F5 one NO_GO alone does not escalate (threshold 2)" "$(next_action_for eta)" "scope"
PM_FLOW_STUB="$SCOPE_ASSIGN"  PM_FLOW_SECTION=eta "$FLOWSH" tick >/dev/null
PM_FLOW_STUB="$DEV_PARTIAL"   PM_FLOW_SECTION=eta "$FLOWSH" tick >/dev/null
PM_FLOW_STUB='## Assessment

no verdict here' PM_FLOW_SECTION=eta "$FLOWSH" tick >/dev/null
eq "F5 NO_GO then UNPARSED reaches the escalation threshold" "$(next_action_for eta)" "escalate"

printf '\n===== F6: accepted cycles with no COMPLETE force a convergence review =====\n'
for cycle in 2 3; do
  PM_FLOW_STUB="$SCOPE_ASSIGN" PM_FLOW_SECTION=alpha "$FLOWSH" tick >/dev/null
  PM_FLOW_STUB="$DEV_PARTIAL"  PM_FLOW_SECTION=alpha "$FLOWSH" tick >/dev/null
  PM_FLOW_STUB='## Assessment

fine

## Decision

GO_WITH_CHANGES' PM_FLOW_SECTION=alpha "$FLOWSH" tick >/dev/null
done
eq "F6 three accepted cycles do not trigger it while it is switched off" \
   "$(next_action_for alpha)" "scope"
set_config escalation.cycles_before_convergence_review 2
eq "F6 switching it on makes the next action a convergence review" \
   "$(next_action_for alpha)" "converge"
PM_FLOW_STUB='## What has actually closed

Nothing measurable.

## Decision

CONTINUE the criteria are still reachable' PM_FLOW_SECTION=alpha "$FLOWSH" tick >/dev/null
eq "F6 CONTINUE is recorded" "$(cat "$FLOW/demo/sections/alpha/convergence/"*/decision.txt)" "CONTINUE"
eq "F6 it does not re-fire on the next tick" "$(next_action_for alpha)" "scope"
set_config escalation.cycles_before_convergence_review 0

printf '\n===== F2: BLOCKED_EXTERNAL moves the section to blocked =====\n'
PM_FLOW_STUB='## Where the section stands

No credentials exist.

## Decision

BLOCKED_EXTERNAL the paper gateway has no credentials on this host; a human must install one' \
  PM_FLOW_SECTION=gamma "$FLOWSH" tick >/dev/null
eq  "F2 the lifecycle becomes blocked" "$(cat "$FLOW/demo/sections/gamma/status.txt")" "blocked"
has "F2 the summary names the dependency" \
    "$(cat "$FLOW/demo/sections/gamma/summary.txt")" "paper gateway"
eq  "F2 a blocked section is not actionable" \
    "$("$FLOWSH" status | awk '$1 == "gamma" {print $4}')" "idle"

printf '\n===== F2: a bare BLOCKED_EXTERNAL token is refused =====\n'
result="$(PM_FLOW_STUB='## Where the section stands

x

## Decision

BLOCKED_EXTERNAL' PM_FLOW_SECTION=epsilon "$FLOWSH" tick 2>&1 || true)"
has "F2 a token with no named dependency is UNPARSED" "$result" "UNPARSED"
eq  "F2 the section is not blocked by it" "$(cat "$FLOW/demo/sections/epsilon/status.txt")" "active"

printf '\n===== F4: a fatal dispatch quarantines one section, not the run =====\n'
STUB_EXIT=1 PM_FLOW_STUB=x PM_FLOW_SECTION=zeta "$FLOWSH" tick >/dev/null 2>&1 || true
if [[ -f "$FLOW/demo/sections/zeta/quarantine.txt" ]]; then
  ok "F4 quarantine.txt is written"; else bad "F4 quarantine.txt is written" missing; fi
eq     "F4 status surfaces the quarantine" \
       "$("$FLOWSH" status | awk '$1 == "zeta" {print $4}')" "quarantined"
absent "F4 a quarantined section leaves the queue" "$("$FLOWSH" next)" "zeta"
has    "F4 the healthy sections stay in the queue" "$("$FLOWSH" next)" "alpha"
has    "F7 a failed dispatch still records its cost" \
       "$(cat "$FLOW/demo/runs/cost_ledger.tsv")" "0.250000"

printf '\n===== F19: two drivers cannot run at once =====\n'
STUB_SLEEP=4 PM_FLOW_STUB="$SCOPE_ASSIGN" PM_FLOW_SECTION=alpha "$FLOWSH" tick >/dev/null 2>&1 &
holder=$!
sleep 1
second="$(PM_FLOW_STUB="$SCOPE_ASSIGN" PM_FLOW_SECTION=alpha "$FLOWSH" tick 2>&1 || true)"
wait "$holder" 2>/dev/null || true
has "F19 the second driver is refused" "$second" "already running"

printf '\n===== F13: a cancelled dependency is reported as a deadlock =====\n'
printf 'cancelled\n' > "$FLOW/demo/sections/alpha/status.txt"
has "F13 status names the deadlock" "$("$FLOWSH" status 2>&1)" \
    "beta waits on alpha, which is cancelled"
run_out="$("$FLOWSH" run --max-ticks 0 2>&1 || true)"
run_code=0; "$FLOWSH" run --max-ticks 0 >/dev/null 2>&1 || run_code=$?
has "F13 run reports the deadlock"        "$run_out" "deadlocked"
eq  "F13 run exits non-zero on a deadlock" "$run_code" "1"
printf 'active\n' > "$FLOW/demo/sections/alpha/status.txt"

printf '\n===== F7: the budget stops the run before it dispatches =====\n'
set_config budget.max_usd 0.01
has "F7 the run refuses to spend past budget.max_usd" \
    "$(PM_FLOW_STUB="$SCOPE_ASSIGN" PM_FLOW_SECTION=alpha "$FLOWSH" tick 2>&1 || true)" \
    "budget exhausted"
set_config budget.max_usd 0

printf '\n===== F14: the step-claim ceiling is configurable and quarantines =====\n'
set_config supervision.max_step_claims 1
rm -rf "$FLOW/demo/sections/epsilon/cycles"
STUB_EXIT=1 PM_FLOW_SECTION=epsilon "$FLOWSH" tick >/dev/null 2>&1 || true
rm -f "$FLOW/demo/sections/epsilon/quarantine.txt"
STUB_EXIT=1 PM_FLOW_SECTION=epsilon "$FLOWSH" tick >/dev/null 2>&1 || true
has "F14 the configured ceiling is enforced and routed to quarantine" \
    "$(cat "$FLOW/demo/sections/epsilon/quarantine.txt" 2>/dev/null)" "ceiling 1"

printf '\ntotals: pass=%d fail=%d\n' "$pass" "$failn"
[[ "$failn" == 0 ]]
