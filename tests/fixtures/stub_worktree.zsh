#!/bin/zsh -f
# Test double for an agent CLI, for the worktree isolation tests.
#
# The developer writes a file into whatever directory it was launched in and
# records that directory, so a test can prove where the dispatch actually ran
# rather than trusting the driver's own report of it. Everything else is the
# smallest answer that keeps a cycle moving.
#
# PM_STUB_STATE  a directory outside the repository for counters and the log
# PM_STUB_REVIEW GO (default) or NO_GO, to exercise the rejected path
prompt="${@[-1]}"
emit() { python3 -c 'import json,sys; print(json.dumps({"is_error":False,"result":sys.argv[1],"session_id":""}))' "$1"; }

state_dir="${PM_STUB_STATE:-${TMPDIR:-/tmp}}"
mkdir -p "$state_dir"

# The section this dispatch belongs to, read off the context paths in the
# prompt. Every role prompt names at least one file under sections/<key>/.
section_key="$(printf '%s' "$prompt" | sed -n 's|.*/sections/\([a-z0-9][a-z0-9_-]*\)/.*|\1|p' | head -n 1)"
[[ -n "$section_key" ]] || section_key=unknown

bump() {
  local counter="$state_dir/$1.count"
  local value
  value="$(head -n 1 "$counter" 2>/dev/null || printf '0\n')"
  [[ "$value" == <-> ]] || value=0
  (( value += 1 ))
  printf '%d\n' "$value" > "$counter"
  printf '%d\n' "$value"
}

emit_portfolio_review() {
  local verdicts="" section_dir key lifecycle project_key
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
    if [[ "$(bump "scope-$section_key")" -gt 1 ]]; then
      emit "## Where the section stands
The file is written.

## Assignment
Not applicable.

## Acceptance
Not applicable.

## Rejection conditions
Not applicable.

## Decision
COMPLETE - acceptance met"
    else
      emit "## Where the section stands
Nothing written yet.

## Assignment
Write the section's own file.

## Acceptance
The file exists.

## Rejection conditions
Any other file changes.

## Decision
ASSIGN - first piece"
    fi ;;
  *"Task: implement this assignment"*)
    # The dispatch's working directory is the claim under test, so it is both
    # written into the tree and recorded outside it.
    printf '%s\n' "$PWD" >> "$state_dir/develop_cwd.log"
    mkdir -p "$PWD/src"
    printf 'written by %s in %s\n' "$section_key" "$PWD" > "$PWD/src/$section_key.txt"
    emit "## What I changed
Wrote src/$section_key.txt.

## What I reused or restructured
Nothing.

## Validation
The file is on disk.

## What I could not do
Nothing.

## Status
DELIVERED" ;;
  *"Task: review a developer result"*)
    if [[ "${PM_STUB_REVIEW:-GO}" == "NO_GO" ]]; then
      emit "## Assessment
The change does not meet the brief.

## Drift review
Out of scope.

## Evidence check
No evidence.

## Risks
High.

## Decision
NO_GO - rejected"
    else
      emit "## Assessment
Good.

## Drift review
None.

## Evidence check
The file is present.

## Risks
Low.

## Decision
GO - accepted"
    fi ;;
  *"Task: write the section handoff"*)
    emit "## Outcome
The section's file exists.

## Decisions
Wrote one file.

## Interfaces
One file.

## Risks
None.

## What is unproven
None; every claim above was demonstrated.

## Next action
Nothing." ;;
  *) emit "## Decision
ASSIGN - fallback" ;;
esac
