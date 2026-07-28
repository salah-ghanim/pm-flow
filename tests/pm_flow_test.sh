#!/bin/zsh -f
set -euo pipefail
unsetopt BG_NICE

REPO_ROOT="$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pm-flow-test.XXXXXX")"
TEST_ROOT="$(cd -P "$TEST_ROOT" && pwd -P)"
case "$TEST_ROOT" in
  */pm-flow-test.*) ;;
  *) printf 'unsafe test temp directory: %s\n' "$TEST_ROOT" >&2; exit 1 ;;
esac

cleanup() {
  if [[ -n "${TEST_ROOT:-}" && -d "$TEST_ROOT" && "$(basename "$TEST_ROOT")" == pm-flow-test.* ]]; then
    rm -rf -- "$TEST_ROOT"
  fi
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local value="$1"
  local expected="$2"
  local label="$3"
  [[ "$value" == *"$expected"* ]] || fail "$label: expected to find '$expected'"
}

assert_not_contains() {
  local value="$1"
  local unexpected="$2"
  local label="$3"
  [[ "$value" != *"$unexpected"* ]] || fail "$label: did not expect '$unexpected'"
}

assert_file_contains() {
  local path="$1"
  local expected="$2"
  local label="$3"
  [[ -f "$path" ]] || fail "$label: missing file $path"
  assert_contains "$(/bin/cat "$path")" "$expected" "$label"
}

output_value() {
  local output="$1"
  local key="$2"
  printf '%s\n' "$output" | awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}'
}

write_step_response() {
  local path="$1"
  local session_id="$2"
  local backend="${3:-claude}"
  local resumable="${4:-true}"
  {
    printf '{\n'
    printf '  "is_error": false,\n'
    printf '  "result": "Assessment\\nAligned.\\n\\nDrift review\\nNo drift.\\n\\nRisks\\nLow.\\n\\nImprovements\\nKeep scope bounded.\\n\\nDecision\\nGO\\n\\nNext action\\nUse a fresh developer.",\n'
    printf '  "session_id": "%s",\n' "$session_id"
    printf '  "session_resumable": %s,\n' "$resumable"
    printf '  "pm_backend": "%s"\n' "$backend"
    printf '}\n'
  } > "$path"
}

write_completion_response() {
  local path="$1"
  local session_id="$2"
  local decision="${3:-DONE}"
  {
    printf '{\n'
    printf '  "is_error": false,\n'
    printf '  "result": "Outcome assessment\\nValidated.\\n\\nDrift review\\nNo drift.\\n\\nExpected vs observed\\nMatched.\\n\\nFeedback\\nReady.\\n\\nRecommended next steps\\nPublish the bounded handoff.\\n\\nDecision\\n%s",\n' "$decision"
    printf '  "session_id": "%s",\n' "$session_id"
    printf '  "session_resumable": true,\n'
    printf '  "pm_backend": "claude"\n'
    printf '}\n'
  } > "$path"
}

expect_failure() {
  local label="$1"
  shift
  if "$@" > "$TEST_ROOT/expected-failure.log" 2>&1; then
    fail "$label: command unexpectedly succeeded"
  fi
}

FIXTURE_REPO="$TEST_ROOT/fixture repo"
mkdir "$FIXTURE_REPO"
printf '# Existing repository rules\n\n- Preserve this custom rule.\n' > "$FIXTURE_REPO/CLAUDE.md"
"$REPO_ROOT/install.sh" "$FIXTURE_REPO" --name "Fixture Project" > "$TEST_ROOT/install.out"

PM="$FIXTURE_REPO/agentic/pm_flow/pm_flow.sh"
PROJECT_DIR="$FIXTURE_REPO/agentic/pm_flow/fixture-repo"

[[ -x "$PM" ]] || fail "installer did not create executable pm_flow.sh"
assert_file_contains \
  "$FIXTURE_REPO/CLAUDE.md" \
  "agentic/pm_flow/fixture-repo/project_state/start.md" \
  "installer renders the actual project key"
assert_file_contains "$FIXTURE_REPO/CLAUDE.md" "Preserve this custom rule." "installer preserves existing CLAUDE rules"
assert_file_contains "$FIXTURE_REPO/CLAUDE.md" "<!-- pm-flow:begin -->" "installer activates managed CLAUDE rules"
assert_file_contains "$FIXTURE_REPO/CLAUDE.md" "Identify your role before acting" "managed rules route by role"
assert_not_contains \
  "$(/bin/cat "$FIXTURE_REPO/CLAUDE.md")" \
  "Create independently owned sections with" \
  "managed rules do not give every agent coordinator instructions"
assert_file_contains "$FIXTURE_REPO/CLAUDE.pre-pm-flow.md" "Preserve this custom rule." "installer backs up CLAUDE rules"

alpha_output="$("$PM" init-section alpha <<'EOF'
## Objective

- Implement alpha.

## Scope

- Alpha implementation and its focused tests.

## Owned paths

- `src/alpha/**`

## Dependencies

- None.

## Acceptance

- Alpha tests pass.

## Rejection conditions

- Any change outside the owned paths.
EOF
)"
beta_output="$("$PM" init-section beta <<'EOF'
## Objective

- Implement beta.

## Scope

- Beta implementation and its focused tests.

## Owned paths

- `src/beta/**`

## Dependencies

- alpha

## Acceptance

- Beta tests pass.

## Rejection conditions

- Any change outside the owned paths.
EOF
)"

alpha_run="$(output_value "$alpha_output" run_dir)"
beta_run="$(output_value "$beta_output" run_dir)"
[[ -d "$alpha_run" ]] || fail "alpha run was not created"
[[ -d "$beta_run" ]] || fail "beta run was not created"
[[ "$alpha_run" != "$beta_run" ]] || fail "sections share a run"

sections_output="$("$PM" list-sections)"
assert_contains "$sections_output" "| alpha | planned |" "alpha registry row"
assert_contains "$sections_output" "| beta | planned |" "beta registry row"
assert_contains "$sections_output" "[handoff](../sections/alpha/handoff.md)" "registry handoff link"
assert_file_contains \
  "$PROJECT_DIR/sections/alpha/pm_prompt.md" \
  "Spawn a fresh developer sub-agent for every assignment" \
  "section PM delegation prompt"
assert_file_contains \
  "$PROJECT_DIR/sections/alpha/pm_prompt.md" \
  "Do not load its full transcript" \
  "section PM context boundary"
assert_file_contains \
  "$PROJECT_DIR/sections/alpha/pm_prompt.md" \
  "without inherited root conversation history" \
  "section PM no-history launch"
assert_not_contains \
  "$(/bin/cat "$PROJECT_DIR/sections/alpha/pm_prompt.md")" \
  'In Codex collaboration, use' \
  "section PM prompt states the requirement, not one host's mechanism"
