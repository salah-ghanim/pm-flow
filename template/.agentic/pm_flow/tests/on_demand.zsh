#!/bin/zsh -f
# Part five: the three hand-operated commands. The dispatcher is stubbed and
# records who it was asked to be, so "the right role got the right prompt" is
# checked without a model.
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
mkdir -p lib docs
printf 'x\n' > lib/a.py
printf 'x\n' > docs/a.md

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
# Nothing fires on its own here: every trigger is off until a test arms it.
set_config governance.portfolio_review_dispatches 0
set_config governance.portfolio_review_usd 0
set_config governance.portfolio_review_idle_cycles 0

export STUB_LOG="$W/dispatch.log"
: > "$STUB_LOG"

# The stub records the role it was dispatched as, the label, and the prompt it
# was handed, then answers with PM_FLOW_STUB.
cat > "$FLOW/agent_exec.sh" <<'STUB'
#!/bin/zsh -f
set -euo pipefail
ROLE="${1:-}"
shift || true
OUT=""; LABEL=""; PROMPT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) OUT="$2"; shift 2 ;;
    --label) LABEL="$2"; shift 2 ;;
    --prompt-file) PROMPT="$2"; shift 2 ;;
    --heartbeat|--seat) shift 2 ;;
    *) shift ;;
  esac
done
printf '%s\t%s\t%s\n' "$ROLE" "$LABEL" "$PROMPT" >> "$STUB_LOG"
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
missing(){ if [[ ! -e "$2" ]]; then ok "$1"; else bad "$1" "$2 exists"; fi }
field() { printf '%s\n' "$1" | awk -F= -v k="$2" '$1 == k {print $2; exit}' }

brief() {
  printf '## Objective\n\n- %s\n\n## Scope\n\n- one thing\n\n## Priority\n\n- must-have: without it there is no product\n\n## Owned paths\n\n- `%s`\n\n## Dependencies\n\n- None.\n\n## Acceptance\n\n- `.venv/bin/python -m pytest -q` exits 0\n\n## Rejection conditions\n\n- nothing runs\n' \
    "$1" "$2"
}
brief alpha "lib/" > "$W/b.md"; "$FLOWSH" init-section alpha --file "$W/b.md" >/dev/null
brief beta  "docs/" > "$W/b.md"; "$FLOWSH" init-section beta  --file "$W/b.md" >/dev/null
git add -A >/dev/null 2>&1; git commit -qm fixture >/dev/null

ANALYSIS='## Where the section stands

- The acceptance check is unknown: nothing has run it.

## What is blocking it

- Nothing external. The work has not been attempted.

## What I would do next and why

- Run the acceptance check first, because every other answer depends on it.

## What I cannot settle myself

- Whether the venue account exists.'

printf '\n===== D1: section-analysis dispatches the manager, outside any cycle =====\n'
: > "$STUB_LOG"
out="$(PM_FLOW_STUB="$ANALYSIS" "$FLOWSH" section-analysis alpha 2>&1)"
has "D1 the command reports what it recorded" "$out" "recorded=section-analysis"
eq  "D1 the section manager is the role dispatched" \
    "$(awk -F'\t' 'NR == 1 {print $1}' "$STUB_LOG")" "pm"
has "D1 the label names the section it assessed" \
    "$(awk -F'\t' 'NR == 1 {print $2}' "$STUB_LOG")" "analysis alpha"
eq  "D1 exactly one dispatch is spent" "$(wc -l < "$STUB_LOG" | tr -d '[:space:]')" "1"

PROMPT="$(awk -F'\t' 'NR == 1 {print $3}' "$STUB_LOG")"
has "D1 the prompt is the section-analysis task" "$(cat "$PROMPT")" "Task: assess section \`alpha\`"
has "D1 it forbids writing an assignment"        "$(cat "$PROMPT")" "Do not write an assignment"
has "D1 it forbids a scope verdict"              "$(cat "$PROMPT")" "Do not answer \`ASSIGN\`"
has "D1 it asks the four questions the owner asked for" \
    "$(cat "$PROMPT")" "What I cannot settle myself"
has "D1 the brief reaches the manager" "$(cat "$PROMPT")" "sections/alpha/brief.md"
absent "D1 no placeholder survives composition" "$(cat "$PROMPT")" "{{"

ANALYSIS_MD="$(field "$out" analysis)"
exists "D1 the assessment is written under the section" "$ANALYSIS_MD"
has    "D1 it holds what the manager answered" "$(cat "$ANALYSIS_MD")" "Whether the venue account exists"
exists "D1 latest.md points at the most recent one" "$FLOW/demo/sections/alpha/analysis/latest.md"

