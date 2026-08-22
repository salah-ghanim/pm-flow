#!/bin/zsh -f
set -euo pipefail
unsetopt BG_NICE

# --- no inherited selector may reach the fixture -----------------------------
#
# PM_FLOW_PROJECT and PM_FLOW_ROOT are legitimate overrides, and a pm-flow run
# that dispatches this suite exports both. Inherited, they point the fixture's
# commands at the *caller's* project workspace, which does not exist inside the
# temporary repository, so the suite dies before its first PASS group. The
# fixture is written here in full; nothing it needs may come from outside it.
for name in ${(k)parameters[(I)PM_FLOW_*]}; do
  unset "$name"
done
# `fail` is defined further down, once TEST_ROOT exists; this check runs first.
[[ -z "${PM_FLOW_PROJECT:-}${PM_FLOW_ROOT:-}${PM_FLOW_ENGINE_ROOT:-}${PM_FLOW_REPO_ROOT:-}${PM_FLOW_FLOW_DIR:-}" ]] || {
  printf 'FAIL: a PM_FLOW_* override survived into the test environment\n' >&2
  exit 1
}

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

PM="$FIXTURE_REPO/.agentic/pm_flow/pm_flow.sh"
PROJECT_DIR="$FIXTURE_REPO/.agentic/pm_flow/fixture-repo"

[[ -x "$PM" ]] || fail "installer did not create executable pm_flow.sh"
assert_file_contains \
  "$FIXTURE_REPO/CLAUDE.md" \
  ".agentic/pm_flow/fixture-repo/task_contract.md" \
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

## Priority

- must-have: the product cannot ship without it

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

## Priority

- must-have: the product cannot ship without it

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
assert_contains "$sections_output" "| alpha | must-have | planned |" "alpha registry row"
assert_contains "$sections_output" "| beta | must-have | planned |" "beta registry row"
assert_contains "$sections_output" "[handoff](../sections/alpha/handoff.md)" "registry handoff link"
assert_file_contains "$PROJECT_DIR/sections/alpha/brief.md" "Implement alpha." "the brief is persisted"
[[ ! -e "$PROJECT_DIR/sections/alpha/pm_prompt.md" ]] || \
  fail "init-section still generates the retired pm_prompt.md"
assert_file_contains "$PROJECT_DIR/sections/alpha/owned_paths.txt" "src/alpha/**" "owned paths are persisted"
assert_file_contains \
  "$PROJECT_DIR/sections/beta/dependency_handoffs.txt" \
  ".agentic/pm_flow/fixture-repo/sections/alpha/handoff.md" \
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
  printf '## Priority\n\n- must-have: the product cannot ship without it\n\n'
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

# The section lifecycle is now driven by `run`; what pm_flow.sh still owns
# directly is section creation, ownership isolation, and the handoff contract.
{
  printf '## Outcome\n\n- Alpha behavior is validated.\n\n'
  printf '## Decisions\n\n- Kept the bounded implementation.\n\n'
  printf '## Interfaces\n\n- Exposes the alpha interface.\n\n'
  printf '## Risks\n\n- None open.\n\n'
  printf '## What is unproven\n\n- None; every claim above was demonstrated.\n\n'
  printf '## Next action\n\n- Integrate from the root coordinator.\n'
} > "$TEST_ROOT/handoff.md"

expect_failure \
  "done without a completion decision" \
  "$PM" section-handoff alpha done "Alpha validated" --file "$TEST_ROOT/handoff.md"
assert_file_contains "$TEST_ROOT/expected-failure.log" "completion review" "done still requires a recorded completion"

"$PM" section-handoff alpha active "Alpha under way" --file "$TEST_ROOT/handoff.md" > "$TEST_ROOT/handoff.out"
sections_output="$("$PM" list-sections)"
assert_contains "$sections_output" "| alpha | must-have | active | Alpha under way |" "a published handoff updates the registry"

{
  printf '## Objective\n\n- Replace alpha ownership.\n\n'
  printf '## Scope\n\n- Follow-up alpha work.\n\n'
  printf '## Priority\n\n- must-have: the product cannot ship without it\n\n'
  printf '## Owned paths\n\n- `src/alpha/**`\n\n'
  printf '## Dependencies\n\n- None.\n\n'
  printf '## Acceptance\n\n- Replacement tests pass.\n\n'
  printf '## Rejection conditions\n\n- Scope drift.\n'
} > "$TEST_ROOT/reassigned-section.md"
expect_failure \
  "ownership overlap with a live section" \
  "$PM" init-section alpha-replacement --file "$TEST_ROOT/reassigned-section.md"
assert_file_contains "$TEST_ROOT/expected-failure.log" "owned paths overlap" "a live section keeps its paths"

{
  printf '## Outcome\n\n'
  for _word in {1..501}; do printf 'word '; done
  printf '\n\n## Decisions\n\n- None.\n\n'
  printf '## Interfaces\n\n- None.\n\n'
  printf '## Risks\n\n- None.\n\n'
  printf '## What is unproven\n\n- None; every claim above was demonstrated.\n\n'
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
  printf '## What is unproven\n\n- None; every claim above was demonstrated.\n\n'
  printf '## Next action\n\n- None.\n'
} > "$TEST_ROOT/oversized-byte-handoff.md"
expect_failure \
  "oversized byte handoff" \
  "$PM" section-handoff beta active "Unbroken context payload" --file "$TEST_ROOT/oversized-byte-handoff.md"
assert_file_contains "$TEST_ROOT/expected-failure.log" "8192-byte context budget" "handoff byte budget error"

# The retired prepare/record lifecycle must be gone, not merely unused.
for retired_command in init prepare-step record-step prepare-complete record-complete \
                       claim-execution cancel-pending rotate-session adopt-pending \
                       print-command current-run; do
  expect_failure "retired command $retired_command" "$PM" "$retired_command"
  assert_file_contains "$TEST_ROOT/expected-failure.log" "unknown command" \
    "$retired_command is no longer accepted"
done


