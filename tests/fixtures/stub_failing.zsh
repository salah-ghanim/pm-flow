#!/bin/zsh -f
# Test double for an agent CLI: a section that keeps failing, forcing the panel,
# an ADOPT_PARALLEL adjudication, and a rescue that does not hold.
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
    emit "## Where the section stands
Stuck.

## Assignment
Try again.

## Acceptance
Tests pass.

## Rejection conditions
Drift.

## Decision
ASSIGN - retry" ;;
  *"Task: implement this assignment"*)
    emit "## What I changed
Tried.

## What I reused or restructured
Nothing.

## Validation
No output.

## What I could not do
Make it work.

## Status
PARTIAL - incomplete" ;;
  *"Task: review a developer result"*)
    emit "## Assessment
No evidence.

## Drift review
None.

## Evidence check
Check never run.

## Risks
High.

## Decision
NO_GO - no evidence" ;;
  *"Task: adjudicate a consultant panel"*)
    emit "## Panel assessment
Wrong primitive.

## Points of agreement
Rebuild.

## Points of disagreement
Which one.

## Selected paths
1. Rebuild on primitive A
2. Rebuild on primitive B

## Rationale
Both decisive.

## Decision
ADOPT_PARALLEL - run both" ;;
  *"Task: rescue this section"*)
    emit "## What I built
Rescue.

## Why this works where the previous attempt did not
New primitive.

## What I reused or restructured
Harness.

## Validation
Passed.

## Residual risk
Low.

## Status
DELIVERED" ;;
  *) emit "## Diagnosis
Wrong primitive.

## Prior art considered
Standard exists.

## Alternatives
A or B.

## What would prove each one
Acceptance test.

## Decision
ALTERNATIVE - switch" ;;
esac
