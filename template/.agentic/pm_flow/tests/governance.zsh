#!/bin/zsh -f
# Part three: section priority, the portfolio review's triggers, its verdict
# parser, and the transitions CUT and BLOCK actually reach. All stubbed.
set -uo pipefail

TEMPLATE="$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)"
W="${1:?work dir required}"
rm -rf "$W"; mkdir -p "$W/src"
cd "$W"
git init -q .; git config user.email t@t; git config user.name t

mkdir -p "$W/.agentic"
cp -R "$TEMPLATE" "$W/.agentic/pm_flow"
FLOW="$W/.agentic/pm_flow"
rm -rf "$FLOW/project"
mkdir -p "$FLOW/demo/project_state" "$FLOW/demo/sections" "$FLOW/demo/runs"
printf 'demo\n' > "$FLOW/.project-key"
printf '{"domain":"generic"}\n' > "$FLOW/demo/project.json"
printf '# Demo Task Contract\n\nrules\n' > "$FLOW/demo/task_contract.md"
printf '# Plan\n\n## Completion criteria\n\n- lib/a.py exists\n' > "$FLOW/demo/project_state/plan.md"
mkdir -p lib docs tools pkg1 pkg2
for d in lib docs tools pkg1 pkg2; do printf 'x\n' > "$d/a.py"; done
printf 'print("hi")\n' > src/main.py

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
set_config escalation.cycles_before_convergence_review 0
# Every trigger off unless a test turns one on, so the review fires only where
# the test says it should.
set_config governance.portfolio_review_dispatches 0
set_config governance.portfolio_review_usd 0
set_config governance.portfolio_review_idle_cycles 0

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

brief() {
  printf '## Objective\n\n- %s\n\n## Scope\n\n- one thing\n\n## Priority\n\n- %s\n\n## Owned paths\n\n- `%s`\n\n## Dependencies\n\n%s\n\n## Acceptance\n\n- `.venv/bin/python -m pytest -q` exits 0\n\n## Rejection conditions\n\n- nothing runs\n' \
    "$1" "$2" "$3" "$4"
}

printf '\n===== C1: Priority is required, parsed, and persisted =====\n'
brief alpha "must-have: without it there is no product" "lib/" "- None." > "$W/b.md"
"$FLOWSH" init-section alpha --file "$W/b.md" >/dev/null
eq     "C1 the token is the first line of priority.txt" \
       "$(sed -n 1p "$FLOW/demo/sections/alpha/priority.txt")" "must-have"
has    "C1 what the product loses is kept on the second line" \
       "$(sed -n 2p "$FLOW/demo/sections/alpha/priority.txt")" "there is no product"

brief beta "nice-to-have: the product ships on one venue without it" "docs/" "- None." > "$W/b.md"
"$FLOWSH" init-section beta --file "$W/b.md" >/dev/null
eq "C1 nice-to-have is recorded as itself" \
   "$(sed -n 1p "$FLOW/demo/sections/beta/priority.txt")" "nice-to-have"

printf '## Objective\n\n- x\n\n## Scope\n\n- x\n\n## Owned paths\n\n- `tools/`\n\n## Dependencies\n\n- None.\n\n## Acceptance\n\n- x\n\n## Rejection conditions\n\n- y\n' > "$W/nopri.md"
out="$("$FLOWSH" init-section nopri --file "$W/nopri.md" 2>&1 || true)"
has    "C1 a brief with no Priority heading is refused" "$out" "Priority heading"
absent "C1 and no section was created"  "$(/bin/ls "$FLOW/demo/sections")" "nopri"

brief bad "critical: this is not one of the two tokens" "tools/" "- None." > "$W/b.md"
out="$("$FLOWSH" init-section bad --file "$W/b.md" 2>&1 || true)"
has "C1 a priority that is neither token is refused" "$out" "must-have or nice-to-have"

brief bare "must-have" "tools/" "- None." > "$W/b.md"
out="$("$FLOWSH" init-section bare --file "$W/b.md" 2>&1 || true)"
has "C1 a bare token with no stated loss is refused" "$out" "what the product loses"

printf '\n===== C1: priority is surfaced =====\n'
has "C1 status has a PRIORITY column" "$("$FLOWSH" status)" "PRIORITY"
has "C1 status shows the section priority" \
    "$("$FLOWSH" status | awk '$1 == "beta" {print $2}')" "nice-to-have"
has "C1 list-sections carries it too" "$("$FLOWSH" list-sections)" "| nice-to-have |"

printf '\n===== C1: a section created before priorities reads as must-have =====\n'
brief gamma "must-have: needed" "tools/" "- None." > "$W/b.md"
"$FLOWSH" init-section gamma --file "$W/b.md" >/dev/null
rm -f "$FLOW/demo/sections/gamma/priority.txt"
eq "C1 the default is must-have, so nothing is cut for lack of a label" \
   "$("$FLOWSH" status | awk '$1 == "gamma" {print $2}')" "must-have"
