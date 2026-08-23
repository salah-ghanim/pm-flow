#!/bin/zsh -f
# Test double for an agent CLI: a section that succeeds on the first cycle.
prompt="${@[-1]}"
emit() { python3 -c 'import json,sys; print(json.dumps({"is_error":False,"result":sys.argv[1],"session_id":""}))' "$1"; }

# The driver reviews the whole portfolio on a dispatch cadence, so any stub that
# survives more than a dozen dispatches has to answer one. A review whose
# verdicts cannot be read is re-asked until the step-claim ceiling gives up, and
# because project work preempts section work, every tick in between is spent on
# the review rather than on the section the test is watching.
emit_portfolio_review() {
  local verdicts="" section_dir key lifecycle sections_glob
  local project_key
  project_key="$(head -n 1 "$PROJECT_ROOT/.agentic/pm_flow/.project-key" 2>/dev/null)"
  for section_dir in "$PROJECT_ROOT"/.agentic/pm_flow/${project_key:-*}/sections/*(/N); do
    key="${section_dir:t}"
    [[ "$key" != .* ]] || continue
    lifecycle="$(head -n 1 "$section_dir/status.txt" 2>/dev/null)"
    case "$lifecycle" in done|cancelled) continue ;; esac
    verdicts+="- $key: CONTINUE still on the shortest path"$'\n'
  done
  emit "## Standing
Every live section is doing the work its brief asked for.

## Verdicts
${verdicts}
## Plan structure
- unstarted dependency: CLEAR
- unreachable section: CLEAR
- must-have inflation: CLEAR
- linear-chain risk: CLEAR

## Shortest path
Finish the sections already in flight; nothing else is on the critical path.

## Decision
ON_TRACK - the plan and the work still agree"
}
case "$prompt" in
  *"Task: review the portfolio"*)
    emit_portfolio_review ;;
  *"Task: scope the next assignment"*)
    if [[ -f "$PM_DONE_FLAG" ]]; then
      emit "## Where the section stands
Done.

## Assignment
Not applicable.

## Acceptance
Not applicable.

## Rejection conditions
Not applicable.

## Decision
COMPLETE - acceptance met"
    else
      touch "$PM_DONE_FLAG"
      emit "## Where the section stands
Starting.

## Workplan task
T1

## Assignment
Build it.

## Acceptance
Tests pass.

## Rejection conditions
Drift.

## Decision
ASSIGN - first piece"
    fi ;;
  *"Task: implement this assignment"*)
    emit "## What I changed
Built it.

## What I reused or restructured
Harness.

## Validation
12 passed

## What I could not do
Nothing.

## Status
DELIVERED" ;;
  *"Task: review a developer result"*)
    emit "## Assessment
Good.

## Drift review
None.

## Evidence check
Output present.

## Risks
Low.

## Decision
GO - accepted" ;;
  *"Task: write the section handoff"*)
    emit "## Outcome
Widget works.

## Decisions
Reused harness.

## Interfaces
Widget API.

## Risks
None.

## What is unproven
None; every claim above was demonstrated.

## Next action
Integrate." ;;
  *) emit "## Decision
ASSIGN - fallback" ;;
esac