printf '\n===== D1: it opens nothing =====\n'
missing "D1 no cycle directory is created"  "$FLOW/demo/sections/alpha/cycles"
eq      "D1 the cycle count stays at zero"  "$(field "$out" cycles)" "0"
missing "D1 no assignment is written"       "$FLOW/demo/sections/alpha/cycles/001/assignment.md"
eq      "D1 the section's next action is still its first scope" \
        "$("$FLOWSH" status | awk '$1 == "alpha" {print $4}')" "scope"

printf '\n===== D1: the cost is recorded like any dispatch =====\n'
has "D1 the ledger carries the analysis" \
    "$(cat "$FLOW/demo/runs/cost_ledger.tsv")" "analysis alpha"
eq  "D1 and charges it to the section" \
    "$(awk -F'\t' '$4 ~ /^analysis/ {print $2; exit}' "$FLOW/demo/runs/cost_ledger.tsv")" "alpha"

printf '\n===== D1: a focusing question reaches the manager =====\n'
: > "$STUB_LOG"
printf 'Is the parser worth keeping?\n' > "$W/q.md"
out="$(PM_FLOW_STUB="$ANALYSIS" "$FLOWSH" section-analysis alpha --file "$W/q.md" 2>&1)"
PROMPT="$(awk -F'\t' 'NR == 1 {print $3}' "$STUB_LOG")"
has "D1 the question is listed among the files to read" "$(cat "$PROMPT")" "question.md"
has "D1 and the task says to answer it first" "$(cat "$PROMPT")" "answer it first"

printf '\n===== D1: an ASSIGN answer is refused the effect it wants =====\n'
: > "$STUB_LOG"
out="$(PM_FLOW_STUB='## Where the section stands

- x

## Decision

ASSIGN write the parser' "$FLOWSH" section-analysis alpha 2>&1)"
has    "D1 the scope verdict is called out" "$out" "answered with a scope verdict"
missing "D1 and still no cycle was opened"  "$FLOW/demo/sections/alpha/cycles"

REVIEW='## What the product still lacks

A real fill.

## Completion criteria

- lib/a.py exists: MET (ls lib/a.py)

## Evidence I probed

- `ls lib/a.py` printed the file.

## Plan structure

- Unstarted dependency: CLEAR
- Unreachable section: CLEAR
- Must-have inflation: CLEAR
- Linear-chain risk: CLEAR

## Verdicts

- alpha: CONTINUE
- beta: CUT the product reaches every criterion without it

## Shortest path

- Land the acceptance check.

## Decision

ON_TRACK'

printf '\n===== D2: portfolio-review runs the review with no threshold armed =====\n'
absent "D2 nothing has armed the automatic review" "$("$FLOWSH" next)" "portfolio-review"
: > "$STUB_LOG"
out="$(PM_FLOW_STUB="$REVIEW" "$FLOWSH" portfolio-review 2>&1)"
has "D2 the review reports the product verdict" "$out" "ON_TRACK"
eq  "D2 the product officer is the role dispatched" \
    "$(awk -F'\t' 'NR == 1 {print $1}' "$STUB_LOG")" "cpo"
has "D2 the label names it a portfolio review" \
    "$(awk -F'\t' 'NR == 1 {print $2}' "$STUB_LOG")" "portfolio review"
has "D2 the prompt is the portfolio review task" \
    "$(cat "$(awk -F'\t' 'NR == 1 {print $3}' "$STUB_LOG")")" "review the portfolio against the mission"
eq  "D2 the record says it was convened by hand" \
    "$(cat "$FLOW/demo/project_state/portfolio/001/trigger.txt")" "convened by hand"

printf '\n===== D2: it is a review in every other respect =====\n'
eq     "D2 the product verdict is recorded" \
       "$(cat "$FLOW/demo/project_state/portfolio/001/decision.txt")" "ON_TRACK"
eq     "D2 a CUT verdict takes effect" \
       "$(cat "$FLOW/demo/sections/beta/status.txt")" "cancelled"
exists "D2 the portfolio log is appended" "$FLOW/demo/project_state/portfolio_log.md"
has    "D2 and carries this review's shortest path" \
       "$(cat "$FLOW/demo/project_state/portfolio_log.md")" "Land the acceptance check"