assert_file_contains "$PROJECT_DIR/sections/alpha/owned_paths.txt" "src/alpha/**" "owned paths are persisted"
assert_file_contains \
  "$PROJECT_DIR/sections/beta/dependency_handoffs.txt" \
  "agentic/pm_flow/fixture-repo/sections/alpha/handoff.md" \
  "dependency handoff allowlist"

{
  printf '## Objective\n\n- Invalid section.\n'
} > "$TEST_ROOT/invalid-section.md"
expect_failure \
  "incomplete section brief" \
  "$PM" init-section invalid --file "$TEST_ROOT/invalid-section.md"
assert_file_contains "$TEST_ROOT/expected-failure.log" "section Scope heading" "section contract validation"

{
  printf '## Objective\n\n- Overlap alpha.\n\n'
  printf '## Scope\n\n- Nested alpha work.\n\n'
  printf '## Owned paths\n\n- `src/alpha/internal/**`\n\n'
  printf '## Dependencies\n\n- None.\n\n'
  printf '## Acceptance\n\n- Tests pass.\n\n'
  printf '## Rejection conditions\n\n- Scope drift.\n'
} > "$TEST_ROOT/overlap-section.md"
expect_failure \
  "overlapping section ownership" \
  "$PM" init-section overlap --file "$TEST_ROOT/overlap-section.md"
assert_file_contains "$TEST_ROOT/expected-failure.log" "owned paths overlap" "owned path isolation"

{
  printf 'Proposed change:\n- Implement the bounded assignment.\n\n'
  printf 'Validation:\n- Run focused tests.\n'
} > "$TEST_ROOT/developer-report.md"

alpha_prepare="$("$PM" --section alpha prepare-step current first --file "$TEST_ROOT/developer-report.md")"
beta_prepare="$("$PM" --section beta prepare-step current first --file "$TEST_ROOT/developer-report.md")"
alpha_pending="$(output_value "$alpha_prepare" pending_dir)"
beta_pending="$(output_value "$beta_prepare" pending_dir)"

assert_not_contains "$(/bin/cat "$alpha_pending/command.txt")" "--resume" "alpha first PM call"
assert_not_contains "$(/bin/cat "$beta_pending/command.txt")" "--resume" "beta first PM call"
assert_file_contains "$alpha_pending/prompt.md" "sections/alpha/state.md" "alpha prompt scope"
assert_not_contains "$(/bin/cat "$alpha_pending/prompt.md")" "sections/beta/state.md" "alpha prompt excludes beta"
assert_file_contains "$alpha_pending/command.txt" "claim-execution" "generated command claims exactly-once execution"
assert_file_contains "$alpha_pending/command.txt" "prompt.md" "generated command sends the structured prompt file"
assert_not_contains \
  "$(/bin/cat "$alpha_pending/command.txt")" \
  "Respond\\ with" \
  "generated command does not inline a flattened prompt"
assert_file_contains "$alpha_pending/prompt.md" "1. Assessment" "structured prompt keeps its section list"
[[ "$(/bin/cat "$alpha_pending/prompt.md" | wc -l | tr -d '[:space:]')" -gt 5 ]] || \
  fail "prompt.md was flattened to a single line"
assert_file_contains \
  "$beta_pending/context_files.json" \
  "dependencies/alpha-handoff.md" \
  "dependency handoff snapshot is included in bounded review context"
assert_file_contains \
  "$beta_pending/dependencies/alpha-handoff.md" \
  "Section initialized; no implementation outcome yet." \
  "dependency context is frozen when the review is prepared"

write_step_response "$alpha_pending/response.json" "alpha-session-1"
"$PM" claim-execution "$alpha_pending" > "$TEST_ROOT/claim-alpha.out"
"$PM" record-step "$alpha_pending" > "$TEST_ROOT/record-alpha.out"

alpha_second="$("$PM" --section alpha prepare-step current second --file "$TEST_ROOT/developer-report.md")"
alpha_second_pending="$(output_value "$alpha_second" pending_dir)"
assert_contains "$(/bin/cat "$alpha_second_pending/command.txt")" "--resume alpha-session-1" "alpha resumes its PM"
assert_not_contains "$(/bin/cat "$beta_pending/command.txt")" "alpha-session-1" "beta does not share alpha PM"

"$PM" claim-execution "$alpha_second_pending" > "$TEST_ROOT/claim-alpha-second.out"
write_step_response "$alpha_second_pending/response.json" "alpha-session-1"
: >> "$alpha_run/.record.lock"
zsh -fc "zmodload zsh/system; zsystem flock -f held '$alpha_run/.record.lock'; sleep 6" &
lock_holder_pid=$!
sleep 1
PM_FLOW_LOCK_WAIT=2 expect_failure "same-section record lock" "$PM" record-step "$alpha_second_pending"
assert_file_contains "$TEST_ROOT/expected-failure.log" "waiting for .record.lock" "record lock error"
kill "$lock_holder_pid" 2>/dev/null || true
wait "$lock_holder_pid" 2>/dev/null || true
"$PM" record-step "$alpha_second_pending" > "$TEST_ROOT/record-alpha-second.out"

alpha_parallel_one="$("$PM" --section alpha prepare-step current parallel-one --file "$TEST_ROOT/developer-report.md")"
alpha_parallel_one_dir="$(output_value "$alpha_parallel_one" pending_dir)"
pending_count_before_rejection="$(ls -d "$alpha_run"/pending/*/ | wc -l | tr -d '[:space:]')"
expect_failure \
  "parallel same-section prepare" \
  "$PM" --section alpha prepare-step current parallel-two --file "$TEST_ROOT/developer-report.md"
assert_file_contains "$TEST_ROOT/expected-failure.log" "active pending review" "same-section pending serialization"
pending_count_after_rejection="$(ls -d "$alpha_run"/pending/*/ | wc -l | tr -d '[:space:]')"
[[ "$pending_count_before_rejection" == "$pending_count_after_rejection" ]] || \
  fail "rejected prepare left an orphan pending directory"
write_step_response "$alpha_parallel_one_dir/response.json" "alpha-session-1"
"$PM" claim-execution "$alpha_parallel_one_dir" > "$TEST_ROOT/claim-alpha-parallel.out"
"$PM" record-step "$alpha_parallel_one_dir" > "$TEST_ROOT/record-alpha-parallel.out"
expect_failure "duplicate same-section response" "$PM" record-step "$alpha_parallel_one_dir"
assert_file_contains "$TEST_ROOT/expected-failure.log" "not the active review" "duplicate response error"