handoff_before="$(/bin/cat "$PROJECT_DIR/sections/alpha/handoff.md")"
printf '\nPreserve this project plan marker.\n' >> "$PROJECT_DIR/project_state/plan.md"
{
  printf '# Project start prompt\n\n'
  printf 'Legacy coordinator instructions that must be backed up during migration.\n'
} > "$PROJECT_DIR/project_state/start.md"
"$REPO_ROOT/install.sh" "$FIXTURE_REPO" --name "Fixture Project" > "$TEST_ROOT/reinstall.out"
handoff_after="$(/bin/cat "$PROJECT_DIR/sections/alpha/handoff.md")"
[[ "$handoff_before" == "$handoff_after" ]] || fail "reinstall overwrote section handoff"
assert_file_contains "$PROJECT_DIR/sections/alpha/status.txt" "active" "reinstall preserves section status"
assert_file_contains "$PROJECT_DIR/project_state/plan.md" "Preserve this project plan marker." "reinstall preserves project plan"
assert_file_contains "$PROJECT_DIR/project_state/start.md" "pm_flow.sh run" "reinstall refreshes the start guide"
assert_file_contains \
  "$PROJECT_DIR/project_state/start.pre-sections.md" \
  "Legacy coordinator instructions" \
  "reinstall backs up legacy coordinator prompt"


readme_before_failed_upgrade="$(/bin/cat "$FIXTURE_REPO/.agentic/pm_flow/README.md")"
pm_script_before_failed_upgrade="$(/bin/cat "$FIXTURE_REPO/.agentic/pm_flow/pm_flow.sh")"
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
readme_after_failed_upgrade="$(/bin/cat "$FIXTURE_REPO/.agentic/pm_flow/README.md")"
pm_script_after_failed_upgrade="$(/bin/cat "$FIXTURE_REPO/.agentic/pm_flow/pm_flow.sh")"
[[ "$readme_before_failed_upgrade" == "$readme_after_failed_upgrade" ]] || \
  fail "failed template fetch truncated a live installed file"
[[ "$pm_script_before_failed_upgrade" == "$pm_script_after_failed_upgrade" ]] || \
  fail "late template fetch failure partially upgraded installed scripts"

MOVE_SOURCE="$TEST_ROOT/move source"
MOVE_DESTINATION="$TEST_ROOT/move destination"
mkdir "$MOVE_SOURCE"
"$REPO_ROOT/install.sh" "$MOVE_SOURCE" --name "Movable Project" > "$TEST_ROOT/move-install.out"
MOVE_PM="$MOVE_SOURCE/.agentic/pm_flow/pm_flow.sh"
"$MOVE_PM" init-section mover <<'EOF' > "$TEST_ROOT/mover-init.out"
## Objective

- Verify relocation.

## Scope

- Relocation fixture only.

## Priority

- must-have: the product cannot ship without it

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
MOVED_PM="$MOVE_DESTINATION/.agentic/pm_flow/pm_flow.sh"
assert_contains "$("$MOVED_PM" list-sections)" "| mover | must-have | planned |" "moved install resolves persisted project key"
"$REPO_ROOT/install.sh" "$MOVE_DESTINATION" --name "Movable Project" > "$TEST_ROOT/move-reinstall.out"
assert_file_contains "$MOVE_DESTINATION/.agentic/pm_flow/.project-key" "move-source" "project key persists across rename"
[[ ! -d "$MOVE_DESTINATION/.agentic/pm_flow/move-destination" ]] || \
  fail "reinstall after rename created a second project workspace"
moved_status="$("$MOVED_PM" status)"
assert_contains "$moved_status" "mover" "a relocated install still resolves its sections"
assert_contains "$moved_status" "scope" "a relocated section still derives its next action"

# --- role/domain personas and the agent dispatcher -------------------------

ROLE_REPO="$TEST_ROOT/role repo"
mkdir "$ROLE_REPO"
"$REPO_ROOT/install.sh" "$ROLE_REPO" --name "Alpha Signals" --domain crypto-trading \
  > "$TEST_ROOT/role-install.out"
ROLE_PM="$ROLE_REPO/.agentic/pm_flow/pm_flow.sh"
ROLE_FLOW="$ROLE_REPO/.agentic/pm_flow"
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
generic_prompt="$("$generic_repo/.agentic/pm_flow/pm_flow.sh" role-prompt cpo)"
assert_contains "$generic_prompt" "Chief Product Officer" "generic domain falls back to a neutral title"
assert_contains "$generic_prompt" "domain has not been specified" "generic domain avoids industry priors"

migration_repo="$TEST_ROOT/migration repo"
mkdir "$migration_repo"
"$REPO_ROOT/install.sh" "$migration_repo" --name "Golden Grid Migration" --domain migration \
  > "$TEST_ROOT/migration-install.out"
migration_prompt="$("$migration_repo/.agentic/pm_flow/pm_flow.sh" role-prompt pm)"
assert_contains "$migration_prompt" "AI Tooling Migration Manager" "migration domain specializes the pm title"
assert_contains "$migration_prompt" "Context is a first-class artifact" "migration domain carries its own priors"
assert_not_contains "$migration_prompt" "{{" "migration role prompt has no unrendered placeholders"

# A flow directory hosts several projects and they are not all the same kind of
# work, so each project carries its own domain.
multi_repo="$TEST_ROOT/multi domain repo"
mkdir "$multi_repo"
MULTI_FLOW="$multi_repo/.agentic/pm_flow"
MULTI_PM="$MULTI_FLOW/pm_flow.sh"
"$REPO_ROOT/install.sh" "$multi_repo" --name "Grid Platform" --project-key platform \
  --domain infrastructure > "$TEST_ROOT/multi-platform-install.out"
"$REPO_ROOT/install.sh" "$multi_repo" --name "Grid Migration" --project-key migration \
  --domain migration --add-project > "$TEST_ROOT/multi-migration-install.out"

assert_file_contains "$MULTI_FLOW/platform/project.json" '"domain": "infrastructure"' \
  "the first project records its own domain"
assert_file_contains "$MULTI_FLOW/migration/project.json" '"domain": "migration"' \
  "an added project records a different domain"

