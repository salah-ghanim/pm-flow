#!/bin/zsh -f
# Test double for an agent CLI: a section that succeeds on the first cycle.
prompt="${@[-1]}"
emit() { python3 -c 'import json,sys; print(json.dumps({"is_error":False,"result":sys.argv[1],"session_id":""}))' "$1"; }
case "$prompt" in
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

## Next action
Integrate." ;;
  *) emit "## Decision
ASSIGN - fallback" ;;
esac