alpha_justified="$("$PM" --section alpha prepare-step current justified --file "$TEST_ROOT/developer-report.md")"
alpha_justified_dir="$(output_value "$alpha_justified" pending_dir)"
{
  printf '{\n'
  printf '  "is_error": false,\n'
  printf '  "result": "## Assessment\\nAligned.\\n\\n## Drift review\\nNo drift.\\n\\n## Risks\\nLow.\\n\\n## Improvements\\nNarrow the scope.\\n\\n## Decision\\nGO_WITH_CHANGES - narrow the scope to the owned paths first.\\n\\n## Next action\\nUse a fresh developer.",\n'
  printf '  "session_id": "alpha-session-1",\n'
  printf '  "session_resumable": true,\n'
  printf '  "pm_backend": "claude"\n'
  printf '}\n'
} > "$alpha_justified_dir/response.json"
"$PM" claim-execution "$alpha_justified_dir" > "$TEST_ROOT/claim-alpha-justified.out"
"$PM" record-step "$alpha_justified_dir" > "$TEST_ROOT/record-alpha-justified.out"

write_step_response "$beta_pending/response.json" "beta-session-1"
"$PM" claim-execution "$beta_pending" > "$TEST_ROOT/claim-beta.out"
"$PM" record-step "$beta_pending" > "$TEST_ROOT/record-beta.out"
beta_fallback="$("$PM" --section beta prepare-step current fallback --file "$TEST_ROOT/developer-report.md")"
beta_fallback_dir="$(output_value "$beta_fallback" pending_dir)"
assert_contains "$(/bin/cat "$beta_fallback_dir/command.txt")" "--resume beta-session-1" "beta resumes before fallback"
write_step_response "$beta_fallback_dir/response.json" "" "codex" "false"
"$PM" claim-execution "$beta_fallback_dir" > "$TEST_ROOT/claim-beta-fallback.out"
"$PM" record-step "$beta_fallback_dir" > "$TEST_ROOT/record-beta-fallback.out"
beta_after_fallback="$("$PM" --section beta prepare-step current after-fallback --file "$TEST_ROOT/developer-report.md")"
beta_after_fallback_dir="$(output_value "$beta_after_fallback" pending_dir)"
assert_not_contains "$(/bin/cat "$beta_after_fallback_dir/command.txt")" "--resume" "stateless fallback clears resume"

alpha_after_beta="$("$PM" --section alpha prepare-step current after-beta --file "$TEST_ROOT/developer-report.md")"
alpha_after_beta_dir="$(output_value "$alpha_after_beta" pending_dir)"
assert_contains "$(/bin/cat "$alpha_after_beta_dir/command.txt")" "--resume alpha-session-1" "beta changes do not affect alpha"

{
  printf '## Outcome\n\n- Alpha behavior is validated.\n\n'
  printf '## Decisions\n\n- Kept the bounded implementation.\n\n'
  printf '## Interfaces\n\n- Exposes the alpha interface.\n\n'
  printf '## Risks\n\n- None open.\n\n'
  printf '## Next action\n\n- Integrate from the root coordinator.\n'
} > "$TEST_ROOT/handoff.md"
expect_failure \
  "done while review active" \
  "$PM" section-handoff alpha done "Alpha validated and ready to integrate" --file "$TEST_ROOT/handoff.md"
assert_file_contains "$TEST_ROOT/expected-failure.log" "active pending review" "done rejects in-flight PM work"
"$PM" claim-execution "$alpha_after_beta_dir" > "$TEST_ROOT/claim-alpha-cancel.out"
cancel_output="$("$PM" cancel-pending "$alpha_after_beta_dir" "simulated aborted PM invocation")"
assert_contains "$cancel_output" "session_rotated=1" "claimed cancellation rotates uncertain session"
expect_failure \
  "done without PM completion" \
  "$PM" section-handoff alpha done "Alpha validated and ready to integrate" --file "$TEST_ROOT/handoff.md"
assert_file_contains "$TEST_ROOT/expected-failure.log" "completion review" "done requires PM completion"

alpha_complete="$("$PM" --section alpha prepare-complete current --file "$TEST_ROOT/developer-report.md")"
alpha_complete_dir="$(output_value "$alpha_complete" pending_dir)"
assert_not_contains "$(/bin/cat "$alpha_complete_dir/command.txt")" "--resume" "cancelled claimed call resets PM session"
write_completion_response "$alpha_complete_dir/response.json" "alpha-completion-session" "DONE"
"$PM" claim-execution "$alpha_complete_dir" > "$TEST_ROOT/claim-alpha-complete.out"
expect_failure "completion pending recorded as step" "$PM" record-step "$alpha_complete_dir"
assert_file_contains "$TEST_ROOT/expected-failure.log" "pending step review" "pending review kind is enforced"
"$PM" record-complete "$alpha_complete_dir" > "$TEST_ROOT/record-alpha-complete.out"
"$PM" section-handoff alpha done "Alpha validated and ready to integrate" --file "$TEST_ROOT/handoff.md" > "$TEST_ROOT/handoff.out"
sections_output="$("$PM" list-sections)"
assert_contains "$sections_output" "| alpha | done | Alpha validated and ready to integrate |" "done handoff updates registry"
expect_failure \
  "terminal section PM work" \
  "$PM" --section alpha prepare-step current post-done --file "$TEST_ROOT/developer-report.md"
assert_file_contains "$TEST_ROOT/expected-failure.log" "publish an active or planned handoff" "terminal section is not silently reopened"
{
  printf '## Objective\n\n- Replace completed alpha ownership.\n\n'
  printf '## Scope\n\n- Follow-up alpha implementation.\n\n'
  printf '## Owned paths\n\n- `src/alpha/**`\n\n'
  printf '## Dependencies\n\n- None.\n\n'
  printf '## Acceptance\n\n- Replacement tests pass.\n\n'
  printf '## Rejection conditions\n\n- Scope drift.\n'
} > "$TEST_ROOT/reassigned-section.md"
"$PM" init-section alpha-replacement --file "$TEST_ROOT/reassigned-section.md" > "$TEST_ROOT/reassigned-init.out"
expect_failure \
  "reopen section with reassigned ownership" \
  "$PM" section-handoff alpha active "Attempting conflicting reopen" --file "$TEST_ROOT/handoff.md"
assert_file_contains "$TEST_ROOT/expected-failure.log" "owned paths overlap" "reopen revalidates path ownership"

{
  printf '## Outcome\n\n'
  for _word in {1..501}; do printf 'word '; done
  printf '\n\n## Decisions\n\n- None.\n\n'
  printf '## Interfaces\n\n- None.\n\n'
  printf '## Risks\n\n- None.\n\n'
  printf '## Next action\n\n- None.\n'
} > "$TEST_ROOT/oversized-handoff.md"
expect_failure \
  "oversized handoff" \
  "$PM" section-handoff beta active "Too much context" --file "$TEST_ROOT/oversized-handoff.md"
assert_file_contains "$TEST_ROOT/expected-failure.log" "500-word context budget" "handoff budget error"