platform_config="$("$MULTI_PM" --project platform config)"
migration_config="$("$MULTI_PM" --project migration config)"
assert_contains "$platform_config" "domain=infrastructure" "sibling projects resolve their own domain"
assert_contains "$migration_config" "domain=migration" "an added project resolves its own domain"
assert_contains "$migration_config" "project.json" "config reports where the domain came from"

platform_persona="$("$MULTI_PM" --project platform role-prompt consultant)"
migration_persona="$("$MULTI_PM" --project migration role-prompt consultant)"
assert_contains "$platform_persona" "Principal Cloud Architect" "one project's persona follows its own domain"
assert_contains "$migration_persona" "Principal Migration Architect" "a sibling project gets a different persona"

migration_dispatch="$(PM_FLOW_PROJECT=migration "$MULTI_FLOW/agent_exec.sh" pm \
  --prompt-file "$MULTI_FLOW/migration/task_contract.md" --output "$TEST_ROOT/multi-dry.json" --dry-run)"
assert_contains "$migration_dispatch" "domain=migration" "a dispatch reports the calling project's domain"

# Reinstalling a project without --domain must not silently rewrite its domain.
"$REPO_ROOT/install.sh" "$multi_repo" --name "Grid Migration" --project-key migration \
  > "$TEST_ROOT/multi-reinstall.out"
assert_file_contains "$MULTI_FLOW/migration/project.json" '"domain": "migration"' \
  "a reinstall preserves the project's recorded domain"

# A project installed before domains were per-project falls back to config.json.
rm "$MULTI_FLOW/migration/project.json"
legacy_config="$("$MULTI_PM" --project migration config)"
assert_contains "$legacy_config" "domain=infrastructure" "a project with no project.json uses the flow default"
"$REPO_ROOT/install.sh" "$multi_repo" --name "Grid Migration" --project-key migration \
  --domain migration > "$TEST_ROOT/multi-restore.out"

expect_failure "creating an unknown project needs stated intent" \
  "$REPO_ROOT/install.sh" "$multi_repo" --project-key mgration
assert_file_contains "$TEST_ROOT/expected-failure.log" "--add-project" \
  "a mistyped project key is not silently created"

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
# `pm` is a scoped role, not a read-only one: codex cannot express a boundary
# below its working root, so the tier degrades to workspace-write there.
assert_contains "$pm_dry" "sandbox workspace-write" "scoped roles get a workspace on codex"

rebind_role consultant codex gpt-5.1-codex high
assert_contains "$(dry_run_argv consultant)" "sandbox read-only" "reviewing roles stay read-only"

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
[[ "$(response_field failure_reason)" == "permanent" ]] || fail "permanent failure was misclassified"

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

# A claude overload is announced in the CLI's own stdout JSON rather than on
# stderr, so classification has to read both streams. It is also a short
# transient fault, not a usage limit: pausing half an hour for it wastes the
# window in which the service recovers.
: > "$TEST_ROOT/heartbeat.txt"
rm -f "$TEST_ROOT/overload-tried"
stub_cli "if [[ -f $TEST_ROOT/overload-tried ]]; then
  printf '{\"is_error\":false,\"result\":\"recovered from overload\",\"session_id\":\"s2\"}'
else
  touch $TEST_ROOT/overload-tried
  printf '{\"type\":\"result\",\"is_error\":true,\"result\":\"API Error: 529 {\\\"type\\\":\\\"overloaded_error\\\"}\"}'
  exit 1
fi"
run_supervised
[[ "$(response_field result)" == "recovered from overload" ]] || \
  fail "an overload reported only in stdout was not retried"
[[ "$(response_field attempts)" == "2" ]] || \
  fail "an overload took the wrong number of attempts to recover"
assert_file_contains "$TEST_ROOT/heartbeat.txt" "network" \
  "an overload is a transient fault, not a usage limit"

# Whatever the role did say has to survive into the response. When the detail
# is in stdout, retaining the empty stderr log instead loses the only evidence
# of why the dispatch failed.
stub_cli "printf '{\"type\":\"result\",\"is_error\":true,\"result\":\"API Error: 400 invalid request shape\"}'
exit 1"
run_supervised
[[ "$(response_field failure_reason)" == "unknown" ]] || \
  fail "an unrecognized stdout error was misclassified"
assert_contains "$(response_field result)" "invalid request shape" \
  "the retained failure detail comes from whichever stream carried it"

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
# Generous on purpose. The point is that a hung agent is terminated at all, not
# that it happens within a particular second; the stall threshold above is 4s,
# and a loaded machine can take a while to get round to noticing.
[[ "$stall_elapsed" -lt 90 ]] || fail "a hung agent was not terminated (${stall_elapsed}s)"
[[ "$(response_field failure_reason)" == "stall" ]] || fail "a hung agent was not reported as a stall"
assert_file_contains "$TEST_ROOT/heartbeat.txt" "stalled with no progress" "a stall is recorded in the heartbeat"
# Polled rather than slept on. A fixed one-second wait is a race, and it loses
# under load: sections run concurrently now, and this suite is the shared
# acceptance check every one of them is judged by, so a test that fails when the
# machine is busy rejects work that was never wrong. That has already cost this
# project two cycles and an escalation.
orphans_gone=0
for _ in $(seq 1 60); do
  if [[ "$(pgrep -f 'sleep 900' | wc -l | tr -d '[:space:]')" == "0" ]]; then
    orphans_gone=1
    break
  fi
  sleep 0.5
done
(( orphans_gone == 1 )) || \
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

## Priority

- must-have: the product cannot ship without it

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
DRIVER_PM="$DRIVER_REPO/.agentic/pm_flow/pm_flow.sh"
DRIVER_FLOW="$DRIVER_REPO/.agentic/pm_flow"
DRIVER_SECTION="$DRIVER_REPO/.agentic/pm_flow/driver-repo/sections/widget"

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

## Priority

- must-have: the product cannot ship without it

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