brief gamma "must-have: needed" "tools/" "- None." > /dev/null
printf 'must-have\nneeded\n' > "$FLOW/demo/sections/gamma/priority.txt"
git add -A >/dev/null 2>&1; git commit -qm sections >/dev/null

printf '\n===== C2: no trigger armed means no review =====\n'
absent "C2 no trigger is armed, so no review is offered" "$("$FLOWSH" next)" "portfolio-review"
has    "C2 and section work is still queued" "$("$FLOWSH" next)" "alpha"

REVIEW='## What the product still lacks

A real fill.

## Completion criteria

- lib/a.py exists: MET (ls lib/a.py)

## Evidence I probed

- `ls lib/a.py` printed the file.

## Plan structure

- Unstarted dependency: CLEAR
- Unreachable section: CLEAR
- Must-have inflation: FOUND beta calls itself must-have and is not
- Linear-chain risk: CLEAR

## Verdicts

- alpha: CONTINUE
- beta: CUT the product reaches every criterion without it
- gamma: BLOCK no credentials exist on this host
- delta: RESCOPE drop the live-venue criterion and prove the parser offline

## Shortest path

- Land the gateway probe, then one real fill.

## Decision

OFF_TRACK the spend is going to a nice-to-have'

printf '\n===== C2: the idle-cycle trigger fires =====\n'
brief delta "must-have: needed" "pkg1/" "- None." > "$W/b.md"
"$FLOWSH" init-section delta --file "$W/b.md" >/dev/null
set_config governance.portfolio_review_idle_cycles 1
mkdir -p "$FLOW/demo/sections/alpha/cycles/001"
eq  "C2 one project cycle with nothing done arms the review" \
    "$("$FLOWSH" next | sed -n 1p | awk '{print $3}')" "portfolio-review"
has "C2 status names the trigger" "$("$FLOWSH" status)" "portfolio review due"
set_config governance.portfolio_review_idle_cycles 0
absent "C2 switching the trigger off disarms it" "$("$FLOWSH" next)" "portfolio-review"

printf '\n===== C2: the dispatch-count trigger fires =====\n'
printf 'x\tdemo\tpm\tscope\t0.5\ty\n' > "$FLOW/demo/runs/cost_ledger.tsv"
printf 'x\tdemo\tpm\treview\t0.5\ty\n' >> "$FLOW/demo/runs/cost_ledger.tsv"
set_config governance.portfolio_review_dispatches 2
eq "C2 two recorded dispatches arm the review" \
   "$("$FLOWSH" next | sed -n 1p | awk '{print $3}')" "portfolio-review"
set_config governance.portfolio_review_dispatches 0

printf '\n===== C2: the spend trigger fires =====\n'
set_config governance.portfolio_review_usd 0.75
eq "C2 \$1.00 of ledger spend passes a \$0.75 threshold" \
   "$("$FLOWSH" next | sed -n 1p | awk '{print $3}')" "portfolio-review"

printf '\n===== C2: the review runs, and preempts actionable section work =====\n'
out="$(PM_FLOW_STUB="$REVIEW" "$FLOWSH" tick 2>&1)"
has    "C2 the tick is taken by the project, not a section" "$out" "section=(project)"
has    "C2 the action is the portfolio review"              "$out" "action=portfolio-review"
has    "C2 the product-level verdict is recorded"           "$out" "OFF_TRACK"
eq     "C2 decision.txt holds the product verdict" \
       "$(cat "$FLOW/demo/project_state/portfolio/001/decision.txt")" "OFF_TRACK"
exists "C2 the trigger that convened it is recorded" \
       "$FLOW/demo/project_state/portfolio/001/trigger.txt"

printf '\n===== C2: all four verdict tokens parse =====\n'
verdicts="$FLOW/demo/project_state/portfolio/001/verdicts.tsv"
eq "C2 CONTINUE parses" "$(awk -F'\t' '$1 == "alpha" {print $2}' "$verdicts")" "CONTINUE"
eq "C2 CUT parses"      "$(awk -F'\t' '$1 == "beta"  {print $2}' "$verdicts")" "CUT"
eq "C2 BLOCK parses"    "$(awk -F'\t' '$1 == "gamma" {print $2}' "$verdicts")" "BLOCK"
eq "C2 RESCOPE parses"  "$(awk -F'\t' '$1 == "delta" {print $2}' "$verdicts")" "RESCOPE"
has "C2 the reason travels with the verdict" \
    "$(awk -F'\t' '$1 == "gamma" {print $3}' "$verdicts")" "no credentials"
has "C2 the plan-structure checks are recorded" \
    "$(cat "$FLOW/demo/project_state/portfolio/001/plan_structure.tsv")" "MUST_HAVE_INFLATION"

printf '\n===== C2: CUT and BLOCK reach the right terminal status =====\n'
eq "C2 CUT cancels the section"      "$(cat "$FLOW/demo/sections/beta/status.txt")"  "cancelled"
eq "C2 BLOCK blocks the section"     "$(cat "$FLOW/demo/sections/gamma/status.txt")" "blocked"
eq "C2 CONTINUE leaves the section alone" \
   "$(cat "$FLOW/demo/sections/alpha/status.txt")" "planned"