{
  printf '## Outcome\n\n'
  for _byte in {1..8200}; do printf 'x'; done
  printf '\n\n## Decisions\n\n- None.\n\n'
  printf '## Interfaces\n\n- None.\n\n'
  printf '## Risks\n\n- None.\n\n'
  printf '## Next action\n\n- None.\n'
} > "$TEST_ROOT/oversized-byte-handoff.md"
expect_failure \
  "oversized byte handoff" \
  "$PM" section-handoff beta active "Unbroken context payload" --file "$TEST_ROOT/oversized-byte-handoff.md"
assert_file_contains "$TEST_ROOT/expected-failure.log" "8192-byte context budget" "handoff byte budget error"

handoff_before="$(/bin/cat "$PROJECT_DIR/sections/alpha/handoff.md")"
printf '\nPreserve this project plan marker.\n' >> "$PROJECT_DIR/project_state/plan.md"
{
  printf '# Project start prompt\n\n'
  printf 'Legacy coordinator instructions that must be backed up during migration.\n'
} > "$PROJECT_DIR/project_state/start.md"
"$REPO_ROOT/install.sh" "$FIXTURE_REPO" --name "Fixture Project" > "$TEST_ROOT/reinstall.out"
handoff_after="$(/bin/cat "$PROJECT_DIR/sections/alpha/handoff.md")"
[[ "$handoff_before" == "$handoff_after" ]] || fail "reinstall overwrote section handoff"
assert_file_contains "$PROJECT_DIR/sections/alpha/status.txt" "done" "reinstall preserves section status"
assert_file_contains "$PROJECT_DIR/project_state/plan.md" "Preserve this project plan marker." "reinstall preserves project plan"
assert_file_contains "$PROJECT_DIR/project_state/start.md" "# Project coordinator start prompt" "reinstall refreshes coordinator prompt"
assert_file_contains \
  "$PROJECT_DIR/project_state/start.pre-sections.md" \
  "Legacy coordinator instructions" \
  "reinstall backs up legacy coordinator prompt"

legacy_run="$(printf 'Legacy task brief.\n' | "$PM" init legacy-task)"
[[ -d "$legacy_run" ]] || fail "legacy init compatibility failed"
rm "$legacy_run/meta.json"
legacy_meta_injection_marker="$TEST_ROOT/unsafe-run-metadata-was-executed"
{
  printf 'RUN_DIR=$(touch %s)\n' "$legacy_meta_injection_marker"
  printf 'TASK_NAME=%q\n' "legacy-task"
  printf 'TASK_SLUG=%q\n' "legacy-task"
  printf 'SECTION_KEY=%q\n' ""
  printf 'SECTION_NAME=%q\n' ""
  printf 'SESSION_ID=%q\n' ""
  printf 'SESSION_STARTED=%q\n' "0"
  printf 'SESSION_REVISION=%q\n' "0"
  printf 'CREATED_AT_UTC=%q\n' "2026-01-01T00:00:00Z"
} > "$legacy_run/meta.env"
legacy_current="$("$PM" current-run)"
assert_contains "$legacy_current" "$legacy_run" "legacy current-run compatibility"

legacy_prepare="$("$PM" prepare-step "$legacy_run" legacy-upgrade --file "$TEST_ROOT/developer-report.md")"
[[ ! -e "$legacy_meta_injection_marker" ]] || fail "legacy run metadata was executed as shell code"
legacy_pending="$(output_value "$legacy_prepare" pending_dir)"
rm "$legacy_run/.active-pending/path.txt"
rmdir "$legacy_run/.active-pending"
rm "$legacy_pending/pending.json"
legacy_injection_marker="$TEST_ROOT/unsafe-metadata-was-executed"
{
  printf 'RUN_DIR=$(touch %s)\n' "$legacy_injection_marker"
  printf 'KIND=%q\n' "step"
  printf 'LABEL=%q\n' "legacy-upgrade"
  printf 'MODE_FLAG=%q\n' "start"
  printf 'SECTION_KEY=%q\n' ""
} > "$legacy_pending/pending.env"
expect_failure "legacy pending requires adoption" "$PM" record-step "$legacy_pending"
assert_file_contains "$TEST_ROOT/expected-failure.log" "adopt-pending" "legacy migration guidance"
adopt_output="$("$PM" adopt-pending "$legacy_pending")"
[[ ! -e "$legacy_injection_marker" ]] || fail "legacy metadata was executed as shell code"
assert_contains "$adopt_output" "response_already_executed=0" "unexecuted legacy review is adopted safely"
assert_file_contains "$legacy_pending/pending.json" '"version": 2' "legacy pending schema upgraded"
assert_file_contains "$legacy_pending/command.txt" "claim-execution" "legacy command regenerated with execution claim"
"$PM" claim-execution "$legacy_pending" > "$TEST_ROOT/claim-legacy.out"
write_step_response "$legacy_pending/response.json" "legacy-session-1"
"$PM" record-step "$legacy_pending" > "$TEST_ROOT/record-legacy.out"

(
  printf 'Parallel legacy brief one.\n' | "$PM" init same-legacy-task > "$TEST_ROOT/parallel-init-one.out"
) &
parallel_init_one_pid=$!
(
  printf 'Parallel legacy brief two.\n' | "$PM" init same-legacy-task > "$TEST_ROOT/parallel-init-two.out"
) &
parallel_init_two_pid=$!
wait "$parallel_init_one_pid"
wait "$parallel_init_two_pid"
parallel_run_one="$(/bin/cat "$TEST_ROOT/parallel-init-one.out")"
parallel_run_two="$(/bin/cat "$TEST_ROOT/parallel-init-two.out")"
[[ "$parallel_run_one" != "$parallel_run_two" ]] || fail "parallel legacy init reused one run directory"
[[ -d "$parallel_run_one" && -d "$parallel_run_two" ]] || fail "parallel legacy init did not create both runs"

readme_before_failed_upgrade="$(/bin/cat "$FIXTURE_REPO/agentic/pm_flow/README.md")"
pm_script_before_failed_upgrade="$(/bin/cat "$FIXTURE_REPO/agentic/pm_flow/pm_flow.sh")"
partial_remote_source="$TEST_ROOT/partial-remote"
mkdir "$partial_remote_source"
cp -R "$REPO_ROOT/template" "$partial_remote_source/template"
rm "$partial_remote_source/template/CLAUDE.md"
expect_failure \
  "late failed remote upgrade" \
  "$REPO_ROOT/install.sh" \
  "$FIXTURE_REPO" \
  --name "Fixture Project" \
  --repo-raw-base "file://$partial_remote_source"
readme_after_failed_upgrade="$(/bin/cat "$FIXTURE_REPO/agentic/pm_flow/README.md")"
pm_script_after_failed_upgrade="$(/bin/cat "$FIXTURE_REPO/agentic/pm_flow/pm_flow.sh")"
[[ "$readme_before_failed_upgrade" == "$readme_after_failed_upgrade" ]] || \
  fail "failed template fetch truncated a live installed file"
[[ "$pm_script_before_failed_upgrade" == "$pm_script_after_failed_upgrade" ]] || \
  fail "late template fetch failure partially upgraded installed scripts"

