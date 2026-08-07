#!/bin/zsh -f
# Part two: the recovery paths and the decomposition, all stubbed.
set -uo pipefail

TEMPLATE="$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)"
W="${1:?work dir required}"
rm -rf "$W"; mkdir -p "$W/src"
cd "$W"
git init -q .; git config user.email t@t; git config user.name t

mkdir -p "$W/agentic"
cp -R "$TEMPLATE" "$W/agentic/pm_flow"
FLOW="$W/agentic/pm_flow"
rm -rf "$FLOW/project"
mkdir -p "$FLOW/demo/project_state" "$FLOW/demo/sections" "$FLOW/demo/runs"
printf 'demo\n' > "$FLOW/.project-key"
printf '{"domain":"generic"}\n' > "$FLOW/demo/project.json"
printf '# Demo Task Contract\n\nrules\n' > "$FLOW/demo/task_contract.md"
printf '# Plan\n\nbuild the thing\n' > "$FLOW/demo/project_state/plan.md"
mkdir -p lib docs tools pkg1 pkg2
for d in lib docs tools pkg1 pkg2; do printf 'x\n' > "$d/a.py"; done
printf 'print("hi")\n' > src/main.py

set_config() {
  python3 -c '
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
c = json.loads(p.read_text().replace(chr(34) + "{{DOMAIN}}" + chr(34), chr(34) + "generic" + chr(34)))
section, key = sys.argv[2].split(".")
c.setdefault(section, {})[key] = int(sys.argv[3])
p.write_text(json.dumps(c, indent=2))
' "$FLOW/config.json" "$1" "$2"
}
set_config escalation.failures_before_consultant 2
set_config escalation.cycles_before_convergence_review 0
set_config escalation.scope_history_cycles 2

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
[[ -z "${STUB_DIRTY:-}" ]] || printf 'developer left this behind\n' >> "$STUB_DIRTY"
if [[ "${STUB_EXIT:-0}" != "0" ]]; then
  printf 'stub: simulated fatal dispatch failure\n' >&2
  python3 -c '
import json, sys
from pathlib import Path
Path(sys.argv[1]).parent.mkdir(parents=True, exist_ok=True)
Path(sys.argv[1]).write_text(json.dumps({"is_error": True, "result": "",
    "failure_reason": "permanent", "total_cost_usd": 0.25}))
' "$OUT"
  exit 3
fi
python3 -c '
import json, sys
from pathlib import Path
Path(sys.argv[1]).parent.mkdir(parents=True, exist_ok=True)
Path(sys.argv[1]).write_text(json.dumps({"is_error": False, "result": sys.argv[2],
    "failure_reason": "none", "total_cost_usd": 0.5}))
' "$OUT" "${PM_FLOW_STUB:-}"
STUB
chmod +x "$FLOW/agent_exec.sh"
FLOWSH="$FLOW/pm_flow.sh"; chmod +x "$FLOWSH"

