#!/bin/zsh -f
set -euo pipefail

# Selectors inherited from a live pm-flow dispatch must never redirect fixture
# artifacts into that live project.
for name in ${(k)parameters[(I)PM_FLOW_*]}; do
  unset "$name"
done

REPO_ROOT="$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)"
QA_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pm-flow-artifact-quality.XXXXXX")"
trap 'rm -rf -- "$QA_ROOT"' EXIT HUP INT TERM

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

PROJECT="fixture"
PROJECT_DIR="$QA_ROOT/.agentic/pm_flow/$PROJECT"
STATE_DIR="$PROJECT_DIR/project_state"
SECTIONS_DIR="$PROJECT_DIR/sections"
mkdir -p "$STATE_DIR" "$SECTIONS_DIR/alpha" "$SECTIONS_DIR/beta" "$SECTIONS_DIR/gamma"
printf '%s\n' "$PROJECT" > "$QA_ROOT/.agentic/pm_flow/.project-key"

cat > "$STATE_DIR/plan.md" <<'EOF'
# Project portfolio plan

## Mission
- Exercise the durable artifact ranker.
## Project-wide constraints
- Use only fixture data.
## Section graph
- Alpha and beta are independent.
## Integration order
- Either section may finish first.
## Project-level decisions
- Keep ranking read-only.
## Completion criteria
- Every fixture artifact is ranked.
## Next coordination actions
At review 003 verify the fixture output.
EOF

cat > "$SECTIONS_DIR/alpha/brief.md" <<'EOF'
# alpha brief

## Objective
- Rank alpha.
## Scope
- Durable fixture files only.
## Priority
- nice-to-have: the fixture loses ranking coverage without it.
## Owned paths
- `src/alpha/`
## Dependencies
- None.
## Acceptance
- A1: every file is printed.
- A2: echo mutation is visible.
## Rejection conditions
- A composite score is printed.

This deliberately repeated paragraph contains enough ordinary words to exercise shared durable prose detection across files in this section.
EOF
printf '\n' >> "$SECTIONS_DIR/alpha/brief.md"
for _ in {1..1450}; do printf ' padding' >> "$SECTIONS_DIR/alpha/brief.md"; done
printf '\n' >> "$SECTIONS_DIR/alpha/brief.md"

cat > "$SECTIONS_DIR/alpha/workplan.md" <<'EOF'
# alpha workplan

## Design summary
- The ranker reads every durable artifact and reports deterministic findings without modifying any fixture content during evaluation.
## Interfaces and data changes
- Standard output only.
## Task T1 — Rank
- Paths: `src/alpha/`
- Acceptance IDs: A1, A2.
## Integration and end-to-end validation
- Run the fixture command.
## Risks and rollback
- Delete fixture files.
## Acceptance coverage
| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1 | T1 | file lines |
EOF

cat > "$SECTIONS_DIR/alpha/state.md" <<'EOF'
# alpha state

## Current task
- T1.
## Completed tasks and evidence
- None.
## Active decisions

- The ranker reads every durable artifact and reports deterministic findings without modifying any fixture content during evaluation.

## Blockers
- None.
## Next eligible task
- T1.
EOF

cat > "$SECTIONS_DIR/alpha/handoff.md" <<'EOF'
# alpha handoff

## Outcome

This deliberately repeated paragraph contains enough ordinary words to exercise shared durable prose detection across files in this section.

## Decisions
- Keep `foreign/file.txt` outside this section unchanged.
## Interfaces
- Standard output.
## Risks
- None.
## What is unproven
- Nothing else.
## Next action
- Inspect output.
EOF

cat > "$SECTIONS_DIR/beta/brief.md" <<'EOF'
# beta brief

## Objective
- Rank beta.
## Scope
- Durable fixture files only.
## Priority
- nice-to-have: the fixture loses isolation coverage without it.
## Owned paths
- `src/beta/`
## Dependencies
- None.
## Acceptance
- A1: every file is printed.
## Rejection conditions
- Cross-section prose is treated as echo.

This deliberately repeated paragraph contains enough ordinary words to exercise shared durable prose detection across files in this section.
EOF

cat > "$SECTIONS_DIR/beta/workplan.md" <<'EOF'
# beta workplan

## Design summary
- Keep the second section independent from the first while exercising the same output interface in this synthetic project.
## Interfaces and data changes
- Standard output only.
## Task T1 — Rank
- Paths: `src/not-beta/file.py`
- Acceptance IDs: A1.
## Integration and end-to-end validation
- Run the fixture command.
## Risks and rollback
- Delete fixture files.
## Acceptance coverage
| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1 | T1 | file lines |
EOF

cat > "$SECTIONS_DIR/beta/state.md" <<'EOF'
# beta state