assert_file_contains \
  "$FIXTURE_REPO/agentic/pm_flow/codex_pm_review.sh" \
  '"session_resumable": False' \
  "Codex fallback marks responses stateless"

mkdir "$TEST_ROOT/fake-bin"
{
  printf '#!/bin/zsh -f\n'
  printf 'set -euo pipefail\n'
  printf 'out_file=""\n'
  printf 'last_arg=""\n'
  printf 'while [[ $# -gt 0 ]]; do\n'
  printf '  if [[ "$1" == "-o" ]]; then out_file="$2"; shift 2; continue; fi\n'
  printf '  last_arg="$1"\n'
  printf '  shift\n'
  printf 'done\n'
  printf 'printf "%%s\\n" "$last_arg" > "$FAKE_CODEX_CAPTURE"\n'
  printf 'printf "Assessment from fake Codex.\\n" > "$out_file"\n'
} > "$TEST_ROOT/fake-bin/codex"
chmod +x "$TEST_ROOT/fake-bin/codex"
if ! FAKE_CODEX_CAPTURE="$TEST_ROOT/codex-prompt.txt" \
    PATH="$TEST_ROOT/fake-bin:$PATH" \
    zsh -f "$FIXTURE_REPO/agentic/pm_flow/codex_pm_review.sh" "$beta_after_fallback_dir" \
    > "$TEST_ROOT/codex-fallback.out" 2>&1; then
  /bin/cat "$TEST_ROOT/codex-fallback.out" >&2
  fail "Codex fallback execution"
fi
assert_file_contains "$TEST_ROOT/codex-prompt.txt" "## Objective" "fallback inlines section brief in spaced path"
assert_file_contains "$TEST_ROOT/codex-prompt.txt" "Implement beta." "fallback preserves spaced-path context"
assert_file_contains "$TEST_ROOT/codex-prompt.txt" "Proposed change:" "fallback inlines developer report"
assert_not_contains "$(/bin/cat "$TEST_ROOT/codex-prompt.txt")" "file not found" "fallback context manifest"

MOVE_SOURCE="$TEST_ROOT/move source"
MOVE_DESTINATION="$TEST_ROOT/move destination"
mkdir "$MOVE_SOURCE"
"$REPO_ROOT/install.sh" "$MOVE_SOURCE" --name "Movable Project" > "$TEST_ROOT/move-install.out"
MOVE_PM="$MOVE_SOURCE/agentic/pm_flow/pm_flow.sh"
"$MOVE_PM" init-section mover <<'EOF' > "$TEST_ROOT/mover-init.out"
## Objective

- Verify relocation.

## Scope

- Relocation fixture only.

## Owned paths

- `src/mover/**`

## Dependencies

- None.

## Acceptance

- The logical project key survives a move.

## Rejection conditions

- A second blank project workspace appears.
EOF
mv "$MOVE_SOURCE" "$MOVE_DESTINATION"
MOVED_PM="$MOVE_DESTINATION/agentic/pm_flow/pm_flow.sh"
assert_contains "$("$MOVED_PM" list-sections)" "| mover | planned |" "moved install resolves persisted project key"
"$REPO_ROOT/install.sh" "$MOVE_DESTINATION" --name "Movable Project" > "$TEST_ROOT/move-reinstall.out"
assert_file_contains "$MOVE_DESTINATION/agentic/pm_flow/.project-key" "move-source" "project key persists across rename"
[[ ! -d "$MOVE_DESTINATION/agentic/pm_flow/move-destination" ]] || \
  fail "reinstall after rename created a second project workspace"
moved_prepare="$("$MOVED_PM" --section mover prepare-step current moved --file "$TEST_ROOT/developer-report.md")"
moved_pending="$(output_value "$moved_prepare" pending_dir)"
assert_contains "$moved_pending" "$MOVE_DESTINATION" "moved run resolves its current canonical path"
assert_not_contains "$moved_pending" "$MOVE_SOURCE" "moved run does not retain its old absolute path"
expect_failure "cross-project pending containment" "$PM" print-command "$moved_pending"
assert_file_contains "$TEST_ROOT/expected-failure.log" "outside the selected project" "pending cannot cross project boundary"
"$MOVED_PM" cancel-pending "$moved_pending" "relocation test complete" > "$TEST_ROOT/cancel-moved.out"

# --- role/domain personas and the agent dispatcher -------------------------

ROLE_REPO="$TEST_ROOT/role repo"
mkdir "$ROLE_REPO"
"$REPO_ROOT/install.sh" "$ROLE_REPO" --name "Alpha Signals" --domain crypto-trading \
  > "$TEST_ROOT/role-install.out"
ROLE_PM="$ROLE_REPO/agentic/pm_flow/pm_flow.sh"
ROLE_FLOW="$ROLE_REPO/agentic/pm_flow"
AGENT_EXEC="$ROLE_FLOW/agent_exec.sh"

[[ -x "$AGENT_EXEC" ]] || fail "installer did not create executable agent_exec.sh"
assert_file_contains "$ROLE_FLOW/config.json" '"domain": "crypto-trading"' "installer records the chosen domain"

role_config="$("$ROLE_PM" config)"
assert_contains "$role_config" "domain=crypto-trading" "config reports the domain"
assert_contains "$role_config" "title='Crypto Trading Product Manager'" "domain specializes the pm title"
assert_contains "$role_config" "10x_developer:" "config lists the rescue role"

consultant_prompt="$("$ROLE_PM" role-prompt consultant)"
assert_contains "$consultant_prompt" "Quantitative Trading Consultant" "consultant persona uses the domain title"
assert_contains "$consultant_prompt" "Alpha Signals" "role prompt carries the project name"
assert_contains "$consultant_prompt" "backtest is evidence, not proof" "role prompt carries domain context"
assert_not_contains "$consultant_prompt" "{{" "role prompt has no unrendered placeholders"
assert_not_contains "$consultant_prompt" "claude" "role prompt does not name a vendor cli"

generic_repo="$TEST_ROOT/generic repo"
mkdir "$generic_repo"
"$REPO_ROOT/install.sh" "$generic_repo" --name "Plain Project" > "$TEST_ROOT/generic-install.out"
generic_prompt="$("$generic_repo/agentic/pm_flow/pm_flow.sh" role-prompt cpo)"
assert_contains "$generic_prompt" "Chief Product Officer" "generic domain falls back to a neutral title"
assert_contains "$generic_prompt" "domain has not been specified" "generic domain avoids industry priors"

expect_failure "unknown domain rejected" \
  "$REPO_ROOT/install.sh" "$TEST_ROOT/bad domain repo" --domain nonsense
assert_file_contains "$TEST_ROOT/expected-failure.log" "unknown --domain" "domain validation"