# Project-level work preempts section work: the driver reviews the whole
# portfolio on a dispatch cadence, and a tick that lands on a due review spends
# itself there and returns before any section is touched. Anything asserting on
# a single section tick has to clear that queue first, or it reads the review's
# output and reports the section as broken. `status` is side-effect free, so the
# due-ness is read without spending a dispatch to discover it.
drain_project_work() {
  local guard=0
  while [[ "$("$DRIVER_PM" status)" == *"portfolio review due"* ]]; do
    (( guard += 1 ))
    (( guard <= 8 )) || fail "the portfolio review queue would not drain"
    PM_DONE_FLAG="$TEST_ROOT/driver-complete.flag" \
    PATH="$TEST_ROOT/driver-bin:$PATH" "$DRIVER_PM" tick > /dev/null 2>&1
  done
}

# One section tick, with the project queue drained first.
driver_tick() {
  drain_project_work
  PM_DONE_FLAG="$TEST_ROOT/driver-complete.flag" \
  PATH="$TEST_ROOT/driver-bin:$PATH" "$DRIVER_PM" tick
}

install_driver_stub "$REPO_ROOT/tests/fixtures/stub_success.zsh"

# Dependencies are scheduling gates, not merely context allowlists. An
# alphabetically earlier dependent must wait for its prerequisite, including
# when selected explicitly, and blocked sections must never be dispatched.
SCHED_REPO="$TEST_ROOT/scheduling repo"
mkdir "$SCHED_REPO"
"$REPO_ROOT/install.sh" "$SCHED_REPO" --name "Scheduling Project" \
  > "$TEST_ROOT/scheduling-install.out"
SCHED_PM="$SCHED_REPO/.agentic/pm_flow/pm_flow.sh"
SCHED_PROJECT="$SCHED_REPO/.agentic/pm_flow/scheduling-repo"

python3 - "$SCHED_REPO/.agentic/pm_flow/config.json" <<'PYCFG'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
config = json.loads(path.read_text())
for role in ("cpo", "pm", "developer", "10x_developer"):
    config["roles"][role] = {"cli": "claude", "model": "", "difficulty": "low"}
path.write_text(json.dumps(config, indent=2) + "\n")
PYCFG

