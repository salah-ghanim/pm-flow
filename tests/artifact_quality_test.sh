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
mkdir -p "$STATE_DIR" "$SECTIONS_DIR/alpha" "$SECTIONS_DIR/beta" \
  "$SECTIONS_DIR/gamma" "$SECTIONS_DIR/delta"
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

cat > "$SECTIONS_DIR/delta/brief.md" <<'EOF'
# delta brief

### Objective
- Pin depth-scoped workplan section reads.
### Scope
- Durable fixture files only.
### Priority
- nice-to-have: the fixture detects a section terminator regression.
### Owned paths
- `src/delta/`
### Dependencies
- None.
### Acceptance
- A1: repeated prose outside the design summary is not stale.
### Rejection conditions
- A state file is compared with later workplan sections.
EOF

cat > "$SECTIONS_DIR/delta/workplan.md" <<'EOF'
# delta workplan

### Design summary
- Keep the design summary short and distinct from every state paragraph.
### Interfaces and data changes
- Standard output only.
### Task T1 — Rank
- Paths: `src/delta/`
- Acceptance IDs: A1.
### Integration and end-to-end validation
- Run the fixture command.
### Risks and rollback

This repeated rollback paragraph has enough ordinary words to prove that depth scoped markdown sections stop at the next peer heading.

### Acceptance coverage
| Brief ID | Workplan task | Evidence required |
|---|---|---|
| A1 | T1 | state has echo but not stale |
EOF

cat > "$SECTIONS_DIR/delta/state.md" <<'EOF'
# delta state

### Current task
- T1.
### Completed tasks and evidence
- None.
### Active decisions

This repeated rollback paragraph has enough ordinary words to prove that depth scoped markdown sections stop at the next peer heading.

### Blockers
- None.
### Next eligible task
- T1.
EOF

cat > "$SECTIONS_DIR/delta/handoff.md" <<'EOF'
# delta handoff

### Outcome
- Terminator fixture ready.
### Decisions
- Keep the repeated paragraph outside the design summary.
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
    PYTHONPATH="$REPO_ROOT/src" python3 -m pm_flow.quality rank --project "$PROJECT" "$@"
}

run_show() {
  PM_FLOW_REPO_ROOT="$QA_ROOT" \
    PYTHONPATH="$REPO_ROOT/src" python3 -m pm_flow.quality show --project "$PROJECT" "$@"
}

run_rank > "$QA_ROOT/initial.out" || fail "rank command failed"
line_count="$(wc -l < "$QA_ROOT/initial.out" | tr -d ' ')"
[[ "$line_count" == 17 ]] || fail "rank printed $line_count lines instead of one for each of 17 files"
for file in project_state/plan.md sections/alpha/brief.md sections/alpha/workplan.md \
    sections/alpha/state.md sections/alpha/handoff.md sections/beta/brief.md \
    sections/beta/workplan.md sections/beta/state.md sections/beta/handoff.md \
    sections/gamma/brief.md sections/gamma/workplan.md sections/gamma/state.md \
    sections/gamma/handoff.md sections/delta/brief.md sections/delta/workplan.md \
    sections/delta/state.md sections/delta/handoff.md; do
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
delta_state_line="$(grep 'sections/delta/state.md' "$QA_ROOT/initial.out")"
[[ "$delta_state_line" == *"echo:"* ]] || fail "depth terminator fixture did not produce echo"
[[ "$delta_state_line" != *"stale:"* ]] || \
  fail "depth terminator fixture incorrectly produced stale: $delta_state_line"
printf 'PASS: rank prints every file worst first with separate dimension findings and no composite\n'

QUALITY_DIR="$PROJECT_DIR/quality"
[[ -f "$QUALITY_DIR/latest.md" ]] || fail "rank did not write latest.md"
[[ -f "$QUALITY_DIR/latest.json" ]] || fail "rank did not write latest.json"
cmp -s "$QA_ROOT/initial.out" "$QUALITY_DIR/latest.md" || \
  fail "latest.md differs from rank stdout"