# Every role binds to a cli, a model, and a difficulty, and the difficulty is
# translated into whatever knob that cli actually exposes.
rebind_role() {
  python3 - "$ROLE_FLOW/config.json" "$1" "$2" "$3" "$4" <<'PY'
import json, sys
from pathlib import Path
path, role, cli, model, difficulty = sys.argv[1:]
config_path = Path(path)
config = json.loads(config_path.read_text())
config["roles"][role] = {"cli": cli, "model": model, "difficulty": difficulty}
config["supervision"] = {
    "heartbeat_stall_seconds": 60, "max_attempts": 3,
    "retry_backoff_seconds": 1, "usage_limit_pause_seconds": 1,
}
config_path.write_text(json.dumps(config, indent=2) + "\n")
PY
}
printf 'Review the proposal.\nSecond line.\n' > "$TEST_ROOT/role-prompt.md"

dry_run_argv() {
  "$AGENT_EXEC" "$1" --prompt-file "$TEST_ROOT/role-prompt.md" \
    --output "$TEST_ROOT/role-response.json" --dry-run
}

rebind_role developer claude claude-sonnet-5 medium
developer_dry="$(dry_run_argv developer)"
assert_contains "$developer_dry" "--effort medium" "claude difficulty maps to --effort"
assert_contains "$developer_dry" "acceptEdits" "building roles get write access"

rebind_role pm codex gpt-5.1-codex max
pm_dry="$(dry_run_argv pm)"
assert_contains "$pm_dry" "model_reasoning_effort=high" "codex collapses the top difficulty levels"
assert_contains "$pm_dry" "sandbox read-only" "reviewing roles stay read-only"

rebind_role consultant copilot claude-opus-4.6 xhigh
consultant_dry="$(dry_run_argv consultant)"
assert_contains "$consultant_dry" "--effort xhigh" "copilot difficulty maps to --effort"
assert_contains "$consultant_dry" "no-custom-instructions" "copilot ignores repo instructions for a role prompt"

expect_failure "unknown role rejected" \
  "$AGENT_EXEC" architect --prompt-file "$TEST_ROOT/role-prompt.md" \
  --output "$TEST_ROOT/role-response.json" --dry-run
assert_file_contains "$TEST_ROOT/expected-failure.log" "unknown role" "role validation"

# Supervision: a real error must not be retried, transient faults must be, and a
# usage limit must pause rather than burn the remaining attempts.
mkdir "$TEST_ROOT/agent-bin"
stub_cli() {
  printf '#!/bin/zsh -f\n%s\n' "$1" > "$TEST_ROOT/agent-bin/claude"
  chmod +x "$TEST_ROOT/agent-bin/claude"
}
run_supervised() {
  PATH="$TEST_ROOT/agent-bin:$PATH" \
  PM_FLOW_TEST_HEARTBEAT="$TEST_ROOT/heartbeat.txt" "$AGENT_EXEC" developer \
    --prompt-file "$TEST_ROOT/role-prompt.md" \
    --output "$TEST_ROOT/role-response.json" \
    --heartbeat "$TEST_ROOT/heartbeat.txt" > "$TEST_ROOT/supervised.out" 2>&1 || true
}
response_field() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' \
    "$TEST_ROOT/role-response.json" "$1"
}

rebind_role developer claude "" low
stub_cli 'print -u2 "Error: invalid model specified"; exit 1'
run_supervised
[[ "$(response_field attempts)" == "1" ]] || fail "a fatal CLI error must not be retried"
[[ "$(response_field failure_reason)" == "fatal" ]] || fail "fatal failure was misclassified"

stub_cli 'print -u2 "fetch failed: ECONNRESET"; exit 1'
run_supervised
[[ "$(response_field attempts)" == "3" ]] || fail "a network fault must exhaust the retry budget"
[[ "$(response_field failure_reason)" == "network" ]] || fail "network failure was misclassified"

: > "$TEST_ROOT/heartbeat.txt"
rm -f "$TEST_ROOT/usage-limit-tried"
stub_cli "if [[ -f $TEST_ROOT/usage-limit-tried ]]; then
  printf '{\"is_error\":false,\"result\":\"recovered\",\"session_id\":\"s1\"}'
else
  touch $TEST_ROOT/usage-limit-tried
  print -u2 '429 usage limit reached'
  exit 1
fi"
run_supervised
[[ "$(response_field result)" == "recovered" ]] || fail "usage limit pause did not recover"
[[ "$(response_field attempts)" == "2" ]] || fail "usage limit recovery took the wrong number of attempts"
[[ "$(response_field session_resumable)" == "False" ]] || \
  fail "a dispatched role must not advertise a resumable session"
assert_file_contains "$TEST_ROOT/heartbeat.txt" "usage_limit" "heartbeat records why an attempt failed"
assert_file_contains "$TEST_ROOT/heartbeat.txt" "finished" "heartbeat records completion"

# A hung agent must be killed rather than blocking a headless run forever, and
# killing it must take its subprocesses with it.
python3 - "$ROLE_FLOW/config.json" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
config = json.loads(path.read_text())
config["supervision"] = {
    "heartbeat_stall_seconds": 4, "max_attempts": 1,
    "retry_backoff_seconds": 1, "usage_limit_pause_seconds": 1,
}
path.write_text(json.dumps(config, indent=2) + "\n")
PY
stub_cli 'sleep 900'
stall_started="$(date +%s)"
run_supervised
stall_elapsed=$(( $(date +%s) - stall_started ))
[[ "$stall_elapsed" -lt 30 ]] || fail "a hung agent was not terminated (${stall_elapsed}s)"
[[ "$(response_field failure_reason)" == "stall" ]] || fail "a hung agent was not reported as a stall"
assert_file_contains "$TEST_ROOT/heartbeat.txt" "stalled with no progress" "a stall is recorded in the heartbeat"
sleep 1
[[ "$(pgrep -f 'sleep 900' | wc -l | tr -d '[:space:]')" == "0" ]] || \
  fail "terminating a stalled agent left orphaned subprocesses"

# An agent that keeps reporting progress must survive past the stall threshold.
stub_cli 'for i in 1 2 3 4 5 6; do sleep 1; print "$(date -u +%H:%M:%S) working" >> "$PM_FLOW_TEST_HEARTBEAT"; done
printf "{\"is_error\":false,\"result\":\"finished the long assignment\",\"session_id\":\"\"}"'
run_supervised
[[ "$(response_field failure_reason)" == "none" ]] || \
  fail "a heartbeating agent was killed despite reporting progress"
assert_contains "$(response_field result)" "finished the long assignment" "long healthy run completes"

# --- consultant panel ------------------------------------------------------

assert_contains "$role_config" "consultant: seats=2" "consultant is a panel by default"
assert_contains "$role_config" "seat 1: cli=claude" "panel seat one"
assert_contains "$role_config" "seat 2: cli=codex" "panel seat two uses a different model family"