has "C2 the cut section's handoff carries the officer's reason" \
    "$(cat "$FLOW/demo/sections/beta/handoff.md")" "reaches every criterion without it"
has "C2 a governance handoff still states what is unproven" \
    "$(cat "$FLOW/demo/sections/gamma/handoff.md")" "## What is unproven"
eq  "C2 a cut section is not actionable" \
    "$("$FLOWSH" status | awk '$1 == "beta" {print $4}')" "idle"
eq  "C2 a blocked section is not actionable" \
    "$("$FLOWSH" status | awk '$1 == "gamma" {print $4}')" "idle"

printf '\n===== C2: RESCOPE reaches that section next scope =====\n'
exists "C2 the rescope reason is written" "$FLOW/demo/sections/delta/portfolio_rescope.txt"
has    "C2 it names what has to change" \
       "$(cat "$FLOW/demo/sections/delta/portfolio_rescope.txt")" "drop the live-venue criterion"
PM_FLOW_STUB='## Workplan task

T1

## Assignment

Do it.

## Acceptance

- x

## Rejection conditions

- y

## Decision

ASSIGN' PM_FLOW_SECTION=delta "$FLOWSH" tick >/dev/null
has "C2 the reason reached the scope prompt" \
    "$(cat "$FLOW/demo/sections/delta/cycles/001/scope_prompt.md")" "portfolio_rescope.txt"
if [[ ! -f "$FLOW/demo/sections/delta/portfolio_rescope.txt" ]]; then
  ok "C2 and it is consumed rather than riding along forever"
else bad "C2 and it is consumed rather than riding along forever" "still present"; fi

printf '\n===== C2: the review is not re-convened until the baseline moves =====\n'
absent "C2 the baseline advanced with the review" "$("$FLOWSH" next)" "portfolio-review"

printf '\n===== C2: the officer gets durable memory =====\n'
log="$FLOW/demo/project_state/portfolio_log.md"
exists "C2 portfolio_log.md is written"     "$log"
has    "C2 it records the criteria"         "$(cat "$log")" "lib/a.py exists: MET"
has    "C2 it records the verdicts"         "$(cat "$log")" "beta: CUT"
has    "C2 it records the shortest path"    "$(cat "$log")" "Land the gateway probe"
has    "C2 it carries a one-line summary for compaction" "$(cat "$log")" "- Summary:"

printf '\n===== C2: an unreadable review is refused, not half-applied =====\n'
set_config governance.portfolio_review_dispatches 1
before="$(cat "$FLOW/demo/sections/alpha/status.txt")"
out="$(PM_FLOW_STUB='## Verdicts

- alpha: CUT

## Shortest path

- x

## Decision

ON_TRACK' "$FLOWSH" tick 2>&1)"
has    "C2 the review is sent back" "$out" "unreadable"
eq     "C2 the CUT with no reason was not applied" \
       "$(cat "$FLOW/demo/sections/alpha/status.txt")" "$before"
exists "C2 the complaint is fed back for the re-ask" \
       "$FLOW/demo/project_state/portfolio/002/verdict_feedback.md"
has    "C2 the complaint names the missing reason" \
       "$(cat "$FLOW/demo/project_state/portfolio/002/verdict_feedback.md")" "states no reason"
has    "C2 and the missing plan-structure checks" \
       "$(cat "$FLOW/demo/project_state/portfolio/002/verdict_feedback.md")" "UNSTARTED_DEPENDENCY"

printf '\n===== C3: What is unproven is a required handoff heading =====\n'
short='## Outcome

- x

## Decisions

- x

## Interfaces

- x

## Risks

- x

## Next action

- x'
out="$(printf '%s\n' "$short" | "$FLOWSH" section-handoff alpha active "no unproven heading" 2>&1 || true)"
has "C3 a handoff without it is refused" "$out" "What is unproven"

printf '\n===== C4: the dependency graph changes only through validation =====\n'
printf '## Dependencies\n\n- alpha\n' > "$W/deps.md"
"$FLOWSH" section-dependencies delta --file "$W/deps.md" >/dev/null
has "C4 the dependency is recorded" \
    "$(cat "$FLOW/demo/sections/delta/dependency_handoffs.txt")" "sections/alpha/handoff.md"
printf '## Dependencies\n\n- nosuchsection\n' > "$W/deps.md"
out="$("$FLOWSH" section-dependencies delta --file "$W/deps.md" 2>&1 || true)"
has "C4 a dependency on a section that does not exist is refused" "$out" "does not exist"
printf '## Dependencies\n\n- delta\n' > "$W/deps.md"
out="$("$FLOWSH" section-dependencies alpha --file "$W/deps.md" 2>&1 || true)"
has "C4 a cycle is refused" "$out" "dependency cycle"
eq  "C4 and the graph is left as it was" \
    "$(cat "$FLOW/demo/sections/alpha/dependency_handoffs.txt")" ""

printf '\ntotals: pass=%d fail=%d\n' "$pass" "$failn"
[[ "$failn" == 0 ]]
