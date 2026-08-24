#!/bin/zsh -f
# Test double for a developer dispatch that must outlive its launching session.
prompt="${@[-1]}"
emit() { python3 -c 'import json,sys; print(json.dumps({"is_error":False,"result":sys.argv[1],"session_id":""}))' "$1"; }

retire_workplan_scaffold() {
  local wp
  wp="$(printf '%s\n' "$prompt" | sed -n 's/^- *`\{0,1\}\([^`]*workplan\.md\)`\{0,1\} *$/\1/p' | head -n 1)"
  [[ -n "$wp" ]] || return 0
  [[ "$wp" == /* ]] || wp="${PROJECT_ROOT:-$PWD}/$wp"
  [[ -f "$wp" ]] || return 0
  grep -v 'pm-flow-workplan-template' "$wp" > "$wp.tmp" && mv "$wp.tmp" "$wp"
}

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
    retire_workplan_scaffold
    emit "## Where the section stands
Starting.

## Workplan task
T1

## Assignment
Build the detached fixture.

## Acceptance
The developer result is recorded.

## Rejection conditions
The dispatch is interrupted.

## Decision
ASSIGN - detached dispatch" ;;
  *"Task: implement this assignment"*)
    if [[ -n "${PM_DETACH_MARKER:-}" && ! -f "$PM_DETACH_MARKER" ]]; then
      printf 'started\n' > "$PM_DETACH_MARKER"
      sleep 15
      printf 'woke\n' > "$PM_DETACH_MARKER.woke"
    fi
    emit "## What I changed
Built it.

## What I reused or restructured
The existing harness.

## Validation
The detached dispatch woke normally.

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
The detached dispatch completed.

## Decisions
Reused the harness.

## Interfaces
None.

## Risks
None.

## What is unproven
Nothing.

## Next action
Integrate." ;;
  *"Task: decompose the product"*)
    emit "## Section: detached-work

### Objective
- Prove detached work completes.

### Scope
- In: the detached fixture. Out: unrelated commands.

### Priority
- must-have. The fixture has no purpose without this proof.

### Owned paths
- src/detached/**

### Dependencies
- None.

### Acceptance
- The detached result is recorded.

### Rejection conditions
- The dispatch is interrupted." ;;
  *) emit "## Decision
ASSIGN - fallback" ;;
esac