# The dispatcher tests above rebound consultant to a single seat. Restore the
# two-seat panel, and keep the short supervision budget so a stubbed failure
# does not stall the suite.
python3 - "$ROLE_FLOW/config.json" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
config = json.loads(path.read_text())
config["roles"]["consultant"] = [
    {"cli": "claude", "model": "claude-opus-5", "difficulty": "xhigh"},
    {"cli": "codex", "model": "gpt-5.1-codex", "difficulty": "high"},
]
config["supervision"] = {
    "heartbeat_stall_seconds": 60, "max_attempts": 1,
    "retry_backoff_seconds": 1, "usage_limit_pause_seconds": 1,
}
path.write_text(json.dumps(config, indent=2) + "\n")
PY
assert_contains "$("$ROLE_PM" config)" "consultant: seats=2" "panel restored for the panel tests"

"$ROLE_PM" init-section signal-model <<'EOF' > "$TEST_ROOT/panel-section.out"
## Objective

- Build the signal model.

## Scope

- Signal generation only.

## Owned paths

- `src/signal/**`

## Dependencies

- None.

## Acceptance

- Out-of-sample performance beats the baseline.

## Rejection conditions

- Any lookahead bias.
EOF

panel_prompt="$("$ROLE_PM" role-prompt consultant)"
assert_contains "$panel_prompt" "one of several independent consultants" "consultants know they are a panel"
assert_contains "$panel_prompt" "cannot see the others" "panel seats are blind to each other"

mkdir "$TEST_ROOT/panel-bin"
{
  printf '#!/bin/zsh -f\n'
  printf 'sleep 2\n'
  printf 'python3 -c "import json;print(json.dumps({\\"is_error\\":False,\\"result\\":\\"## Diagnosis\\\\nRegime overfit.\\\\n\\\\n## Decision\\\\nALTERNATIVE - walk-forward split\\",\\"session_id\\":\\"\\"}))"\n'
} > "$TEST_ROOT/panel-bin/claude"
{
  printf '#!/bin/zsh -f\n'
  printf 'sleep 2\n'
  printf 'out=""\n'
  printf 'while [[ $# -gt 0 ]]; do [[ "$1" == "-o" ]] && { out="$2"; shift 2; continue; }; shift; done\n'
  printf 'printf "## Diagnosis\\nFeature leakage.\\n\\n## Decision\\nALTERNATIVE - rebuild features causally\\n" > "$out"\n'
} > "$TEST_ROOT/panel-bin/codex"
chmod +x "$TEST_ROOT/panel-bin/claude" "$TEST_ROOT/panel-bin/codex"
printf 'Two attempts failed: overfit in sample, no out-of-sample edge.\n' > "$TEST_ROOT/panel-failure.md"

panel_started="$(date +%s)"
panel_output="$(PATH="$TEST_ROOT/panel-bin:$PATH" "$ROLE_PM" \
  consult-panel signal-model --file "$TEST_ROOT/panel-failure.md")"
panel_elapsed=$(( $(date +%s) - panel_started ))
# Two 2s seats: parallel lands near 3s with poll overhead, serial cannot beat 4s.
[[ "$panel_elapsed" -lt 5 ]] || fail "consultant seats did not run in parallel (${panel_elapsed}s)"

assert_contains "$panel_output" "seats=2" "panel dispatched both seats"
assert_contains "$panel_output" "proposals=2" "both seats delivered a proposal"
panel_dir="$(output_value "$panel_output" panel_dir)"
assert_file_contains "$panel_dir/proposal_1.md" "Regime overfit" "seat one proposal is captured"
assert_file_contains "$panel_dir/proposal_2.md" "Feature leakage" "seat two proposal is captured"

adjudication="$(/bin/cat "$panel_dir/adjudication_prompt.md")"
assert_contains "$adjudication" "Chief Product Officer for a crypto trading product" "adjudication uses the CPO persona"
assert_contains "$adjudication" "Task: adjudicate a consultant panel" "adjudication carries its task"
assert_contains "$adjudication" "proposal_1.md" "adjudication references every proposal"
assert_contains "$adjudication" "proposal_2.md" "adjudication references every proposal"
assert_contains "$adjudication" "ADOPT_PARALLEL" "the CPO may pursue several paths at once"
assert_not_contains "$adjudication" "{{" "adjudication prompt has no unrendered placeholders"

# One failed seat must degrade the panel, not destroy it.
printf '#!/bin/zsh -f\nprint -u2 "Error: model unavailable"; exit 1\n' > "$TEST_ROOT/panel-bin/codex"
chmod +x "$TEST_ROOT/panel-bin/codex"
degraded_output="$(PATH="$TEST_ROOT/panel-bin:$PATH" "$ROLE_PM" \
  consult-panel signal-model --file "$TEST_ROOT/panel-failure.md" 2>/dev/null)"
assert_contains "$degraded_output" "proposals=1" "a failed seat does not abort the panel"
assert_contains "$degraded_output" "note=at least one seat failed" "a failed seat is reported"

# Every seat failing is a real failure.
printf '#!/bin/zsh -f\nprint -u2 "Error: model unavailable"; exit 1\n' > "$TEST_ROOT/panel-bin/claude"
chmod +x "$TEST_ROOT/panel-bin/claude"
expect_failure "panel with no usable proposal" \
  env PATH="$TEST_ROOT/panel-bin:$PATH" "$ROLE_PM" \
  consult-panel signal-model --file "$TEST_ROOT/panel-failure.md"
assert_file_contains "$TEST_ROOT/expected-failure.log" "no consultant seat produced" "empty panel is an error"

# --- headless driver -------------------------------------------------------

DRIVER_REPO="$TEST_ROOT/driver repo"
mkdir "$DRIVER_REPO"
"$REPO_ROOT/install.sh" "$DRIVER_REPO" --name "Driver Project" > "$TEST_ROOT/driver-install.out"
DRIVER_PM="$DRIVER_REPO/agentic/pm_flow/pm_flow.sh"
DRIVER_FLOW="$DRIVER_REPO/agentic/pm_flow"
DRIVER_SECTION="$DRIVER_REPO/agentic/pm_flow/driver-repo/sections/widget"

python3 - "$DRIVER_FLOW/config.json" <<'PYCFG'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
config = json.loads(path.read_text())
for role in ("cpo", "pm", "developer", "10x_developer"):
    config["roles"][role] = {"cli": "claude", "model": "", "difficulty": "low"}
config["roles"]["consultant"] = [
    {"cli": "claude", "model": "", "difficulty": "low"},
    {"cli": "claude", "model": "", "difficulty": "low"},
]
config["escalation"] = {"failures_before_consultant": 2, "max_rescue_attempts": 1}
config["supervision"] = {
    "heartbeat_stall_seconds": 30, "max_attempts": 1,
    "retry_backoff_seconds": 1, "usage_limit_pause_seconds": 1,
}
path.write_text(json.dumps(config, indent=2) + "\n")
PYCFG