printf '\n===== D2: it advances the governance baseline =====\n'
set_config governance.portfolio_review_dispatches 1
absent "D2 the loop is not left about to convene another" "$("$FLOWSH" next)" "portfolio-review"
printf 'x\tdemo\tpm\tscope\t0.5\ty\n' >> "$FLOW/demo/runs/cost_ledger.tsv"
has    "D2 and one further dispatch arms it again" "$("$FLOWSH" next)" "portfolio-review"
set_config governance.portfolio_review_dispatches 0

printf '\n===== D3: proposals convenes the panel on a question =====\n'
: > "$STUB_LOG"
printf 'Propose three ways to structure the data branch.\n' > "$W/q.md"
out="$(PM_FLOW_STUB='## Panel assessment

Both seats read the same question.

## Selected paths

- Proposal 1: one collector per venue

## Decision

ADOPT proposal 1' "$FLOWSH" proposals "Data Branch" --file "$W/q.md" 2>&1)"
has "D3 the panel name is slugified" "$out" "panel=data-branch"
PANEL="$(field "$out" panel_dir)"
eq  "D3 one artifact per seat"       "$(field "$out" proposals)" "2"
exists "D3 seat one answered"        "$PANEL/proposal_1.md"
exists "D3 seat two answered"        "$PANEL/proposal_2.md"
exists "D3 the question is kept with the panel" "$PANEL/question.md"
exists "D3 the adjudication is written"         "$PANEL/adjudication.md"
eq  "D3 the adopted path is recorded" "$(cat "$PANEL/decision.txt")" "ADOPT"

printf '\n===== D3: the seats are consultants, the adjudicator is the officer =====\n'
eq "D3 both seats ran as consultants" \
   "$(awk -F'\t' '$1 == "consultant"' "$STUB_LOG" | wc -l | tr -d '[:space:]')" "2"
eq "D3 the product officer adjudicates last" \
   "$(awk -F'\t' 'END {print $1}' "$STUB_LOG")" "cpo"
has "D3 the seat prompt asks for proposals, not a diagnosis" \
    "$(cat "$PANEL/consultant_prompt.md")" "Give at least two proposals"
has "D3 the seats are told they are blind to each other" \
    "$(cat "$PANEL/consultant_prompt.md")" "cannot see the others"
has "D3 the seat prompt points at the question" \
    "$(cat "$PANEL/consultant_prompt.md")" "question.md"

printf '\n===== D3: the adjudication reuses the panel task =====\n'
adj="$(cat "$PANEL/adjudication_prompt.md")"
has    "D3 it is the consultant panel adjudication" "$adj" "Task: adjudicate a consultant panel"
has    "D3 it says the panel was not convened on a failure" "$adj" "not on a failure"
has    "D3 both proposals are listed for the officer" "$adj" "Proposal 2:"
has    "D3 the question is listed too" "$adj" "- Question:"
absent "D3 no placeholder survives composition" "$adj" "{{"

printf '\n===== D3: the failure panel still reads as a failure panel =====\n'
printf '# Failure history\n\nit kept failing\n' > "$W/f.md"
: > "$STUB_LOG"
out="$(PM_FLOW_STUB='## Diagnosis

x

## Decision

ALTERNATIVE' "$FLOWSH" consult-panel alpha --file "$W/f.md" 2>&1)"
panel2="$(field "$out" panel_dir)"
has "D3 the shared task still frames a failed section" \
    "$(cat "$panel2/adjudication_prompt.md")" "has failed repeatedly"

printf '\n===== D4: each command refuses while a driver holds the project =====\n'
cat > "$W/holdlock.zsh" <<'HOLD'
#!/bin/zsh -f
zmodload zsh/system
zsystem flock -f FD "$1" || exit 1
: > "$2"
while [[ -f "$2" ]]; do sleep 0.05; done
HOLD
chmod +x "$W/holdlock.zsh"
: >> "$FLOW/demo/.driver.lock"
"$W/holdlock.zsh" "$FLOW/demo/.driver.lock" "$W/held" &
holder=$!
for _ in {1..200}; do [[ -f "$W/held" ]] && break; sleep 0.05; done

held_out="$("$FLOWSH" portfolio-review 2>&1)"; held_rc=$?
has "D4 portfolio-review refuses"  "$held_out" "another pm_flow driver is already running"
eq  "D4 and exits non-zero"        "$held_rc" "1"
held_out="$("$FLOWSH" section-analysis alpha 2>&1 || true)"
has "D4 section-analysis refuses"  "$held_out" "another pm_flow driver is already running"
held_out="$("$FLOWSH" proposals held --file "$W/q.md" 2>&1 || true)"
has "D4 proposals refuses"         "$held_out" "another pm_flow driver is already running"
dispatches_while_locked="$(awk -F'\t' '$2 ~ /^(analysis|portfolio review|proposals)/' "$STUB_LOG" | wc -l | tr -d '[:space:]')"
eq  "D4 no dispatch was spent behind the lock" "$dispatches_while_locked" "0"