init_schedule_section() {
  local name="$1"
  local owned_path="$2"
  local dependency="$3"
  "$SCHED_PM" init-section "$name" <<SECTIONBRIEF > /dev/null
## Objective

- Deliver $name.

## Scope

- The bounded $name change only.

## Priority

- must-have: the product cannot ship without it

## Owned paths

- \`$owned_path\`

## Dependencies

- $dependency

## Acceptance

- The bounded result is validated.

## Rejection conditions

- Work starts before its dependency is done.
SECTIONBRIEF
}

init_schedule_section z-prerequisite "src/prerequisite/**" "None."
init_schedule_section a-dependent "src/dependent/**" "z-prerequisite"
init_schedule_section b-blocked "src/blocked/**" "None."

SCHED_DEPENDENT="$SCHED_PROJECT/sections/a-dependent"
SCHED_PREREQUISITE="$SCHED_PROJECT/sections/z-prerequisite"
SCHED_BLOCKED="$SCHED_PROJECT/sections/b-blocked"
printf 'blocked\n' > "$SCHED_BLOCKED/status.txt"

schedule_status="$("$SCHED_PM" status)"
dependent_status_line="$(printf '%s\n' "$schedule_status" | awk '$1 == "a-dependent" {print}')"
blocked_status_line="$(printf '%s\n' "$schedule_status" | awk '$1 == "b-blocked" {print}')"
assert_contains "$dependent_status_line" "waiting-dependencies" "status exposes an unmet dependency"
assert_contains "$blocked_status_line" "idle" "a blocked section is non-actionable"

explicit_waiting_tick="$("$SCHED_PM" --section a-dependent tick)"
assert_contains "$explicit_waiting_tick" "waiting=a-dependent" "explicit tick cannot bypass dependencies"
explicit_waiting_run="$("$SCHED_PM" --section a-dependent run --max-ticks 1)"
assert_contains \
  "$explicit_waiting_run" \
  "no section has actionable work" \
  "explicit run cannot bypass dependencies"
[[ ! -d "$SCHED_DEPENDENT/cycles" ]] || \
  fail "an explicitly selected dependent section was dispatched before its prerequisite"

SCHED_DONE_FLAG="$TEST_ROOT/scheduling-complete.flag"
first_schedule_tick="$(PM_DONE_FLAG="$SCHED_DONE_FLAG" \
  PATH="$TEST_ROOT/driver-bin:$PATH" "$SCHED_PM" tick)"
assert_contains \
  "$first_schedule_tick" \
  "section=z-prerequisite" \
  "the prerequisite is selected before its alphabetically earlier dependent"
[[ -f "$SCHED_PREREQUISITE/cycles/001/assignment.md" ]] || \
  fail "the selected prerequisite was not scoped"
[[ ! -d "$SCHED_DEPENDENT/cycles" ]] || \
  fail "the dependent section was dispatched while its prerequisite was unfinished"

# Both pieces of completion evidence are required: status alone is not enough
# without the accepted handoff file.
printf 'done\n' > "$SCHED_PREREQUISITE/status.txt"
rm "$SCHED_PREREQUISITE/handoff.md"
missing_handoff_tick="$("$SCHED_PM" --section a-dependent tick)"
assert_contains "$missing_handoff_tick" "waiting=a-dependent" "a missing dependency handoff keeps the section waiting"
{
  printf '# Accepted dependency\n\n'
  printf 'DEPENDENCY_READY_EVIDENCE\n'
} > "$SCHED_PREREQUISITE/handoff.md"

second_schedule_tick="$(PM_DONE_FLAG="$SCHED_DONE_FLAG" \
  PATH="$TEST_ROOT/driver-bin:$PATH" "$SCHED_PM" tick)"
assert_contains \
  "$second_schedule_tick" \
  "section=a-dependent" \
  "the dependent becomes actionable after its prerequisite is done"
dependency_handoff="$(/usr/bin/head -n 1 "$SCHED_DEPENDENT/dependency_handoffs.txt")"
assert_file_contains \
  "$SCHED_DEPENDENT/cycles/001/scope_prompt.md" \
  "$dependency_handoff" \
  "the accepted dependency handoff enters the PM scope context"

printf 'done\n' > "$SCHED_DEPENDENT/status.txt"
blocked_tick="$("$SCHED_PM" --section b-blocked tick)"
assert_contains "$blocked_tick" "idle=b-blocked" "explicit tick does not dispatch a blocked section"
project_idle_tick="$("$SCHED_PM" tick)"
assert_contains "$project_idle_tick" "idle=project" "automatic tick ignores a blocked section"
[[ ! -d "$SCHED_BLOCKED/cycles" ]] || fail "a blocked section was dispatched"

# --- access observation ------------------------------------------------------
#
# The access tiers say what a role may touch. On codex the scoped tier bounds
# writes and not reads, and on claude the write tier grants bare Bash, which is
# unrestricted read by construction. Both are documented; neither was ever
# measured. The hook is what measures it, so it is asserted rather than assumed
# - the first version logged one empty record per tool call and looked fine,
# because `python3 - <<'PY'` had already eaten the payload off stdin.
ACCESS_HOOK="$FIXTURE_REPO/.agentic/pm_flow/access_hook.sh"
[[ -x "$ACCESS_HOOK" ]] || fail "the access hook was installed without the execute bit"
ACCESS_LOG="$TEST_ROOT/access-probe.jsonl"
access_probe() {
  printf '%s' "$1" | PM_FLOW_ACCESS_LOG="$ACCESS_LOG" PM_FLOW_ACCESS_ROLE=developer \
    PM_FLOW_ACCESS_LABEL="develop widget 001" PM_FLOW_REPO_ROOT="$FIXTURE_REPO" \
    PM_FLOW_ACCESS_WORK_ROOT="$FIXTURE_REPO" "$ACCESS_HOOK"
}
access_probe '{"tool_name":"Read","tool_input":{"file_path":"/etc/passwd"}}' \
  || fail "the access hook exited non-zero; it must never break a dispatch"
access_probe "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$FIXTURE_REPO/README.md\"}}"
access_probe '{"tool_name":"Bash","tool_input":{"command":"cat ~/.ssh/config"}}'
access_probe 'not json at all'

access_records="$(/bin/cat "$ACCESS_LOG")"
assert_contains "$access_records" '"tool": "Read"' "the hook records which tool was used"
assert_contains "$access_records" '"path": "/etc/passwd", "outside": true' \
  "a read outside the repository is recorded as outside"
assert_contains "$access_records" "$FIXTURE_REPO/README.md\", \"outside\": false" \
  "a read inside the repository is not flagged"
assert_contains "$access_records" '"command": "cat ~/.ssh/config"' \
  "a shell command is recorded verbatim, not merely counted"
# Four probes, four records: the malformed one is still logged rather than
# dropped, because a payload the hook could not read is itself worth knowing.
access_line_count="$(/usr/bin/wc -l < "$ACCESS_LOG" | tr -d '[:space:]')"
[[ "$access_line_count" == 4 ]] || \
  fail "expected 4 access records, got $access_line_count"
assert_not_contains "$access_records" '"targets": [], "outside": false, "command"' \
  "a shell command with paths in it does not record an empty target list"

# --- codex token accounting, against a real event stream ---------------------
#
# This fixture is a verbatim `codex exec --json` stream, captured from a real
# dispatch. It exists because the parser was written and accepted against a
# *fake* codex that emitted `total_token_usage`, a key real codex never sends -
# so every real dispatch recorded no tokens at all, and the section that built
# it passed its acceptance and was marked done. The acceptance said "a Codex
# dispatch writes a non-empty .events.jsonl" and never said a real one.
#
# A section that integrates with an external tool has to be proven against that
# tool. Anything else measures the stub.
codex_usage="$(python3 - "$REPO_ROOT/template/.agentic/pm_flow/telemetry.py" \
    "$REPO_ROOT/tests/fixtures/codex_events_real.jsonl" <<'PYUSAGE'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("telemetry", sys.argv[1])
telemetry = importlib.util.module_from_spec(spec)
spec.loader.exec_module(telemetry)
print(json.dumps(telemetry.usage_from_codex_events(sys.argv[2]), sort_keys=True))
PYUSAGE
)"
assert_contains "$codex_usage" '"input_tokens": 13937' \
  "real codex input tokens are recovered from turn.completed"
assert_contains "$codex_usage" '"output_tokens": 5' \
  "real codex output tokens are recovered"
assert_contains "$codex_usage" '"cache_read_tokens": 12032' \
  "real codex cached input is recorded as a cache read"
assert_contains "$codex_usage" '"total_tokens": 13942' \
  "a total is computed when the real payload carries none"
assert_not_contains "$codex_usage" '{}' \
  "the real stream does not parse to nothing"

printf 'PASS: codex token accounting against a real event stream\n'

printf 'PASS: per-dispatch access observation\n'

printf 'PASS: dependency scheduling and blocked sections\n'

reset_driver_section
success_run="$(run_driver 10)"
assert_contains "$success_run" "scope 001 -> ASSIGN" "driver scopes the first assignment"
assert_contains "$success_run" "develop 001 -> result" "driver dispatches the developer"
assert_contains "$success_run" "review 001 -> GO" "driver reviews the result"
assert_contains "$success_run" "complete -> section done" "driver completes the section"
# A task file gained {{HEARTBEAT_SCRIPT}} and the driver had to learn to fill
# it. An unrendered placeholder reaches the role as literal braces and it does
# whatever it likes with them, so the dispatched prompt is checked directly.
assert_not_contains "$(/bin/cat "$DRIVER_SECTION/cycles/001/develop_prompt.md")" "{{" \
  "the dispatched developer prompt has no unrendered placeholders"
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

# dispatch_role publishes over its own output path, so an assignment that grants
# the developer that path destroys the work it asks for: the role writes the
# file, the dispatch overwrites it, and review rejects the work as absent. The
# driver must refuse the assignment instead of spending a dispatch on it.
reset_driver_section
drain_project_work
run_driver 1 > /dev/null
GUARD_CYCLE="$DRIVER_SECTION/cycles/001"
[[ -f "$GUARD_CYCLE/assignment.md" ]] || fail "the guard fixture was not scoped"
GUARD_OUTPUT="${GUARD_CYCLE#$DRIVER_REPO/}/result.md"
{
  printf '## Assignment\n\n'
  printf 'The developer may write only:\n\n'
  printf -- '- `%s`\n' "$GUARD_OUTPUT"
  printf -- '- `src/widget/thing.py`\n'
} > "$GUARD_CYCLE/assignment.md"
# The rejection is recoverable rather than fatal. The manager wrote the
# assignment, so the manager can rewrite it: the offending assignment is set
# aside, the cycle returns to scope, and the tick succeeds. It used to fail the
# whole tick, which left the cycle wedged on the same rejected assignment
# forever.
guard_reject_tick="$(driver_tick)"
assert_contains "$guard_reject_tick" "assignment rejected; returning the cycle to scope" \
  "an assignment owning the dispatch output path is refused and re-scoped"
assert_file_contains "$GUARD_CYCLE/rescope_reason.txt" \
  "grants write access to the dispatch output path" "the rejection explains itself"
assert_file_contains "$GUARD_CYCLE/rescope_reason.txt" "$GUARD_OUTPUT" \
  "the rejection names the offending path"
[[ -f "$GUARD_CYCLE/assignment.rejected.md" ]] || \
  fail "the rejected assignment was not set aside for the manager to see"
[[ ! -f "$GUARD_CYCLE/result.md" ]] || \
  fail "a rejected assignment still spent a developer dispatch"
[[ ! -d "$GUARD_CYCLE/.claim-develop" ]] || \
  fail "a rejected assignment still claimed the develop step"

# A prohibition is not a grant. Telling a role that the harness owns result.md
# names both writability and the path, and must not be read as handing it over.
{
  printf '## Assignment\n\n'
  printf 'Writable paths:\n\n- `src/widget/thing.py`\n\n'
  printf '`result.md` is the harness dispatch output and is not writable;\n'
  printf 'durable evidence goes in the named artifact.\n\n'
  printf '# Rejection conditions\n\n'
  printf 'Reject if any file outside the writable paths changes; if `result.md`\n'
  printf 'is treated as a durable artifact.\n'
} > "$GUARD_CYCLE/assignment.md"
guard_prohibition_tick="$(driver_tick)"
assert_contains "$guard_prohibition_tick" "develop 001 -> result" \
  "a prohibition naming the output path is not a grant"
rm -f "$GUARD_CYCLE/result.md"

# An unqualified mention is caught the same way, since that is how the grant is
# usually phrased in prose.
printf '## Assignment\n\nThe developer may write only `heartbeat.txt` and\n`result.md`.\n' \
  > "$GUARD_CYCLE/assignment.md"
guard_inline_tick="$(driver_tick)"
assert_contains "$guard_inline_tick" "assignment rejected; returning the cycle to scope" \
  "an inline write grant on the output name is rejected"
assert_file_contains "$GUARD_CYCLE/rescope_reason.txt" \
  "grants write access to the dispatch output path" "an inline grant is rejected too"

# Only write grants are inspected. Another cycle's result is ordinary read-only
# evidence, and prose after a grant's list is outside the grant.
{
  printf '## Assignment\n\n'
  printf 'Reuse the evidence in `%s`.\n\n' \
    "${DRIVER_SECTION#$DRIVER_REPO/}/cycles/003/result.md"
  printf 'Writable paths:\n\n- `src/widget/thing.py`\n\n'
  printf 'Report what cycle 003 recorded in its result.md before reviewing.\n'
} > "$GUARD_CYCLE/assignment.md"
guard_allowed_tick="$(driver_tick)"
assert_contains "$guard_allowed_tick" "develop 001 -> result" \
  "a read-only reference to another cycle's result stays legal"
[[ -f "$GUARD_CYCLE/result.md" ]] || fail "the permitted assignment was not dispatched"

install_driver_stub "$REPO_ROOT/tests/fixtures/stub_failing.zsh"
reset_driver_section
failing_run="$(run_driver 16)"
assert_contains "$failing_run" "review 001 -> NO_GO (developer said PARTIAL; consecutive failures: 1)" "failures are counted from cycle history"
assert_contains "$failing_run" "review 002 -> NO_GO (developer said PARTIAL; consecutive failures: 2)" "consecutive failures accumulate"
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
# --- worktree isolation ------------------------------------------------------
#
# Sections owning disjoint paths is an honour system. A worktree per section
# makes the isolation structural: the dispatch runs somewhere else entirely, an
# accepted cycle merges back, and a rejected one never reaches the main tree.
WT_REPO="$TEST_ROOT/worktree repo"
mkdir "$WT_REPO"
git -C "$WT_REPO" init -q -b main
git -C "$WT_REPO" config user.name "pm-flow test"
git -C "$WT_REPO" config user.email "pm-flow-test@localhost"
mkdir -p "$WT_REPO/src"
printf 'seed\n' > "$WT_REPO/src/seed.txt"
"$REPO_ROOT/install.sh" "$WT_REPO" --name "Worktree Project" > "$TEST_ROOT/wt-install.out"
WT_PM="$WT_REPO/.agentic/pm_flow/pm_flow.sh"
WT_FLOW="$WT_REPO/.agentic/pm_flow"
WT_PROJECT="$WT_REPO/.agentic/pm_flow/worktree-repo"

python3 - "$WT_FLOW/config.json" <<'PYCFG'
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

wt_init_section() {
  "$WT_PM" init-section "$1" <<SECTIONBRIEF > /dev/null
## Objective

- Write the $1 file.

## Scope

- That file only.

## Priority

- must-have: the product cannot ship without it

## Owned paths

- \`src/$1.txt\`

## Dependencies

- None.

## Acceptance

- The file exists.

## Rejection conditions

- Any other file changes.
SECTIONBRIEF
}

wt_init_section alpha
wt_init_section beta

git -C "$WT_REPO" add -A
git -C "$WT_REPO" -c user.name="pm-flow test" -c user.email="pm-flow-test@localhost" \
  commit -q -m "seed the worktree project"
WT_BASE_COMMIT="$(git -C "$WT_REPO" rev-parse HEAD)"

mkdir "$TEST_ROOT/wt-bin" "$TEST_ROOT/wt-state"
/bin/cp "$REPO_ROOT/tests/fixtures/stub_worktree.zsh" "$TEST_ROOT/wt-bin/claude"
chmod +x "$TEST_ROOT/wt-bin/claude"

wt_run() {
  PM_STUB_STATE="$TEST_ROOT/wt-state" PM_STUB_REVIEW="${PM_STUB_REVIEW:-GO}" \
  PATH="$TEST_ROOT/wt-bin:$PATH" "$WT_PM" run --max-ticks "${1:-30}" 2>&1
}

# A worktree that a killed run left behind must not block the next one. git
# keeps an administrative record per worktree that outlives the directory, and
# a stale record is exactly what makes `git worktree add` refuse the path.
# Beside the repository. Not inside it, where every find and glob would walk
# it, and not under .git, where tools that exclude `.git` by path part exclude
# the whole checkout and an agent's write controls refuse it as sensitive.
WT_ROOT="${TEST_ROOT}/.pm-flow-worktrees/worktree repo/worktree-repo"
mkdir -p "$WT_ROOT/alpha"
printf 'left behind by a killed run\n' > "$WT_ROOT/alpha/debris.txt"

wt_first_run="$(wt_run 30)"

assert_contains "$wt_first_run" "complete -> section done" "a section in a worktree still completes"
[[ ! -f "$WT_ROOT/alpha/debris.txt" ]] || \
  fail "an orphaned worktree directory blocked the next run instead of being reclaimed"

# The dispatch ran somewhere else. Not "the driver said so" - the developer
# recorded its own working directory from inside the process.
wt_cwds="$(/bin/cat "$TEST_ROOT/wt-state/develop_cwd.log")"
assert_contains "$wt_cwds" "/.pm-flow-worktrees/worktree repo/worktree-repo/alpha" \
  "the developer dispatch ran inside the section's own worktree"
assert_contains "$wt_cwds" "/.pm-flow-worktrees/worktree repo/worktree-repo/beta" \
  "each section got its own worktree, not a shared one"
assert_not_contains "$wt_cwds" "$WT_REPO
" "no developer dispatch ran in the main working tree"

# Tool caches must land somewhere the dispatch is allowed to write. codex runs
# reviewers under --sandbox workspace-write, which refuses $HOME/.cache, so an
# acceptance check that builds anything failed with "Failed to initialize cache
# ... Operation not permitted" - and the section was rejected for not passing a
# check that could not be executed at all. Two cycles and an escalation went to
# that before anyone looked.
wt_env="$(/bin/cat "$TEST_ROOT/wt-state/develop_env.log")"
assert_contains "$wt_env" "$WT_PROJECT/runs/.cache" \
  "tool caches are pointed inside the project, where every sandbox can write"
assert_not_contains "$wt_env" "unset" \
  "every cache variable a build tool reads for is set, not merely one of them"

# An accepted cycle merges back. Both sections wrote a file, each in its own
# tree, and both files are in the main tree afterwards without either having
# collided with the other.
assert_file_contains "$WT_REPO/src/alpha.txt" "written by alpha" \
  "an accepted section's work merged into the main tree"
assert_file_contains "$WT_REPO/src/beta.txt" "written by beta" \
  "a second section merged back without colliding with the first"
[[ "$(git -C "$WT_REPO" rev-parse HEAD)" != "$WT_BASE_COMMIT" ]] || \
  fail "the base branch did not advance, so nothing was actually merged"
assert_contains "$(git -C "$WT_REPO" log --oneline -20)" "merge(alpha)" \
  "the merge is recorded on the base branch"

# Finishing a section gives its checkout back, and takes no work with it: the
# branch that carries the history stays.
[[ ! -d "$WT_ROOT/alpha" ]] || fail "a completed section kept its worktree"
assert_contains "$(git -C "$WT_REPO" branch --list 'pm-flow/*')" "pm-flow/worktree-repo/alpha" \
  "removing a worktree did not remove the branch behind it"

# A rejected result never reaches the main tree. The same stub, reviewing NO_GO,
# writes its file in the worktree and the main tree must not see it.
wt_init_section gamma
git -C "$WT_REPO" add -A
git -C "$WT_REPO" -c user.name="pm-flow test" -c user.email="pm-flow-test@localhost" \
  commit -q -m "add the rejected section"
WT_REJECT_COMMIT="$(git -C "$WT_REPO" rev-parse HEAD)"
PM_STUB_REVIEW=NO_GO wt_run 4 > /dev/null
[[ ! -f "$WT_REPO/src/gamma.txt" ]] || \
  fail "a rejected result reached the main working tree"
[[ -f "$WT_ROOT/gamma/src/gamma.txt" ]] || \
  fail "the rejected work did not survive in the section's own worktree"
[[ "$(git -C "$WT_REPO" rev-parse HEAD)" == "$WT_REJECT_COMMIT" ]] || \
  fail "a rejected cycle advanced the base branch"
[[ -z "$(git -C "$WT_REPO" status --porcelain -- src)" ]] || \
  fail "a rejected cycle left the main working tree dirty"

# Where a worktree lives is load-bearing, so it is asserted rather than assumed.
# Under `.git`, MANIFEST generation enumerated 0 of 74 template files and a
# developer's write controls refused its own owned paths as sensitive; a section
# was blocked for two cycles by it.
assert_not_contains "$WT_ROOT" "/.git/" "section worktrees are not placed under .git"
[[ ! -d "$(git -C "$WT_REPO" rev-parse --path-format=absolute --git-common-dir)/pm-flow" ]] || \
  fail "a worktree was created under .git"
wt_manifest_count="$(cd "$WT_ROOT/../../../" 2>/dev/null && pwd -P)"
assert_not_contains "$wt_manifest_count" "/.git" "the worktree root itself is outside .git"

printf 'PASS: per-section git worktrees, merge-back, and cleanup\n'

# Two section-scoped runs at once. Worktrees made this safe; the project lock
# still made it impossible, because it was exclusive for every run. A
# section-scoped run now takes the project lock shared and its own section
# exclusively, so two sections proceed and a project-wide run is still refused
# while either is in flight.
wt_init_section delta
wt_init_section epsilon
git -C "$WT_REPO" add -A
git -C "$WT_REPO" -c user.name="pm-flow test" -c user.email="pm-flow-test@localhost" \
  commit -q -m "add the concurrent sections"

wt_parallel_section() {
  PM_STUB_STATE="$TEST_ROOT/wt-state" PM_STUB_REVIEW=GO \
  PATH="$TEST_ROOT/wt-bin:$PATH" "$WT_PM" --section "$1" run --max-ticks 8 \
    > "$TEST_ROOT/wt-$1.log" 2>&1
}
wt_parallel_section delta &
wt_delta_pid=$!
wt_parallel_section epsilon &
wt_epsilon_pid=$!
wait "$wt_delta_pid" || fail "the delta section run failed: $(/bin/cat "$TEST_ROOT/wt-delta.log")"
wait "$wt_epsilon_pid" || fail "the epsilon section run failed: $(/bin/cat "$TEST_ROOT/wt-epsilon.log")"

assert_contains "$(/bin/cat "$TEST_ROOT/wt-delta.log")" "complete -> section done" \
  "a section completes while another section is running"
assert_contains "$(/bin/cat "$TEST_ROOT/wt-epsilon.log")" "complete -> section done" \
  "the concurrent section completes too"
assert_file_contains "$WT_REPO/src/delta.txt" "written by delta" \
  "one concurrent section merged back"
assert_file_contains "$WT_REPO/src/epsilon.txt" "written by epsilon" \
  "the other concurrent section merged back without losing the first"
[[ -z "$(git -C "$WT_REPO" status --porcelain -- src)" ]] || \
  fail "concurrent merges left the main working tree dirty"

# A section whose branch has commits of its own must still pick up the base.
# It used to fast-forward only, so once a section had committed anything it was
# pinned to the base as it stood at that moment - including the shared
# acceptance check every section is judged on. persona-packs lost two cycles and
# reached the escalation threshold on a flaky test it did not own, because its
# branch could never receive the fix.
WT_SYNC_BRANCH="pm-flow/worktree-repo/delta"
git -C "$WT_REPO" show-ref --verify --quiet "refs/heads/$WT_SYNC_BRANCH" || \
  fail "the delta section left no branch to test syncing against"
printf 'a shared fix that landed after the section branched\n' > "$WT_REPO/src/shared-fix.txt"
git -C "$WT_REPO" add -A
git -C "$WT_REPO" -c user.name="pm-flow test" -c user.email="pm-flow-test@localhost" \
  commit -q -m "a fix on the base, after delta already committed"
WT_SYNC_TREE="$WT_ROOT/delta-sync"
git -C "$WT_REPO" worktree add --force "$WT_SYNC_TREE" "$WT_SYNC_BRANCH" > /dev/null 2>&1
[[ ! -f "$WT_SYNC_TREE/src/shared-fix.txt" ]] || \
  fail "the section branch already had the base fix; the test proves nothing"
( eval "$(sed -n '/^sync_section_worktree() {/,/^}/p' "$WT_FLOW/driver.zsh")"
  PROJECT_ROOT="$WT_REPO"
  driver_base_branch() { printf 'main\n'; }
  sync_section_worktree "$WT_SYNC_TREE" "" ) || true
[[ -f "$WT_SYNC_TREE/src/shared-fix.txt" ]] || \
  fail "a section branch with its own commits never received the base fix"
git -C "$WT_REPO" worktree remove --force "$WT_SYNC_TREE" > /dev/null 2>&1 || true

# A section run holds the project lock in shared mode, so a project-wide run,
# which schedules across every section, must be refused rather than allowed to
# race it. Asserted by holding the shared lock directly rather than by starting
# a second run and hoping it is still alive: that version passed or failed
# depending on which process won, which is a coin toss dressed up as a test.
zmodload zsh/system
: >> "$WT_PROJECT/.driver.lock"
zsystem flock -t 0 -r -f WT_SHARED_LOCK "$WT_PROJECT/.driver.lock" || \
  fail "could not take the project lock in shared mode; two section runs could never coexist"
wt_project_refusal=0
PM_STUB_STATE="$TEST_ROOT/wt-state" PATH="$TEST_ROOT/wt-bin:$PATH" \
  "$WT_PM" run --max-ticks 1 > "$TEST_ROOT/wt-project.log" 2>&1 || wt_project_refusal=$?
(( wt_project_refusal != 0 )) || \
  fail "a project-wide run was allowed while a section run held the project lock"
assert_contains "$(/bin/cat "$TEST_ROOT/wt-project.log")" "already running" \
  "the refusal says which lock stopped it"
# And a second shared holder is admitted, which is the other half of the claim.
zsystem flock -t 0 -r -f WT_SHARED_LOCK_2 "$WT_PROJECT/.driver.lock" || \
  fail "a second section run could not take the shared lock; concurrency is not real"
zsystem flock -u "$WT_SHARED_LOCK_2"
zsystem flock -u "$WT_SHARED_LOCK"

printf 'PASS: concurrent section runs, serialised merges, and lock exclusion\n'


# The product officer cuts the product into sections before any section exists,
# and a run started from an empty project drives them all to completion.
DECOMP_REPO="$TEST_ROOT/decomp repo"
mkdir "$DECOMP_REPO"
"$REPO_ROOT/install.sh" "$DECOMP_REPO" --name "Decomp Project" --domain saas \
  --mission "ship a usable task tracker" > "$TEST_ROOT/decomp-install.out"
DECOMP_FLOW="$DECOMP_REPO/.agentic/pm_flow"
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
decomp_code=0
decomp_run="$(PM_DONE_FLAG="$TEST_ROOT/decomp.flag" PATH="$TEST_ROOT/decomp-bin:$PATH" \
  "$DECOMP_FLOW/pm_flow.sh" run --max-ticks 20 2>&1)" || decomp_code=$?
# Reported rather than left to `set -e`. A run that exits non-zero inside a
# command substitution kills the suite with no output at all, which is how a
# missing heading in the decomposition fixture read as "the suite stops after
# the driver tests" for weeks.
(( decomp_code == 0 )) || fail "the decomposition run exited $decomp_code:
$decomp_run"
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