"$DRIVER_PM" init-section widget <<'SECTIONBRIEF' > "$TEST_ROOT/driver-section.out"
## Objective

- Build the widget.

## Scope

- The widget only.

## Owned paths

- `src/widget/**`

## Dependencies

- None.

## Acceptance

- Widget tests pass.

## Rejection conditions

- Scope drift.
SECTIONBRIEF

driver_status="$("$DRIVER_PM" status)"
assert_contains "$driver_status" "widget" "status lists the section"
assert_contains "$driver_status" "scope" "a fresh section needs scoping first"

mkdir "$TEST_ROOT/driver-bin"
install_driver_stub() {
  /bin/cp "$1" "$TEST_ROOT/driver-bin/claude"
  chmod +x "$TEST_ROOT/driver-bin/claude"
}
reset_driver_section() {
  find "$DRIVER_SECTION" -mindepth 1 -maxdepth 1 -type d \
    \( -name cycles -o -name panels -o -name 'escalation*' \) -exec rm -rf {} + 2>/dev/null || true
  printf 'planned\n' > "$DRIVER_SECTION/status.txt"
  rm -f "$TEST_ROOT/driver-complete.flag"
}
run_driver() {
  PM_DONE_FLAG="$TEST_ROOT/driver-complete.flag" \
  PATH="$TEST_ROOT/driver-bin:$PATH" "$DRIVER_PM" run --max-ticks "${1:-12}" 2>&1
}

install_driver_stub "$REPO_ROOT/tests/fixtures/stub_success.zsh"
reset_driver_section
success_run="$(run_driver 10)"
assert_contains "$success_run" "scope 001 -> ASSIGN" "driver scopes the first assignment"
assert_contains "$success_run" "develop 001 -> result" "driver dispatches the developer"
assert_contains "$success_run" "review 001 -> GO" "driver reviews the result"
assert_contains "$success_run" "complete -> section done" "driver completes the section"
assert_contains "$success_run" "no section has actionable work" "the run terminates on its own"
assert_contains "$("$DRIVER_PM" status)" "done" "a completed section is done"
assert_file_contains "$DRIVER_SECTION/handoff.md" "Widget works." "the driver publishes the pm's handoff"

# Resumption: a dispatch that died leaves a claim with no output. The next run
# must derive the same next action from the files, with no recovery flag.
reset_driver_section
run_driver 2 > /dev/null
mkdir -p "$DRIVER_SECTION/cycles/002/.claim-develop"
/bin/cp "$DRIVER_SECTION/cycles/001/assignment.md" "$DRIVER_SECTION/cycles/002/assignment.md"
printf '1\n' > "$DRIVER_SECTION/cycles/002/.claim-develop/attempts.txt"
assert_contains "$("$DRIVER_PM" status)" "develop" "a crashed dispatch still needs its step"
resumed_run="$(run_driver 8)"
assert_contains "$resumed_run" "develop 002 -> result" "an interrupted run resumes without recovery state"
assert_contains "$resumed_run" "complete -> section done" "a resumed run still reaches completion"

install_driver_stub "$REPO_ROOT/tests/fixtures/stub_failing.zsh"
reset_driver_section
failing_run="$(run_driver 16)"
assert_contains "$failing_run" "review 001 -> NO_GO (consecutive failures: 1)" "failures are counted from cycle history"
assert_contains "$failing_run" "review 002 -> NO_GO (consecutive failures: 2)" "consecutive failures accumulate"
assert_contains "$failing_run" "widget: escalate" "reaching the threshold escalates automatically"
assert_contains "$failing_run" "adjudicate -> ADOPT_PARALLEL" "the product officer may adopt several paths"
assert_contains "$failing_run" "rescue -> 2 of 2 path(s) delivered" "ADOPT_PARALLEL runs one rescue per path"
assert_contains "$failing_run" "rescue round(s) exhausted" "a rescue that fails review is terminal"
assert_contains "$failing_run" "abandon -> section cancelled" "an exhausted section is abandoned, not retried forever"
assert_contains "$failing_run" "no section has actionable work" "the failing run also terminates"
assert_contains "$("$DRIVER_PM" status)" "cancelled" "the abandoned section is cancelled"
[[ -d "$DRIVER_SECTION/escalation/rescue_1" && -d "$DRIVER_SECTION/escalation/rescue_2" ]] || \
  fail "parallel rescue did not create an isolated attempt per path"

printf 'PASS: headless driver, escalation, and parallel rescue\n'
# The product officer cuts the product into sections before any section exists,
# and a run started from an empty project drives them all to completion.
DECOMP_REPO="$TEST_ROOT/decomp repo"
mkdir "$DECOMP_REPO"
"$REPO_ROOT/install.sh" "$DECOMP_REPO" --name "Decomp Project" --domain saas \
  --mission "ship a usable task tracker" > "$TEST_ROOT/decomp-install.out"
DECOMP_FLOW="$DECOMP_REPO/agentic/pm_flow"
python3 - "$DECOMP_FLOW/config.json" <<'PYCFG'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
config = json.loads(path.read_text())
for role in ("cpo", "pm", "developer", "10x_developer"):
    config["roles"][role] = {"cli": "claude", "model": "", "difficulty": "low"}
config["supervision"] = {
    "heartbeat_stall_seconds": 30, "max_attempts": 1,
    "retry_backoff_seconds": 1, "usage_limit_pause_seconds": 1,
}
path.write_text(json.dumps(config, indent=2) + "\n")
PYCFG

mkdir "$TEST_ROOT/decomp-bin"
/bin/cp "$REPO_ROOT/tests/fixtures/stub_decompose.zsh" "$TEST_ROOT/decomp-bin/claude"
chmod +x "$TEST_ROOT/decomp-bin/claude"

assert_not_contains "$("$DECOMP_FLOW/pm_flow.sh" status)" "widget" "an empty project has no sections yet"
decomp_run="$(PM_DONE_FLAG="$TEST_ROOT/decomp.flag" PATH="$TEST_ROOT/decomp-bin:$PATH" \
  "$DECOMP_FLOW/pm_flow.sh" run --max-ticks 20 2>&1)"
assert_contains "$decomp_run" "(project): decompose" "an empty project decomposes first"
assert_contains "$decomp_run" "decompose -> 2 section(s)" "the officer emits several sections"
assert_contains "$decomp_run" "data-model" "the decomposition names its sections"
assert_contains "$decomp_run" "no section has actionable work" "the whole project run terminates"
decomp_status="$("$DECOMP_FLOW/pm_flow.sh" status)"
assert_contains "$decomp_status" "api" "the dependent section was created"
assert_not_contains "$decomp_status" "planned" "every decomposed section reached a terminal state"

printf 'PASS: product decomposition and a full headless project run\n'

printf 'PASS: section-scoped PM flow\n'
printf 'PASS: role personas, agent dispatch, and supervision\n'
printf 'PASS: independent consultant panel and CPO adjudication\n'
