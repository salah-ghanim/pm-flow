#!/bin/zsh -f
# Test double for an agent CLI: a section that keeps failing, forcing the panel,
# an ADOPT_PARALLEL adjudication, and a rescue that does not hold.
prompt="${@[-1]}"
emit() { python3 -c 'import json,sys; print(json.dumps({"is_error":False,"result":sys.argv[1],"session_id":""}))' "$1"; }
case "$prompt" in
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
