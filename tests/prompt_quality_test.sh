#!/bin/zsh -f
set -euo pipefail

# --- no inherited selector may reach the fixture -----------------------------
#
# A pm-flow run that dispatches this suite exports PM_FLOW_PROJECT and
# PM_FLOW_REPO_ROOT. Inherited, the driver under test honours them and writes
# its synthetic sections into the *caller's* live project instead of the work
# directory below. That is not hypothetical: portfolio review 002 found six
# fixture sections (alpha delta epsilon eta gamma zeta) and six run directories
# in the live `pm-agent` project, put there by this code path.
#
# The suites set PM_FLOW_STUB and PM_FLOW_SECTION themselves, per command, so
# clearing the whole namespace here costs them nothing.
for name in ${(k)parameters[(I)PM_FLOW_*]}; do
  unset "$name"
done

REPO_ROOT="$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)"
AUDITOR="$REPO_ROOT/template/.agentic/pm_flow/prompt_quality.py"
QA_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pm-flow-prompt-quality.XXXXXX")"
trap 'rm -rf -- "$QA_ROOT"' EXIT HUP INT TERM

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

cat > "$QA_ROOT/good.md" <<'EOF'
<!-- pm-flow-prompt version=2 role=pm phase=section_scope commit_owner=driver -->

# Project Manager

You manage one section. The brief is the outcome contract and the state is an
evidence ledger. The driver commits accepted implementation work.

# Task: scope the next assignment

Read `brief.md`, `workplan.md`, and `state.md`. Select one task with concrete
writable paths, acceptance IDs, and a validation command. State the expected
observation and rejection conditions. Return a Workplan task heading and one
decision. Do not broaden the brief or combine tasks. A complete section has
evidence for every acceptance ID and its end-to-end scenario.
EOF

python3 "$AUDITOR" audit --strict --manifest "$QA_ROOT/good.manifest.json" \
  "$QA_ROOT/good.md" >/dev/null || fail "a bounded prompt was rejected"
python3 - "$QA_ROOT/good.manifest.json" <<'PY' || fail "manifest metrics are missing"
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
assert data["runtime"]["commit_owner"] == "driver"
assert data["metrics"]["task_ratio"] >= 0.35
assert data["findings"] == []
PY
printf 'PASS: a bounded prompt produces a clean manifest\n'

cat > "$QA_ROOT/contradictory.md" <<'EOF'
<!-- pm-flow-prompt version=2 role=pm phase=section_scope commit_owner=driver -->

# Project Manager

You must commit after every accepted result. You share a model family with the
developer. This used to be handled differently.

# Task: scope the next assignment

The history above includes every previous result. Read `{{CONTEXT_FILES}}`,
`workplan.md`, acceptance IDs, validation commands, and writable paths.
EOF

if python3 "$AUDITOR" audit "$QA_ROOT/contradictory.md" > "$QA_ROOT/bad.out" 2>&1; then
  fail "contradictory prompt passed"
fi
for code in unresolved-placeholder commit-owner-contradiction every-history \
    model-family-assumption historical-incident; do
  grep -q "$code" "$QA_ROOT/bad.out" || fail "missing finding $code"
done
printf 'PASS: contradictions, incident leakage, and placeholders fail closed\n'

cat > "$QA_ROOT/duplicated.md" <<'EOF'
<!-- pm-flow-prompt version=2 role=consultant phase=example commit_owner=none -->

This paragraph is deliberately long enough to count and it repeats the exact
same process instruction without adding any task information for the reader.

This paragraph is deliberately long enough to count and it repeats the exact
same process instruction without adding any task information for the reader.
EOF

if python3 "$AUDITOR" audit --strict "$QA_ROOT/duplicated.md" > "$QA_ROOT/duplicate.out" 2>&1; then
  fail "strict mode accepted duplicated prose"
fi
grep -q duplicate-prose "$QA_ROOT/duplicate.out" || fail "duplication was not reported"
printf 'PASS: strict mode treats duplicated prose as drift\n'

# The shipped prompts, as the engine actually composes and dispatches them.
# The fixtures above prove the rules; this proves the templates obey them. The
# stub suite drives every section phase without model spend and leaves each
# generated prompt beside its manifest, so the audit runs on the exact text a
# role would receive.
GENERATED="$QA_ROOT/generated"
zsh "$REPO_ROOT/template/.agentic/pm_flow/tests/transitions.zsh" "$GENERATED/transitions" \
  > "$QA_ROOT/transitions.log" 2>&1 || fail "the transitions suite failed:
$(tail -n 20 "$QA_ROOT/transitions.log")"
zsh "$REPO_ROOT/template/.agentic/pm_flow/tests/on_demand.zsh" "$GENERATED/on_demand" \
  > "$QA_ROOT/on_demand.log" 2>&1 || fail "the on_demand suite failed:
$(tail -n 20 "$QA_ROOT/on_demand.log")"
zsh "$REPO_ROOT/template/.agentic/pm_flow/tests/recovery.zsh" "$GENERATED/recovery" \
  > "$QA_ROOT/recovery.log" 2>&1 || fail "the recovery suite failed:
$(tail -n 20 "$QA_ROOT/recovery.log")"
generated_prompts=("${(@f)$(find "$GENERATED" -name '*_prompt.md' -o -name 'prompt.md' | sort)}")
(( ${#generated_prompts[@]} >= 6 )) || fail "the stub suites generated too few prompts to audit"
for phase in scope develop review handoff consultant adjudication analysis; do
  printf '%s\n' "${generated_prompts[@]}" | grep -q "$phase" || \
    fail "no generated $phase prompt to audit"
done
if ! python3 "$AUDITOR" audit --strict "${generated_prompts[@]}" > "$QA_ROOT/generated.out" 2>&1; then
  fail "a shipped prompt, as composed, fails the strict audit:
$(grep -v '^PASS' "$QA_ROOT/generated.out")"
fi
printf 'PASS: every composed shipped prompt (%d) is clean under strict audit\n' "${#generated_prompts[@]}"