rm -f "$W/held"
wait "$holder" 2>/dev/null || true

printf '\n===== D4: the lock is released, so the commands work again =====\n'
: > "$STUB_LOG"
out="$(PM_FLOW_STUB="$ANALYSIS" "$FLOWSH" section-analysis alpha 2>&1)"
has "D4 section-analysis runs once the driver is gone" "$out" "recorded=section-analysis"

printf '\n===== D5: init-section with a request has the officer cut the section =====\n'
PROPOSAL='## Assessment

The plan asks for a recording layer; nothing live owns an exporter. Probe:
`ls src` shows no trace module.

## Section: theta

### Objective
- Ship recorded spans to a backend with one command.

### Current baseline
- Spans are recorded; nothing exports them.

### Deliverables
- `pm-flow trace export`.

### User-visible scenarios
1. `pm-flow trace export --file out.json` writes OTLP JSON.

### Interfaces produced
- The `trace` command.

### Interfaces consumed
- The spans table.

### Scope
- In: export. Out: recording.

### Non-goals
- A vendor default.

### Priority
- must-have: a record nobody can open is not a record.

### Owned paths
- `export/**`

### Dependencies
- None.

### Constraints and fixed decisions
- None.

### Acceptance
- A1: `pm-flow trace export --file out.json` exits 0 and the file parses as OTLP JSON.

### Rejection conditions
- A vendor endpoint is defaulted.

### Open questions
- None.

## Decision

CUT - serves the plan bullet on backend-readable traces'
printf 'Runs should be exportable to a backend with one command.\n' > "$W/req.md"
: > "$STUB_LOG"
out="$(PM_FLOW_STUB="$PROPOSAL" "$FLOWSH" init-section theta --file "$W/req.md" 2>&1)"
has    "D5 the officer is dispatched once"        "$(cat "$STUB_LOG")" "cpo	propose section theta"
eq     "D5 exactly one dispatch is spent"         "$(grep -c . "$STUB_LOG")" "1"
has    "D5 the decision is reported"              "$out" "init-section theta -> CUT"
if [[ -f "$FLOW/demo/sections/theta/brief.md" ]]; then ok "D5 the section exists"; else bad "D5 the section exists" "$out"; fi
has    "D5 the brief is the officer's, in full shape" "$(cat "$FLOW/demo/sections/theta/brief.md")" "### Deliverables"
has    "D5 acceptance carries its ID"             "$(cat "$FLOW/demo/sections/theta/brief.md")" "A1:"
eq     "D5 owned paths come from the brief"       "$(cat "$FLOW/demo/sections/theta/owned_paths.txt")" "export/**"
has    "D5 the request is kept with the proposal" "$(cat "$FLOW"/demo/project_state/proposals/*-theta/request.md)" "exportable"
has    "D5 the proposal prompt names the live owners" "$(cat "$FLOW"/demo/project_state/proposals/*-theta/prompt.md)" '`lib/` (alpha)'
absent "D5 no placeholder survives composition"   "$(cat "$FLOW"/demo/project_state/proposals/*-theta/prompt.md)" "{{"

printf '\n===== D5: a DECLINE creates nothing =====\n'
DECLINED='## Assessment

Covered by theta.

## Section block

Not applicable.

## Decision

DECLINE - theta already owns export'
out="$(PM_FLOW_STUB="$DECLINED" "$FLOWSH" init-section iota --file "$W/req.md" 2>&1)"
has "D5 the decline is reported" "$out" "init-section iota -> DECLINE"
if [[ ! -d "$FLOW/demo/sections/iota" ]]; then ok "D5 no section was created"; else bad "D5 no section was created" "iota exists"; fi

printf '\n===== D5: a block under another name is refused =====\n'
out="$(PM_FLOW_STUB="$PROPOSAL" "$FLOWSH" init-section kappa --file "$W/req.md" 2>&1 || true)"
has "D5 the mismatch is named" "$out" "named its section 'theta'"
if [[ ! -d "$FLOW/demo/sections/kappa" ]]; then ok "D5 nothing was created for kappa"; else bad "D5 nothing was created for kappa" "exists"; fi

printf '\ntotals: pass=%d fail=%d\n' "$pass" "$failn"
[[ "$failn" == 0 ]]
