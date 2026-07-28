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
assert_contains "$sections_output" "| alpha | active |" "alpha registry row"
assert_contains "$sections_output" "| beta | active |" "beta registry row"
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
  'fork_turns="none"' \
  "section PM no-history launch"
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
mkdir "$alpha_run/.record.lock"
printf '%s\n' "$$" > "$alpha_run/.record.lock/owner"
expect_failure "same-section record lock" "$PM" record-step "$alpha_second_pending"
assert_file_contains "$TEST_ROOT/expected-failure.log" "another PM response" "record lock error"
rm "$alpha_run/.record.lock/owner"
rmdir "$alpha_run/.record.lock"
"$PM" record-step "$alpha_second_pending" > "$TEST_ROOT/record-alpha-second.out"

alpha_parallel_one="$("$PM" --section alpha prepare-step current parallel-one --file "$TEST_ROOT/developer-report.md")"
alpha_parallel_one_dir="$(output_value "$alpha_parallel_one" pending_dir)"
expect_failure \
  "parallel same-section prepare" \
  "$PM" --section alpha prepare-step current parallel-two --file "$TEST_ROOT/developer-report.md"
assert_file_contains "$TEST_ROOT/expected-failure.log" "active pending review" "same-section pending serialization"
write_step_response "$alpha_parallel_one_dir/response.json" "alpha-session-1"
"$PM" claim-execution "$alpha_parallel_one_dir" > "$TEST_ROOT/claim-alpha-parallel.out"
"$PM" record-step "$alpha_parallel_one_dir" > "$TEST_ROOT/record-alpha-parallel.out"
expect_failure "duplicate same-section response" "$PM" record-step "$alpha_parallel_one_dir"
assert_file_contains "$TEST_ROOT/expected-failure.log" "not the active review" "duplicate response error"

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
assert_contains "$("$MOVED_PM" list-sections)" "| mover | active |" "moved install resolves persisted project key"
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

printf 'PASS: section-scoped PM flow\n'