pass=0; failn=0
ok()   { printf 'PASS  %s\n' "$1"; (( pass += 1 )); return 0 }
bad()  { printf 'FAIL  %s\n        got: %s\n' "$1" "$2"; (( failn += 1 )); return 0 }
eq()   { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1" "$2 != $3"; fi }
has()  { if [[ "$2" == *"$3"* ]]; then ok "$1"; else bad "$1" "$2"; fi }
absent(){ if [[ "$2" != *"$3"* ]]; then ok "$1"; else bad "$1" "$2"; fi }
exists(){ if [[ -f "$2" ]]; then ok "$1"; else bad "$1" "missing $2"; fi }
next_action_for() { "$FLOWSH" next 2>/dev/null | awk -v k="$1" '$2 == k {print $3; exit}' }

brief() {
  printf '## Objective\n\n- %s\n\n## Scope\n\n- one thing\n\n## Priority\n\n- must-have: the product cannot ship without it\n\n## Owned paths\n\n- `%s`\n\n## Dependencies\n\n- None.\n\n## Acceptance\n\n- `.venv/bin/python -m pytest -q` exits 0\n\n## Rejection conditions\n\n- nothing runs\n' "$1" "$2"
}

SCOPE_OK='## Assignment

Write it.

## Acceptance

- `.venv/bin/python -m pytest -q` exits 0

## Rejection conditions

- nothing runs

## Decision

ASSIGN'
DEV_OK='## What I changed

x

## Status

DELIVERED'

printf '\n===== F18/F21: decomposition validates before creating, and matches briefs exactly =====\n'
PM_FLOW_STUB='## Section: client

## Objective

- the bare client

## Scope

- one

## Priority

- must-have: no client, no product

## Owned paths

- `pkg1/`

## Dependencies

- None.

## Acceptance

- `.venv/bin/python -m pytest -q` exits 0

## Rejection conditions

- nothing runs

## Section: ib-client

## Objective

- the ib client

## Scope

- one

## Priority

- nice-to-have: the product still works on one venue without it

## Owned paths

- `pkg2/`

## Dependencies

- None.

## Acceptance

- `.venv/bin/python -m pytest -q` exits 0

## Rejection conditions

- nothing runs' "$FLOWSH" tick > "$W/decompose.out" 2>&1 || true
cat "$W/decompose.out"
has "F21 both sections were created despite the name being a suffix of the other" \
    "$(cat "$W/decompose.out")" "2 section(s)"
has "F21 client got the brief written for client" \
    "$(cat "$FLOW/demo/sections/client/brief.md" 2>/dev/null)" "the bare client"
has "F21 ib-client got the brief written for ib-client" \
    "$(cat "$FLOW/demo/sections/ib-client/brief.md" 2>/dev/null)" "the ib client"

printf '\n===== F18: a decomposition with one bad brief creates nothing =====\n'
rm -rf "$FLOW/demo/sections" "$FLOW/demo/project_state/decomposition"
mkdir -p "$FLOW/demo/sections"
out="$(PM_FLOW_STUB='## Section: good

## Objective

- ok

## Scope

- one

## Priority

- must-have: nothing ships without it

## Owned paths

- `pkg1/`

## Dependencies

- None.

## Acceptance

- x

## Rejection conditions

- y

## Section: bad

## Objective

- no owned paths bullet

## Scope

- one

## Priority

- must-have: nothing ships without it

## Owned paths

## Dependencies

- None.

## Acceptance

- x

## Rejection conditions

- y' "$FLOWSH" tick 2>&1 || true)"
has "F18 the decomposition is refused as a whole" "$out" "nothing was created"
eq  "F18 no section was created" "$(/bin/ls "$FLOW/demo/sections" | wc -l | tr -d ' ')" "0"

printf '\n===== setup for the recovery paths =====\n'
rm -rf "$FLOW/demo/project_state/decomposition"
brief alpha "lib/"  > "$W/b.md"; "$FLOWSH" init-section alpha --file "$W/b.md" >/dev/null
brief beta  "docs/" > "$W/b.md"; "$FLOWSH" init-section beta  --file "$W/b.md" >/dev/null
brief gamma "tools/" > "$W/b.md"; "$FLOWSH" init-section gamma --file "$W/b.md" >/dev/null
git add -A >/dev/null 2>&1; git commit -qm sections

printf '\n===== F16: an assignment that owns the dispatch output returns to its manager =====\n'
PM_FLOW_STUB='## Assignment

Do the thing. You may write `result.md` with your findings.

## Acceptance

- x

## Rejection conditions

- y

## Decision

ASSIGN' PM_FLOW_SECTION=alpha "$FLOWSH" tick >/dev/null
eq "F16 the cycle wants develop next" "$(next_action_for alpha)" "develop"
PM_FLOW_SECTION=alpha "$FLOWSH" tick > "$W/f16.out" 2>&1 || true
has    "F16 the tick reports the rejection instead of failing the run" \
       "$(cat "$W/f16.out")" "returning the cycle to scope"
exists "F16 a rescope reason is written" "$FLOW/demo/sections/alpha/cycles/001/rescope_reason.txt"
exists "F16 the rejected assignment is kept" "$FLOW/demo/sections/alpha/cycles/001/assignment.rejected.md"
eq     "F16 the section goes back to scope" "$(next_action_for alpha)" "scope"
absent "F16 the section is not quarantined" "$("$FLOWSH" status)" "quarantined"
PM_FLOW_STUB="$SCOPE_OK" PM_FLOW_SECTION=alpha "$FLOWSH" tick >/dev/null
eq     "F16 the re-ask reuses the same cycle rather than burning a new one" \
       "$(/bin/ls "$FLOW/demo/sections/alpha/cycles" | tr '\n' ' ' | tr -d ' ')" "001"
has    "F16 the rescope reason reached the new scope prompt" \
       "$(cat "$FLOW/demo/sections/alpha/cycles/001/scope_prompt.md")" "rescope_reason.txt"

printf '\n===== F15: a failed dispatch names what it left uncommitted =====\n'
STUB_EXIT=1 STUB_DIRTY="$W/docs/leftover.txt" PM_FLOW_SECTION=beta "$FLOWSH" tick >/dev/null 2>&1 || true
exists "F15 orphaned_worktree.txt is written" "$FLOW/demo/sections/beta/orphaned_worktree.txt"
has    "F15 it names the file the dispatch left behind" \
       "$(cat "$FLOW/demo/sections/beta/orphaned_worktree.txt" 2>/dev/null)" "docs/leftover.txt"
rm -f "$W/docs/leftover.txt" "$FLOW/demo/sections/beta/quarantine.txt"

printf '\n===== F12: the scope context is windowed, not cumulative =====\n'
for cycle in 1 2 3 4; do
  PM_FLOW_STUB="$SCOPE_OK" PM_FLOW_SECTION=gamma "$FLOWSH" tick >/dev/null
  PM_FLOW_STUB="$DEV_OK"   PM_FLOW_SECTION=gamma "$FLOWSH" tick >/dev/null
  PM_FLOW_STUB='## Decision

GO_WITH_CHANGES' PM_FLOW_SECTION=gamma "$FLOWSH" tick >/dev/null
done
PM_FLOW_STUB="$SCOPE_OK" PM_FLOW_SECTION=gamma "$FLOWSH" tick >/dev/null
prompt="$FLOW/demo/sections/gamma/cycles/005/scope_prompt.md"
cited="$(grep -c 'cycles/00[0-9]/result.md' "$prompt" || true)"
eq     "F12 only the last two cycles are cited (window of 2)" "$cited" "2"
has    "F12 the newest cycle is included"  "$(cat "$prompt")" "cycles/004/result.md"
absent "F12 cycle 001 is no longer carried" "$(cat "$prompt")" "cycles/001/result.md"
has    "F12 state.md is still in the context" "$(cat "$prompt")" "state.md"

printf '\n===== F17: a handoff over budget gets feedback, then gives up cleanly =====\n'
LONG="$(python3 -c "print('## Outcome\n\n' + ('word ' * 600) + '\n\n## Decisions\n\n- x\n\n## Interfaces\n\n- x\n\n## Risks\n\n- x\n\n## What is unproven\n\n- x\n\n## Next action\n\n- x')")"
PM_FLOW_STUB='## Decision

COMPLETE' PM_FLOW_SECTION=beta "$FLOWSH" tick >/dev/null
eq "F17 the section wants to complete" "$(next_action_for beta)" "complete"
PM_FLOW_STUB="$LONG" PM_FLOW_SECTION=beta "$FLOWSH" tick > "$W/f17.out" 2>&1 || true
exists "F17 the overrun is written down" "$FLOW/demo/sections/beta/cycles/001/handoff_feedback.md"
has    "F17 the feedback names the actual word count" \
       "$(cat "$FLOW/demo/sections/beta/cycles/001/handoff_feedback.md")" "the cap is 500"
has    "F17 the second prompt carries the feedback" \
       "$(cat "$FLOW/demo/sections/beta/cycles/001/handoff_prompt.md")" "previous handoff was rejected"
has    "F17 two attempts and then a clean stop" "$(cat "$W/f17.out")" "missed its budget twice"
rm -f "$FLOW/demo/sections/beta/quarantine.txt"

printf '\n===== F8: a rescue that holds breaks the failure streak for good =====\n'
NO_GO='## Assessment

no

## Decision

NO_GO'
for round in 1 2; do
  PM_FLOW_STUB="$SCOPE_OK" PM_FLOW_SECTION=alpha "$FLOWSH" tick >/dev/null
  PM_FLOW_STUB="$DEV_OK"   PM_FLOW_SECTION=alpha "$FLOWSH" tick >/dev/null
  PM_FLOW_STUB="$NO_GO"    PM_FLOW_SECTION=alpha "$FLOWSH" tick >/dev/null
done
eq "F8 two rejections reach the escalation threshold" "$(next_action_for alpha)" "escalate"
PM_FLOW_STUB='## Diagnosis

x

## Decision

ALTERNATIVE try another way' PM_FLOW_SECTION=alpha "$FLOWSH" tick >/dev/null
eq "F8 the panel hands over to adjudication" "$(next_action_for alpha)" "adjudicate"
PM_FLOW_STUB='## Selected paths

- rewrite the parser

## Decision

ADOPT' PM_FLOW_SECTION=alpha "$FLOWSH" tick >/dev/null
eq "F8 the adjudication routes to a rescue" "$(next_action_for alpha)" "rescue"
PM_FLOW_STUB='## What I changed

rewrote it

## Status

DELIVERED' PM_FLOW_SECTION=alpha "$FLOWSH" tick >/dev/null
eq "F8 the rescue is reviewed" "$(next_action_for alpha)" "review-rescue"
PM_FLOW_STUB='## Assessment

it holds

## Decision

GO' PM_FLOW_SECTION=alpha "$FLOWSH" tick >/dev/null
exists "F8 the streak floor is recorded" "$FLOW/demo/sections/alpha/failure_streak_reset.txt"
eq "F8 the section resumes normal cycles instead of escalating again" \
   "$(next_action_for alpha)" "scope"
eq "F8 and it still does not escalate on the tick after that" \
   "$(next_action_for alpha)" "scope"

printf '\ntotals: pass=%d fail=%d\n' "$pass" "$failn"
[[ "$failn" == 0 ]]