snapshots=("$QUALITY_DIR"/*Z.json(N))
[[ "${#snapshots}" == 1 ]] || \
  fail "first rank wrote ${#snapshots} timestamped snapshots instead of one"
cmp -s "$QUALITY_DIR/latest.json" "$snapshots[1]" || \
  fail "first timestamped snapshot differs from latest.json"
python3 - "$QUALITY_DIR/latest.json" "$QA_ROOT/initial.out" <<'PY' || \
  fail "latest.json does not match rank stdout"
import json
import sys

record_path, stdout_path = sys.argv[1:]
with open(record_path, encoding="utf-8") as handle:
    record = json.load(handle)
with open(stdout_path, encoding="utf-8") as handle:
    lines = [line.rstrip("\n") for line in handle]

expected = []
for line in lines:
    parts = line.split(" | ")
    findings = []
    if parts[1] != "findings: none":
        for value in parts[1:]:
            code, message = value.split(": ", 1)
            findings.append({"code": code, "message": message})
    expected.append({"file": parts[0], "findings": findings})

actual = [
    {"file": artifact["file"], "findings": artifact["findings"]}
    for artifact in record["artifacts"]
]
assert record["project"] == "fixture"
assert record["generated_at"].endswith("Z")
assert set(record) == {"project", "generated_at", "artifacts"}
assert all(
    set(artifact) == {"file", "words", "budget", "over", "findings"}
    for artifact in record["artifacts"]
)
assert actual == expected, (actual, expected)
print("MATCH: " + ", ".join(artifact["file"] for artifact in actual))
PY

cp "$QUALITY_DIR/latest.json" "$QA_ROOT/first-latest.json"
sleep 1
run_rank > "$QA_ROOT/second.out" || fail "second rank command failed"
cmp -s "$QA_ROOT/second.out" "$QUALITY_DIR/latest.md" || \
  fail "second rank did not replace latest.md with stdout"
snapshots=("$QUALITY_DIR"/*Z.json(N))
[[ "${#snapshots}" == 2 ]] || \
  fail "second rank left ${#snapshots} timestamped snapshots instead of two"
cmp -s "$QUALITY_DIR/latest.json" "$snapshots[-1]" || \
  fail "second timestamped snapshot differs from latest.json"
cmp -s "$QA_ROOT/first-latest.json" "$QUALITY_DIR/latest.json" && \
  fail "second rank did not replace latest.json"
printf 'PASS: rank writes matching latest records and preserves timestamped snapshots\n'

find "$PROJECT_DIR/quality" -type f | sort > "$QA_ROOT/show-files-before"
run_show > "$QA_ROOT/show.out" || fail "show command failed"
cmp -s "$QA_ROOT/show.out" "$QUALITY_DIR/latest.md" || \
  fail "show stdout differs from latest.md"
cmp -s "$QA_ROOT/show.out" "$QA_ROOT/second.out" || \
  fail "show stdout differs from rank stdout"
find "$PROJECT_DIR/quality" -type f | sort > "$QA_ROOT/show-files-after"
cmp -s "$QA_ROOT/show-files-before" "$QA_ROOT/show-files-after" || \
  fail "show created or removed a quality record file"

if run_show --out "$QA_ROOT/empty-record" \
    > "$QA_ROOT/empty-record.out" 2> "$QA_ROOT/empty-record.err"; then
  fail "show exited successfully without a quality record"
fi
grep -Fq "${QA_ROOT:A}/empty-record" "$QA_ROOT/empty-record.err" || \
  fail "missing-record error did not name the resolved directory"
grep -q "python -m pm_flow.quality rank" "$QA_ROOT/empty-record.err" || \
  fail "missing-record error did not name the command that creates it"
grep -q 'refusing quality record' "$QA_ROOT/empty-record.err" && \
  fail "missing-record error was confused with destination refusal"
[[ ! -s "$QA_ROOT/empty-record.out" ]] || \
  fail "show printed missing-record output on stdout"
[[ ! -e "$QA_ROOT/empty-record" ]] || \
  fail "show created the missing record directory"

if run_show --out "$SECTIONS_DIR/alpha/quality" \
    > "$QA_ROOT/show-sections-refusal.out" 2> "$QA_ROOT/show-sections-refusal.err"; then
  fail "show accepted an output directory inside sections"
fi
grep -q 'sections' "$QA_ROOT/show-sections-refusal.err" || \
  fail "show sections refusal did not explain the rejected path"
show_section_records=("${(@f)$(find "$SECTIONS_DIR" -name 'quality*' -print)}")
[[ -z "${show_section_records[1]:-}" ]] || \
  fail "show sections refusal created a quality path: ${show_section_records[1]}"
printf 'PASS: show reprints the record byte-for-byte, stays read-only, and distinguishes absence from refusal\n'

if run_rank --out "$SECTIONS_DIR/alpha/quality" \
    > "$QA_ROOT/sections-refusal.out" 2> "$QA_ROOT/sections-refusal.err"; then
  fail "rank accepted an output directory inside sections"
fi
grep -q 'sections' "$QA_ROOT/sections-refusal.err" || \
  fail "sections refusal did not explain the rejected path"
section_records=("${(@f)$(find "$SECTIONS_DIR" -name 'quality*' -print)}")
[[ -z "${section_records[1]:-}" ]] || \
  fail "sections refusal created a quality path: ${section_records[1]}"
printf 'PASS: --out inside sections is refused before creating a path\n'

LINKED_ROOT="$QA_ROOT/linked-worktree"
mkdir -p "$LINKED_ROOT"
printf 'gitdir: %s\n' "$QA_ROOT/missing-gitdir" > "$LINKED_ROOT/.git"
if run_rank --out "$LINKED_ROOT/quality" \
    > "$QA_ROOT/worktree-refusal.out" 2> "$QA_ROOT/worktree-refusal.err"; then
  fail "rank accepted an output directory inside a linked worktree"
fi
grep -q 'linked git worktree' "$QA_ROOT/worktree-refusal.err" || \
  fail "worktree refusal did not explain the rejected path"
[[ ! -e "$LINKED_ROOT/quality" ]] || \
  fail "worktree refusal created its output directory"
printf 'PASS: linked-worktree output is refused before creating a path\n'

TRACKED_ROOT="$QA_ROOT/tracked-repo"
mkdir -p "$TRACKED_ROOT/.agentic/pm_flow/tracked/project_state"
git -C "$TRACKED_ROOT" init -q
if PM_FLOW_REPO_ROOT="$TRACKED_ROOT" PYTHONPATH="$REPO_ROOT/src" \
    python3 -m pm_flow.quality rank --project tracked --out "$TRACKED_ROOT/quality" \
    > "$QA_ROOT/tracked-refusal.out" 2> "$QA_ROOT/tracked-refusal.err"; then
  fail "rank accepted a git-visible output directory"
fi
grep -q 'git does not ignore' "$QA_ROOT/tracked-refusal.err" || \
  fail "git-visible refusal did not explain the rejected path"
[[ ! -e "$TRACKED_ROOT/quality" ]] || \
  fail "git-visible refusal created its output directory"
printf 'PASS: git-visible output is refused before creating a path\n'

if PM_FLOW_REPO_ROOT="$QA_ROOT" PYTHONPATH="$REPO_ROOT/src" \
    python3 -m pm_flow.quality rank --project nosuch \
    > "$QA_ROOT/nosuch.out" 2> "$QA_ROOT/nosuch.err"; then
  fail "zero-artifact project exited successfully"
fi
grep -q "project 'nosuch'" "$QA_ROOT/nosuch.err" || \
  fail "zero-artifact error did not name the project key"
grep -q '/.agentic/pm_flow/nosuch/sections' "$QA_ROOT/nosuch.err" || \
  fail "zero-artifact error did not name the sections directory"
[[ ! -e "$QA_ROOT/.agentic/pm_flow/nosuch/quality" ]] || \
  fail "zero-artifact run created a quality directory"
printf 'PASS: zero-artifact project fails loudly without writing a record\n'

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

host_status_before="$(git -C "$REPO_ROOT" status --porcelain)"
if PYTHONPATH="$REPO_ROOT/src" python3 -m pm_flow.quality rank --project pm-agent \
    > "$QA_ROOT/host.out" 2> "$QA_ROOT/host.err"; then
  host_branch="wrote ignored project metadata"
else
  host_branch="refused linked worktree"
  grep -q 'linked git worktree' "$QA_ROOT/host.err" || \
    fail "host rank failed for an unexpected reason: $(<"$QA_ROOT/host.err")"
fi
host_status_after="$(git -C "$REPO_ROOT" status --porcelain)"
[[ "$host_status_before" == "$host_status_after" ]] || \
  fail "host repository status changed after rank"
host_section_records=("${(@f)$(find "$REPO_ROOT/.agentic/pm_flow/pm-agent/sections" \
  \( -name 'quality*' -o -name '*.score' \) -print)}")
[[ -z "${host_section_records[1]:-}" ]] || \
  fail "host rank wrote under sections: ${host_section_records[1]}"
printf 'PASS: host rank leaves git status and sections unchanged (%s)\n' "$host_branch"