## Current task
- T1.
## Completed tasks and evidence
- None.
## Active decisions
- None.
## Blockers
- None.
## Next eligible task
- T1.
EOF

cat > "$SECTIONS_DIR/beta/handoff.md" <<'EOF'
# beta handoff

## Outcome
- Ranking exercised.
## Decisions
- None.
## Interfaces
- Standard output.
## Risks
- None.
## What is unproven
- Nothing else.
## Next action
- Inspect output.
EOF

cat > "$SECTIONS_DIR/gamma/brief.md" <<'EOF'
# gamma brief

### Objective
- Rank a live-style section precisely.
### Current baseline
- The fixture has depth-three headings.
### Deliverables
- A clean durable artifact set.
### User-visible scenarios
- The rank output has no gamma findings.
### Interfaces produced
- Standard output.
### Interfaces consumed
- Read `shared/gamma/input.json` without owning it.
### Scope
- Exercise non-path token recognition.
### Non-goals
- Changing `state.md` during ranking.
### Priority
- nice-to-have: this fixture protects finding precision.
### Owned paths
- `src/gamma/`
### Dependencies
- None.
### Constraints and fixed decisions
- Keep the fixture read-only.
### Acceptance
- A1: depth-three headings are accepted.
- A2: grouped coverage cells cover every ID.
### Rejection conditions
- A declared consumed path is reported as unowned.
### Open questions
- None.
EOF

cat > "$SECTIONS_DIR/gamma/workplan.md" <<'EOF'
# gamma workplan

### Design summary
- Read the live-style fixture and preserve precise findings.
### Interfaces and data changes
- Read `src/gamma/` and print standard output.
### Task T1 — Rank
- Acceptance IDs: A1, A2.
### Integration and end-to-end validation
- Run the fixture rank command.
### Risks and rollback
- Revert the fixture mutation.
### Acceptance coverage
| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1, A2 | T1 | A3 remains outside the first cell |
EOF

cat > "$SECTIONS_DIR/gamma/state.md" <<'EOF'
# gamma state

### Current task
- T1.
### Completed tasks and evidence
- The `shared/gamma/input.json` interface is available.
### Active decisions
- Keep the section independent.
- Treat `0.25`, `os.environ`, `v1.36.0`, and `2>/dev/null` as non-path tokens.
### Blockers
- None.
### Next eligible task
- T1.
EOF

cat > "$SECTIONS_DIR/gamma/handoff.md" <<'EOF'
# gamma handoff

### Outcome
- Precision fixture ready.
### Decisions
- Keep grouped coverage.
### Interfaces
- Standard output.
### Risks
- None.
### What is unproven
- Nothing else.
### Next action
- Inspect output.
EOF

run_rank() {
  PM_FLOW_REPO_ROOT="$QA_ROOT" \
    PYTHONPATH="$REPO_ROOT/src" python3 -m pm_flow.quality rank --project "$PROJECT"
}

run_rank > "$QA_ROOT/initial.out" || fail "rank command failed"
line_count="$(wc -l < "$QA_ROOT/initial.out" | tr -d ' ')"
[[ "$line_count" == 13 ]] || fail "rank printed $line_count lines instead of one for each of 13 files"
for file in project_state/plan.md sections/alpha/brief.md sections/alpha/workplan.md \
    sections/alpha/state.md sections/alpha/handoff.md sections/beta/brief.md \
    sections/beta/workplan.md sections/beta/state.md sections/beta/handoff.md \
    sections/gamma/brief.md sections/gamma/workplan.md sections/gamma/state.md \
    sections/gamma/handoff.md; do
  grep -q "$file" "$QA_ROOT/initial.out" || fail "rank omitted $file"
done
for file in brief.md workplan.md state.md handoff.md; do
  gamma_line="$(grep "sections/gamma/$file" "$QA_ROOT/initial.out")"
  [[ "$gamma_line" == *"findings: none"* ]] || \
    fail "live-style gamma $file was not finding-free: $gamma_line"
  printf '%s\n' "$gamma_line"
done
first_line="$(head -n 1 "$QA_ROOT/initial.out")"
[[ "$first_line" == *"sections/alpha/brief.md"* ]] || fail "highest-finding artifact was not ranked first: $first_line"
for dimension in length echo shape boundaries stale; do
  grep -q "${dimension}:" "$QA_ROOT/initial.out" || fail "fixture did not produce $dimension finding"
done
if grep -Eqi 'composite|quality:[[:space:]]*[0-9]|score[=:][[:space:]]*[0-9]' "$QA_ROOT/initial.out"; then
  fail "rank printed a composite score or quality total"
fi
beta_brief_line="$(grep 'sections/beta/brief.md' "$QA_ROOT/initial.out")"
[[ "$beta_brief_line" != *"echo:"* ]] || fail "cross-section repetition was reported as echo"
printf 'PASS: rank prints every file worst first with separate dimension findings and no composite\n'

alpha_handoff_before="$(grep 'sections/alpha/handoff.md' "$QA_ROOT/initial.out")"
[[ "$alpha_handoff_before" == *"echo:"* ]] || fail "repeated handoff paragraph did not produce echo"
[[ "$alpha_handoff_before" == *"boundaries:"* ]] || fail "handoff control finding is missing"
sed -i.bak '/^This deliberately repeated paragraph/d' "$SECTIONS_DIR/alpha/handoff.md"
rm "$SECTIONS_DIR/alpha/handoff.md.bak"
run_rank > "$QA_ROOT/no-echo.out" || fail "rank failed after echo mutation"
alpha_handoff_after="$(grep 'sections/alpha/handoff.md' "$QA_ROOT/no-echo.out")"
[[ "$alpha_handoff_after" != *"echo:"* ]] || fail "removing repeated paragraph did not clear echo"
[[ "$alpha_handoff_after" == *"boundaries:"* ]] || fail "echo mutation changed the handoff control finding"
before_other="$(printf '%s\n' "$alpha_handoff_before" | sed 's/ | echo: [^|]*//')"
[[ "$before_other" == "$alpha_handoff_after" ]] || fail "echo mutation changed another handoff finding"
printf 'PASS: removing a shared handoff paragraph clears only its echo finding\n'

alpha_brief_before="$(grep 'sections/alpha/brief.md' "$QA_ROOT/no-echo.out")"
[[ "$alpha_brief_before" == *"shape:"*A2* ]] || fail "missing A2 coverage did not produce brief shape"
sed -i.bak '/| A1 | T1 | file lines |/a\
| A2 | T1 | echo mutation |' "$SECTIONS_DIR/alpha/workplan.md"
rm "$SECTIONS_DIR/alpha/workplan.md.bak"
run_rank > "$QA_ROOT/covered.out" || fail "rank failed after coverage mutation"
alpha_brief_after="$(grep 'sections/alpha/brief.md' "$QA_ROOT/covered.out")"
[[ "$alpha_brief_after" != *"shape:"* ]] || fail "adding A2 coverage did not clear brief shape"
[[ "$alpha_brief_after" == *"length:"* ]] || fail "coverage mutation changed brief length finding"
alpha_state_line="$(grep 'sections/alpha/state.md' "$QA_ROOT/covered.out")"
[[ "$alpha_state_line" == *"stale:"* ]] || fail "pasted design summary did not produce stale"
printf 'PASS: coverage mutation clears shape and pasted design summary produces stale\n'

sed -i.bak 's/^### Open questions$/### Questions/' "$SECTIONS_DIR/gamma/brief.md"
rm "$SECTIONS_DIR/gamma/brief.md.bak"
run_rank > "$QA_ROOT/missing-heading.out" || fail "rank failed after heading mutation"
gamma_missing_heading_line="$(grep 'sections/gamma/brief.md' "$QA_ROOT/missing-heading.out")"
[[ "$gamma_missing_heading_line" == *"shape:"*"Open questions"* ]] || \
  fail "genuinely missing gamma heading did not produce shape"
printf '%s\n' "$gamma_missing_heading_line"
sed -i.bak 's/^### Questions$/### Open questions/' "$SECTIONS_DIR/gamma/brief.md"
rm "$SECTIONS_DIR/gamma/brief.md.bak"

sed -i.bak '/^- A2: grouped coverage cells cover every ID\.$/a\
- A3: an uncovered ID remains visible.' "$SECTIONS_DIR/gamma/brief.md"
rm "$SECTIONS_DIR/gamma/brief.md.bak"
run_rank > "$QA_ROOT/uncovered.out" || fail "rank failed after uncovered-ID mutation"
gamma_brief_line="$(grep 'sections/gamma/brief.md' "$QA_ROOT/uncovered.out")"
[[ "$gamma_brief_line" == *"shape:"*"A3"* ]] || \
  fail "genuinely uncovered gamma ID did not produce shape"
printf '%s\n' "$gamma_brief_line"

sed -i.bak '/^- Keep the section independent\.$/a\
- Inspect `foreign/undeclared.py`.' "$SECTIONS_DIR/gamma/state.md"
rm "$SECTIONS_DIR/gamma/state.md.bak"
run_rank > "$QA_ROOT/undeclared.out" || fail "rank failed after undeclared-path mutation"
gamma_state_line="$(grep 'sections/gamma/state.md' "$QA_ROOT/undeclared.out")"
[[ "$gamma_state_line" == *"boundaries:"*"foreign/undeclared.py"* ]] || \
  fail "state-only gamma path did not produce boundaries"
printf '%s\n' "$gamma_state_line"
printf 'PASS: depth-three grouped coverage and declared references stay clean while real defects fire\n'
