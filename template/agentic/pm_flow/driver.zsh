# driver.zsh - the headless run loop, sourced by pm_flow.sh.
#
# The driver is level-triggered. It stores no record of what it was doing;
# every tick observes the files on disk, derives the single next action from
# them, performs it, and exits. Resumption is therefore not a special code
# path - it is the normal path executed once more. An interrupted run needs no
# recovery logic because there is no in-flight intent to reconstruct.
#
# Each cycle of a section is a directory holding the artifacts of one attempt:
#
#   sections/<key>/cycles/001/assignment.md   scoped by the pm
#   sections/<key>/cycles/001/result.md       produced by the developer
#   sections/<key>/cycles/001/review.md       judged by the pm
#   sections/<key>/cycles/001/decision.txt    the parsed verdict
#
# The presence or absence of those files *is* the state.

# Read one line, tolerating a missing file. `head` on an absent path fails, and
# under `set -o pipefail` that aborts the whole run rather than yielding a
# default, so every optional read goes through here.
first_line_or() {
  local file="$1"
  local fallback="${2:-}"
  local value=""
  if [[ -f "$file" ]]; then
    value="$(/usr/bin/head -n 1 "$file" | tr -d '\r')"
  fi
  printf '%s\n' "${value:-$fallback}"
}

# Take the first line without a pipe. `producer | head -n 1` makes head close
# the pipe early, which kills the producer with SIGPIPE; under `set -o pipefail`
# that becomes the pipeline's status and aborts the run. It only shows up once
# the producer has more than one line to emit.
first_line_of() {
  local text="$1"
  printf '%s\n' "${text%%$'\n'*}"
}

section_cycles_dir() {
  printf '%s\n' "$1/cycles"
}

latest_cycle() {
  local cycles_dir
  cycles_dir="$(section_cycles_dir "$1")"
  [[ -d "$cycles_dir" ]] || { printf '0\n'; return; }
  local newest=0 entry name
  for entry in "$cycles_dir"/*(/N); do
    name="$(basename "$entry")"
    [[ "$name" == <-> ]] || continue
    (( name > newest )) && newest="$name"
  done
  printf '%s\n' "$newest"
}

cycle_dir_for() {
  printf '%s/cycles/%03d\n' "$1" "$2"
}

cycle_decision() {
  first_line_or "$1/decision.txt" ""
}

# Consecutive failures are counted by walking cycles backwards, not tracked in a
# counter. A counter can drift from reality after a crash or a replayed
# recovery; the cycle history cannot.
consecutive_failures() {
  local section_dir="$1"
  local newest failures cycle decision
  newest="$(latest_cycle "$section_dir")"
  failures=0
  for (( cycle = newest; cycle >= 1; cycle-- )); do
    decision="$(cycle_decision "$(cycle_dir_for "$section_dir" "$cycle")")"
    case "$decision" in
      NO_GO) (( failures += 1 )) ;;
      "") continue ;;
      *) break ;;
    esac
  done
  printf '%s\n' "$failures"
}

escalation_dir_for() {
  printf '%s/escalation\n' "$1"
}

section_dependencies_ready() {
  local section_dir="$1"
  local dependencies_file="$section_dir/dependency_handoffs.txt"
  local relative_handoff absolute_handoff dependency_dir
  [[ -f "$dependencies_file" ]] || return 0

  while IFS= read -r relative_handoff; do
    [[ -n "$relative_handoff" ]] || continue
    absolute_handoff="$PROJECT_ROOT/$relative_handoff"
    [[ -f "$absolute_handoff" ]] || return 1
    dependency_dir="$(dirname "$absolute_handoff")"
    [[ "$(first_line_or "$dependency_dir/status.txt" unknown)" == "done" ]] || return 1
  done < "$dependencies_file"
  return 0
}

section_dependency_context() {
  local section_dir="$1"
  local dependencies_file="$section_dir/dependency_handoffs.txt"
  local relative_handoff
  [[ -f "$dependencies_file" ]] || return 0

  while IFS= read -r relative_handoff; do
    [[ -n "$relative_handoff" ]] || continue
    context_bullet_list "$PROJECT_ROOT/$relative_handoff"
  done < "$dependencies_file"
}

# Derive the one action this section needs next. Pure observation; no writes.
section_next_action() {
  local section_dir="$1"
  local lifecycle newest cycle_dir escalation_dir threshold failures

  lifecycle="$(first_line_or "$section_dir/status.txt" active)"
  case "$lifecycle" in
    blocked|done|cancelled) printf 'idle\n'; return ;;
  esac
  if ! section_dependencies_ready "$section_dir"; then
    printf 'waiting-dependencies\n'
    return
  fi

  escalation_dir="$(escalation_dir_for "$section_dir")"
  if [[ -d "$escalation_dir" ]]; then
    if [[ -f "$escalation_dir/exhausted.txt" ]]; then
      printf 'abandon\n'; return
    fi
    if [[ ! -f "$escalation_dir/adjudication.md" ]]; then
      if [[ -f "$escalation_dir/panel_dir.txt" ]]; then
        printf 'adjudicate\n'; return
      fi
      printf 'escalate\n'; return
    fi
    if [[ ! -f "$escalation_dir/rescue_result.md" ]]; then
      case "$(first_line_or "$escalation_dir/decision.txt")" in
        ADOPT|ADOPT_PARALLEL|SYNTHESIZE) printf 'rescue\n'; return ;;
        ABANDON) printf 'abandon\n'; return ;;
      esac
    fi
    if [[ ! -f "$escalation_dir/review.md" ]]; then
      printf 'review-rescue\n'; return
    fi
  fi

  newest="$(latest_cycle "$section_dir")"
  if (( newest == 0 )); then
    printf 'scope\n'; return
  fi
  cycle_dir="$(cycle_dir_for "$section_dir" "$newest")"
  if [[ ! -f "$cycle_dir/assignment.md" ]]; then
    if [[ "$(cycle_decision "$cycle_dir")" == "COMPLETE" ]]; then
      printf 'complete\n'; return
    fi
    printf 'scope\n'; return
  fi
  if [[ ! -f "$cycle_dir/result.md" ]]; then
    printf 'develop\n'; return
  fi
  if [[ ! -f "$cycle_dir/review.md" ]]; then
    printf 'review\n'; return
  fi

  case "$(cycle_decision "$cycle_dir")" in
    NO_GO)
      threshold="$(escalation_threshold)"
      failures="$(consecutive_failures "$section_dir")"
      if (( failures >= threshold )); then
        printf 'escalate\n'; return
      fi
      printf 'scope\n'; return
      ;;
    *)
      printf 'scope\n'; return
      ;;
  esac
}

escalation_threshold() {
  python3 - "$AGENT_CONFIG_FILE" <<'PY'
import json
import sys
from pathlib import Path

config = json.loads(Path(sys.argv[1]).read_text())
value = config.get("escalation", {}).get("failures_before_consultant", 2)
if not isinstance(value, int) or isinstance(value, bool) or value < 1:
    raise SystemExit(f"escalation.failures_before_consultant must be >= 1, got {value!r}")
print(value)
PY
}

# A dispatch is claimed before the model is called so a crash cannot silently
# pay for the same call twice on the next tick. A claim whose output never
# appeared is a died-mid-flight dispatch: it is recorded and retried, because a
# call that produced nothing bought nothing.
claim_step() {
  local claim_dir="$1"
  if mkdir "$claim_dir" 2>/dev/null; then
    printf '%s\n' "$(now_iso_utc)" > "$claim_dir/claimed_at.txt"
    printf '1\n' > "$claim_dir/attempts.txt"
    return 0
  fi
  local attempts
  attempts="$(first_line_or "$claim_dir/attempts.txt" 1)"
  [[ "$attempts" == <-> ]] || attempts=1
  (( attempts += 1 ))
  printf '%s\n' "$attempts" > "$claim_dir/attempts.txt"
  if (( attempts > 3 )); then
    fail "dispatch for $(basename "$claim_dir") has been retried $attempts times; stopping rather than spending more"
  fi
  return 0
}

rescue_attempt_budget() {
  python3 - "$AGENT_CONFIG_FILE" <<'PY'
import json
import sys
from pathlib import Path

config = json.loads(Path(sys.argv[1]).read_text())
value = config.get("escalation", {}).get("max_rescue_attempts", 1)
if not isinstance(value, int) or isinstance(value, bool) or value < 1:
    raise SystemExit(f"escalation.max_rescue_attempts must be >= 1, got {value!r}")
print(value)
PY
}

context_bullet_list() {
  local context_path
  for context_path in "$@"; do
    [[ -f "$context_path" ]] || continue
    printf -- '- %s\n' "$(repo_relative_path "$context_path")"
  done
}

# Dispatch one role and capture its text. Output is written through a temporary
# file and renamed, so a partial write is never visible to the next tick.
dispatch_role() {
  local role="$1"
  local prompt_file="$2"
  local output_md="$3"
  local heartbeat="$4"
  local label="$5"
  local response_json="${output_md%.md}.response.json"
  local staged="${output_md}.staging"

  local dispatch_args=("$role" --prompt-file "$prompt_file" --output "$response_json" --label "$label")
  [[ -z "$heartbeat" ]] || dispatch_args+=(--heartbeat "$heartbeat")

  if ! "$SCRIPT_DIR/agent_exec.sh" "${dispatch_args[@]}" >/dev/null; then
    fail "role '$role' did not produce a usable response for $label; see $response_json"
  fi
  python3 - "$response_json" "$staged" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text())
if payload.get("is_error"):
    raise SystemExit(f"role reported an error: {payload.get('failure_reason', 'unknown')}")
text = (payload.get("result") or "").strip()
if not text:
    raise SystemExit("role returned an empty response")
Path(sys.argv[2]).write_text(text + "\n")
PY
  mv "$staged" "$output_md"
}

# dispatch_role publishes over its own output path, so an assignment that hands
# that path to the role destroys the very work it asked for: the role writes the
# file, the dispatch overwrites it with the response, and review then rejects
# the work as absent. Reject such an assignment before spending a dispatch on
# it. Only write grants are inspected; naming another cycle's artifact as
# read-only evidence stays legal.
assert_output_not_writable() {
  local assignment="$1"
  local output_md="$2"
  local relative report
  [[ -f "$assignment" ]] || return 0
  relative="$(repo_relative_path "$output_md")"
  # Checked explicitly rather than left to ERR_EXIT: this must stop the tick.
  if ! report="$(python3 - "$assignment" "$relative" "${output_md:t}" <<'PY'
import re
import sys
from pathlib import Path

assignment, relative, basename = sys.argv[1], sys.argv[2], sys.argv[3]

# Language that hands a path to the role, either inline or above a list.
grant = re.compile(r"writab|may\s+(?:only\s+)?write|write\s+only|may\s+be\s+written", re.I)
# The dispatch output, as a full repo-relative path or as an unqualified name.
# The lookbehind keeps `cycles/003/result.md` from matching this cycle's file.
target = re.compile(
    r"%s|(?<![\w/.-])%s" % (re.escape(relative), re.escape(basename)), re.I
)
listed = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s")

lines = Path(assignment).read_text().splitlines()
granting = False
offenders = []
for index, line in enumerate(lines):
    # A grant covers the rest of its paragraph, plus any list it introduces.
    if line.startswith("#"):
        granting = False
    elif not line.strip():
        following = next((later for later in lines[index + 1:] if later.strip()), "")
        if not listed.match(following):
            granting = False
    if grant.search(line):
        granting = True
    if granting and target.search(line):
        offenders.append((index + 1, line.strip()))

if offenders:
    detail = "\n".join(f"  line {number}: {text}" for number, text in offenders)
    print(
        f"the assignment grants write access to the dispatch output path "
        f"{relative}:\n{detail}\n"
        f"The harness overwrites that path with the role response, so anything "
        f"written there is lost. Re-scope the assignment: the role reports "
        f"through its response, and durable evidence belongs in a separate "
        f"artifact next to it."
    )
    raise SystemExit(1)
PY
  )"; then
    fail "$report"
  fi
}

record_cycle_decision() {
  local cycle_dir="$1"
  local source_md="$2"
  local allowed="$3"
  local decision
  decision="$(extract_markdown_decision "$(/bin/cat "$source_md")" "$allowed")"
  local staged="$cycle_dir/.decision.txt.staging"
  printf '%s\n' "$decision" > "$staged"
  mv "$staged" "$cycle_dir/decision.txt"
  printf '%s\n' "$decision"
}

# --- transitions -----------------------------------------------------------
#
# Each transition performs exactly one dispatch and one atomic publication. It
# never assumes what the previous tick was doing; it reads the same files
# section_next_action read.

task_file() {
  printf '%s/tasks/%s.md\n' "$SCRIPT_DIR" "$1"
}

open_or_resume_cycle() {
  local section_dir="$1"
  local newest cycle_dir
  newest="$(latest_cycle "$section_dir")"
  if (( newest > 0 )); then
    cycle_dir="$(cycle_dir_for "$section_dir" "$newest")"
    # A cycle with neither an assignment nor a verdict is a scope that died
    # mid-flight; finish it instead of opening another.
    if [[ ! -f "$cycle_dir/assignment.md" && ! -f "$cycle_dir/decision.txt" ]]; then
      printf '%s\n' "$cycle_dir"
      return
    fi
  fi
  (( newest += 1 ))
  cycle_dir="$(cycle_dir_for "$section_dir" "$newest")"
  mkdir -p "$cycle_dir"
  printf '%s\n' "$cycle_dir"
}

cycle_history_files() {
  local section_dir="$1"
  local upto="$2"
  local cycle cycle_dir
  for (( cycle = 1; cycle < upto; cycle++ )); do
    cycle_dir="$(cycle_dir_for "$section_dir" "$cycle")"
    context_bullet_list \
      "$cycle_dir/assignment.md" \
      "$cycle_dir/result.md" \
      "$cycle_dir/review.md"
  done
}

do_scope() {
  local section_dir="$1"
  local cycle_dir cycle_number prompt context
  cycle_dir="$(open_or_resume_cycle "$section_dir")"
  cycle_number="$(basename "$cycle_dir")"
  claim_step "$cycle_dir/.claim-scope"

  context="$(context_bullet_list "$section_dir/brief.md" "$section_dir/state.md" "$CONTRACT_FILE")
$(section_dependency_context "$section_dir")
$(cycle_history_files "$section_dir" "${cycle_number#0}")"
  prompt="$cycle_dir/scope_prompt.md"
  compose_role_task pm "$(task_file section_scope)" \
    "SECTION_KEY=$(basename "$section_dir")" \
    "CYCLE=$cycle_number" \
    "CONTEXT_FILES=$context" > "$prompt"

  dispatch_role pm "$prompt" "$cycle_dir/scope.md" "" "scope $(basename "$section_dir") $cycle_number"
  local decision
  decision="$(record_cycle_decision "$cycle_dir" "$cycle_dir/scope.md" "ASSIGN,COMPLETE")"
  if [[ "$decision" == "ASSIGN" ]]; then
    /bin/cp "$cycle_dir/scope.md" "$cycle_dir/.assignment.staging"
    mv "$cycle_dir/.assignment.staging" "$cycle_dir/assignment.md"
  fi
  printf 'scope %s -> %s\n' "$cycle_number" "$decision"
}

do_develop() {
  local section_dir="$1"
  local newest cycle_dir cycle_number prompt context heartbeat
  newest="$(latest_cycle "$section_dir")"
  cycle_dir="$(cycle_dir_for "$section_dir" "$newest")"
  cycle_number="$(basename "$cycle_dir")"
  assert_output_not_writable "$cycle_dir/assignment.md" "$cycle_dir/result.md"
  claim_step "$cycle_dir/.claim-develop"
  heartbeat="$cycle_dir/heartbeat.txt"

  context="$(context_bullet_list "$cycle_dir/assignment.md" "$section_dir/brief.md" "$section_dir/state.md")"
  prompt="$cycle_dir/develop_prompt.md"
  compose_role_task developer "$(task_file developer_assignment)" \
    "SECTION_KEY=$(basename "$section_dir")" \
    "CYCLE=$cycle_number" \
    "CONTEXT_FILES=$context" \
    "HEARTBEAT_FILE=$(repo_relative_path "$heartbeat")" > "$prompt"

  dispatch_role developer "$prompt" "$cycle_dir/result.md" "$heartbeat" \
    "develop $(basename "$section_dir") $cycle_number"
  printf 'develop %s -> result\n' "$cycle_number"
}

do_review() {
  local section_dir="$1"
  local newest cycle_dir cycle_number prompt context decision
  newest="$(latest_cycle "$section_dir")"
  cycle_dir="$(cycle_dir_for "$section_dir" "$newest")"
  cycle_number="$(basename "$cycle_dir")"
  claim_step "$cycle_dir/.claim-review"

  context="$(context_bullet_list "$cycle_dir/assignment.md" "$cycle_dir/result.md" "$section_dir/brief.md")"
  prompt="$cycle_dir/review_prompt.md"
  compose_role_task pm "$(task_file section_review)" \
    "SECTION_KEY=$(basename "$section_dir")" \
    "CYCLE=$cycle_number" \
    "CONTEXT_FILES=$context" > "$prompt"

  dispatch_role pm "$prompt" "$cycle_dir/review.md" "" "review $(basename "$section_dir") $cycle_number"
  decision="$(record_cycle_decision "$cycle_dir" "$cycle_dir/review.md" "GO,GO_WITH_CHANGES,NO_GO")"
  printf 'review %s -> %s (consecutive failures: %s)\n' \
    "$cycle_number" "$decision" "$(consecutive_failures "$section_dir")"
}

do_escalate() {
  local section_dir="$1"
  local escalation_dir panel_output panel_dir brief cycle cycle_dir
  escalation_dir="$(escalation_dir_for "$section_dir")"
  mkdir -p "$escalation_dir"
  claim_step "$escalation_dir/.claim-panel"

  # The panel is told what was tried and observed, not merely that it failed.
  brief="$escalation_dir/failure_brief.md"
  {
    printf '# Failure history for section %s\n\n' "$(basename "$section_dir")"
    printf 'This section failed %s consecutive review cycles.\n\n' \
      "$(consecutive_failures "$section_dir")"
    for (( cycle = 1; cycle <= $(latest_cycle "$section_dir"); cycle++ )); do
      cycle_dir="$(cycle_dir_for "$section_dir" "$cycle")"
      [[ -f "$cycle_dir/review.md" ]] || continue
      printf '## Cycle %03d - verdict %s\n\n' "$cycle" "$(cycle_decision "$cycle_dir")"
      printf '### What was assigned\n\n%s\n\n' "$(/bin/cat "$cycle_dir/assignment.md" 2>/dev/null)"
      printf '### What came back\n\n%s\n\n' "$(/bin/cat "$cycle_dir/result.md" 2>/dev/null)"
      printf '### Why it was rejected\n\n%s\n\n' "$(/bin/cat "$cycle_dir/review.md")"
    done
  } > "$brief"

  panel_output="$(cmd_consult_panel "$(basename "$section_dir")" --file "$brief")"
  panel_dir="$(printf '%s\n' "$panel_output" | awk -F= '$1 == "panel_dir" {print $2; exit}')"
  [[ -n "$panel_dir" ]] || fail "the consultant panel did not report a panel directory"
  printf '%s\n' "$panel_dir" > "$escalation_dir/panel_dir.txt"
  printf 'escalate -> panel at %s\n' "$(repo_relative_path "$panel_dir")"
}

do_adjudicate() {
  local section_dir="$1"
  local escalation_dir panel_dir decision
  escalation_dir="$(escalation_dir_for "$section_dir")"
  panel_dir="$(first_line_or "$escalation_dir/panel_dir.txt")"
  [[ -f "$panel_dir/adjudication_prompt.md" ]] || \
    fail "the panel left no adjudication prompt at $panel_dir"
  claim_step "$escalation_dir/.claim-adjudicate"

  dispatch_role cpo "$panel_dir/adjudication_prompt.md" \
    "$escalation_dir/adjudication.md" "" "adjudicate $(basename "$section_dir")"
  decision="$(extract_markdown_decision "$(/bin/cat "$escalation_dir/adjudication.md")" \
    "ADOPT,ADOPT_PARALLEL,SYNTHESIZE,ABANDON")"
  printf '%s\n' "$decision" > "$escalation_dir/.decision.txt.staging"
  mv "$escalation_dir/.decision.txt.staging" "$escalation_dir/decision.txt"
  printf 'adjudicate -> %s\n' "$decision"
}

# ADOPT_PARALLEL runs one rescue per selected path, concurrently and blind to
# each other, exactly like the panel. The paths are independent by construction:
# each gets its own attempt directory, and the product officer's stated
# tie-breaker decides between them afterwards.
adjudication_paths() {
  local adjudication="$1"
  python3 - "$adjudication" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text()
inside = False
paths = []
for line in text.splitlines():
    heading = re.match(r"^#{1,6}\s+(.+?)\s*$", line)
    if heading:
        inside = heading.group(1).strip().lower() == "selected paths"
        continue
    if not inside:
        continue
    value = re.sub(r"^\s*[-*\d.)]+\s*", "", line).strip()
    if value:
        paths.append(value)
if not paths:
    raise SystemExit("the adjudication named no selected paths")
print("\n".join(paths))
PY
}

do_rescue() {
  local section_dir="$1"
  local escalation_dir decision paths path_count index prompt context pids=() rescue_status=0
  escalation_dir="$(escalation_dir_for "$section_dir")"
  decision="$(first_line_or "$escalation_dir/decision.txt")"
  paths="$(adjudication_paths "$escalation_dir/adjudication.md")"

  if [[ "$decision" == "ADOPT_PARALLEL" ]]; then
    path_count="$(printf '%s\n' "$paths" | wc -l | tr -d '[:space:]')"
  else
    path_count=1
    paths="$(first_line_of "$paths")"
  fi
  claim_step "$escalation_dir/.claim-rescue"

  context="$(context_bullet_list "$section_dir/brief.md" "$escalation_dir/failure_brief.md" "$escalation_dir/adjudication.md")"
  for (( index = 1; index <= path_count; index++ )); do
    local attempt_dir="$escalation_dir/rescue_$index"
    mkdir -p "$attempt_dir"
    prompt="$attempt_dir/prompt.md"
    compose_role_task 10x_developer "$(task_file section_rescue)" \
      "SECTION_KEY=$(basename "$section_dir")" \
      "CONTEXT_FILES=$context" \
      "CHOSEN_PATH=$(printf '%s\n' "$paths" | sed -n "${index}p")" \
      "HEARTBEAT_FILE=$(repo_relative_path "$attempt_dir/heartbeat.txt")" > "$prompt"
    (
      dispatch_role 10x_developer "$prompt" "$attempt_dir/result.md" \
        "$attempt_dir/heartbeat.txt" "rescue $(basename "$section_dir") path $index" \
        > "$attempt_dir/dispatch.log" 2>&1
    ) &
    pids+=($!)
  done
  for (( index = 1; index <= path_count; index++ )); do
    wait "${pids[$index]}" || rescue_status=1
  done

  local delivered=0
  {
    printf '# Rescue attempts for section %s\n\n' "$(basename "$section_dir")"
    printf 'Decision: %s across %d path(s).\n\n' "$decision" "$path_count"
    for (( index = 1; index <= path_count; index++ )); do
      printf '## Path %d\n\n%s\n\n' "$index" "$(printf '%s\n' "$paths" | sed -n "${index}p")"
      if [[ -f "$escalation_dir/rescue_$index/result.md" ]]; then
        delivered=$(( delivered + 1 ))
        printf '%s\n\n' "$(/bin/cat "$escalation_dir/rescue_$index/result.md")"
      else
        printf 'This path produced no usable result.\n\n'
      fi
    done
  } > "$escalation_dir/.rescue_result.md.staging"
  [[ "$delivered" -ge 1 ]] || fail "no rescue path produced a result; see $escalation_dir"
  mv "$escalation_dir/.rescue_result.md.staging" "$escalation_dir/rescue_result.md"
  printf 'rescue -> %d of %d path(s) delivered\n' "$delivered" "$path_count"
}

do_review_rescue() {
  local section_dir="$1"
  local escalation_dir prompt context decision
  escalation_dir="$(escalation_dir_for "$section_dir")"
  claim_step "$escalation_dir/.claim-review-rescue"

  context="$(context_bullet_list "$section_dir/brief.md" "$escalation_dir/adjudication.md" "$escalation_dir/rescue_result.md")"
  prompt="$escalation_dir/review_prompt.md"
  compose_role_task pm "$(task_file section_review)" \
    "SECTION_KEY=$(basename "$section_dir")" \
    "CYCLE=rescue" \
    "CONTEXT_FILES=$context" > "$prompt"

  dispatch_role pm "$prompt" "$escalation_dir/review.md" "" "review rescue $(basename "$section_dir")"
  decision="$(extract_markdown_decision "$(/bin/cat "$escalation_dir/review.md")" "GO,GO_WITH_CHANGES,NO_GO")"
  if [[ "$decision" == "NO_GO" ]]; then
    local rounds budget
    rounds="$(first_line_or "$escalation_dir/rounds.txt" 0)"
    [[ "$rounds" == <-> ]] || rounds=0
    (( rounds += 1 ))
    budget="$(rescue_attempt_budget)"
    if (( rounds >= budget )); then
      printf '%s\n' "rescue rounds exhausted after $rounds" > "$escalation_dir/exhausted.txt"
      printf 'review-rescue -> NO_GO; %d rescue round(s) exhausted, section will be abandoned\n' "$rounds"
      return
    fi
    # Archive this round so the next tick opens a fresh panel that can see it.
    local archived="${escalation_dir}-failed-$(now_compact_utc)"
    mv "$escalation_dir" "$archived"
    mkdir -p "$escalation_dir"
    printf '%s\n' "$rounds" > "$escalation_dir/rounds.txt"
    printf 'review-rescue -> NO_GO; starting rescue round %d of %d\n' "$(( rounds + 1 ))" "$budget"
    return
  fi
  # The rescue held. Clear the escalation so the section resumes normal cycles
  # with its failure streak broken.
  mv "$escalation_dir" "${escalation_dir}-resolved-$(now_compact_utc)"
  printf 'review-rescue -> %s; section resumes\n' "$decision"
}

do_abandon() {
  local section_dir="$1"
  local escalation_dir summary
  escalation_dir="$(escalation_dir_for "$section_dir")"
  summary="Abandoned after a consultant panel found no viable path"
  {
    printf '## Outcome\n\n- %s.\n\n' "$summary"
    printf '## Decisions\n\n- The product officer accepted abandonment; see the adjudication.\n\n'
    printf '## Interfaces\n\n- Nothing from this section can be depended on.\n\n'
    printf '## Risks\n\n- Any section expecting this capability must be rescoped.\n\n'
    printf '## Next action\n\n- Reconcile the product plan without this section.\n'
  } > "$escalation_dir/abandon_handoff.md"
  cmd_section_handoff "$(basename "$section_dir")" cancelled "$summary" \
    --file "$escalation_dir/abandon_handoff.md" >/dev/null
  printf 'abandon -> section cancelled\n'
}

do_complete() {
  local section_dir="$1"
  local newest cycle_dir prompt context handoff
  newest="$(latest_cycle "$section_dir")"
  cycle_dir="$(cycle_dir_for "$section_dir" "$newest")"
  claim_step "$cycle_dir/.claim-complete"

  context="$(context_bullet_list "$section_dir/brief.md" "$cycle_dir/scope.md")
$(cycle_history_files "$section_dir" "$newest")"
  prompt="$cycle_dir/handoff_prompt.md"
  compose_role_task pm "$(task_file section_handoff)" \
    "SECTION_KEY=$(basename "$section_dir")" \
    "CONTEXT_FILES=$context" > "$prompt"

  handoff="$cycle_dir/handoff.md"
  dispatch_role pm "$prompt" "$handoff" "" "handoff $(basename "$section_dir")"

  # A `done` handoff requires a recorded completion decision. Under the driver
  # that decision is the pm's COMPLETE verdict, backed by the review history in
  # this section's cycles, so record it against the section's run before
  # publishing.
  load_run "$(resolve_section_run "$(basename "$section_dir")")"
  write_completion_marker "DONE" "$cycle_dir"

  cmd_section_handoff "$(basename "$section_dir")" done \
    "Section completed and validated across $newest cycle(s)" --file "$handoff" >/dev/null
  printf 'complete -> section done\n'
}

# --- the loop --------------------------------------------------------------

perform_action() {
  local section_dir="$1"
  local action="$2"
  case "$action" in
    scope)         do_scope "$section_dir" ;;
    develop)       do_develop "$section_dir" ;;
    review)        do_review "$section_dir" ;;
    escalate)      do_escalate "$section_dir" ;;
    adjudicate)    do_adjudicate "$section_dir" ;;
    rescue)        do_rescue "$section_dir" ;;
    review-rescue) do_review_rescue "$section_dir" ;;
    abandon)       do_abandon "$section_dir" ;;
    complete)      do_complete "$section_dir" ;;
    decompose)     do_decompose ;;
    *) fail "unknown driver action: $action" ;;
  esac
}

actionable_sections() {
  local section_dir action
  [[ -d "$SECTIONS_DIR" ]] || return 0
  for section_dir in "$SECTIONS_DIR"/*(/N); do
    [[ "$(basename "$section_dir")" != .* ]] || continue
    action="$(section_next_action "$section_dir")"
    [[ "$action" != "idle" && "$action" != "waiting-dependencies" ]] || continue
    printf '%s\n' "$section_dir"
  done
}

cmd_tick() {
  local requested_section="${SECTION_OVERRIDE:-}"
  local section_dir action
  if [[ -n "$requested_section" ]]; then
    section_dir="$(resolve_section_dir "$requested_section")"
    action="$(section_next_action "$section_dir")"
    if [[ "$action" == "idle" || "$action" == "waiting-dependencies" ]]; then
      if [[ "$action" == "waiting-dependencies" ]]; then
        printf 'waiting=%s\n' "$(basename "$section_dir")"
        return 0
      fi
      printf 'idle=%s\n' "$(basename "$section_dir")"
      return 0
    fi
  else
    section_dir="$(first_line_of "$(actionable_sections)")"
    if [[ -z "$section_dir" ]]; then
      if [[ "$(project_next_action)" == "decompose" ]]; then
        printf 'section=%s\n' "(project)"
        printf 'action=decompose\n'
        printf 'result=%s\n' "$(do_decompose)"
        return 0
      fi
      printf 'idle=project\n'
      return 0
    fi
    action="$(section_next_action "$section_dir")"
  fi

  printf 'section=%s\n' "$(basename "$section_dir")"
  printf 'action=%s\n' "$action"
  # Capture before printing: a command substitution inside printf's arguments
  # discards the action's exit status, so a rejected action would report a
  # successful tick. cmd_run already propagates through its pipeline.
  local outcome action_status=0
  outcome="$(perform_action "$section_dir" "$action")" || action_status=$?
  printf 'result=%s\n' "$outcome"
  return "$action_status"
}

cmd_run() {
  local max_ticks=100
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --max-ticks)
        shift || fail "--max-ticks requires a value"
        max_ticks="${1:-}"
        [[ "$max_ticks" == <-> ]] || fail "--max-ticks requires a positive integer"
        ;;
      *) fail "unknown run argument: $1" ;;
    esac
    shift || true
  done

  local tick=0 section_dir action
  while (( tick < max_ticks )); do
    if [[ -n "${SECTION_OVERRIDE:-}" ]]; then
      section_dir="$(resolve_section_dir "$SECTION_OVERRIDE")"
      action="$(section_next_action "$section_dir")"
      [[ "$action" != "idle" && "$action" != "waiting-dependencies" ]] || section_dir=""
    else
      section_dir="$(first_line_of "$(actionable_sections)")"
    fi
    if [[ -z "$section_dir" ]]; then
      if [[ -z "${SECTION_OVERRIDE:-}" && "$(project_next_action)" == "decompose" ]]; then
        (( tick += 1 ))
        printf '[tick %d] (project): decompose\n' "$tick"
        do_decompose | sed 's/^/          /'
        continue
      fi
      printf 'run finished after %d tick(s): no section has actionable work\n' "$tick"
      return 0
    fi
    (( tick += 1 ))
    action="$(section_next_action "$section_dir")"
    printf '[tick %d] %s: %s\n' "$tick" "$(basename "$section_dir")" "$action"
    perform_action "$section_dir" "$action" | sed 's/^/          /'
  done
  printf 'run stopped at the %d tick budget; work remains\n' "$max_ticks"
  return 0
}

cmd_status() {
  local section_dir lifecycle action
  printf '%-24s %-10s %s\n' "SECTION" "STATUS" "NEXT ACTION"
  [[ -d "$SECTIONS_DIR" ]] || return 0
  for section_dir in "$SECTIONS_DIR"/*(/N); do
    [[ "$(basename "$section_dir")" != .* ]] || continue
    lifecycle="$(first_line_or "$section_dir/status.txt" unknown)"
    action="$(section_next_action "$section_dir")"
    printf '%-24s %-10s %s\n' "$(basename "$section_dir")" "$lifecycle" "$action"
  done
}

# --- project level ---------------------------------------------------------

# The product officer cuts the product into sections once, before any section
# work exists. This is derived like everything else: no sections on disk means
# the project has not been decomposed yet.
project_next_action() {
  local section_dir
  if [[ -d "$SECTIONS_DIR" ]]; then
    for section_dir in "$SECTIONS_DIR"/*(/N); do
      [[ "$(basename "$section_dir")" != .* ]] || continue
      printf 'idle\n'
      return
    done
  fi
  printf 'decompose\n'
}

split_section_blocks() {
  local response="$1"
  local out_dir="$2"
  python3 - "$response" "$out_dir" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text()
out_dir = Path(sys.argv[2])
out_dir.mkdir(parents=True, exist_ok=True)

blocks = re.split(r"^##\s+Section:\s*(.+?)\s*$", text, flags=re.MULTILINE)
if len(blocks) < 3:
    raise SystemExit("the decomposition contained no '## Section: <name>' blocks")

required = ["Objective", "Scope", "Owned paths", "Dependencies", "Acceptance",
            "Rejection conditions"]
names = []
for index in range(1, len(blocks), 2):
    raw_name = blocks[index].strip().strip("`")
    body = blocks[index + 1]
    key = re.sub(r"[^a-z0-9]+", "-", raw_name.lower()).strip("-")
    if not key:
        raise SystemExit(f"section {raw_name!r} has no usable name")
    if key in names:
        raise SystemExit(f"the decomposition names section {key!r} twice")
    for heading in required:
        if not re.search(rf"^#{{1,6}}\s+{re.escape(heading)}\s*$", body,
                         re.MULTILINE | re.IGNORECASE):
            raise SystemExit(f"section {key!r} is missing the {heading!r} heading")
    names.append(key)
    (out_dir / f"{len(names):02d}-{key}.md").write_text(body.strip() + "\n")

print("\n".join(names))
PY
}

do_decompose() {
  local state_claim="$STATE_DIR/.claim-decompose"
  mkdir -p "$STATE_DIR"
  claim_step "$state_claim"

  local prompt context brief_dir names name brief_file created=0
  brief_dir="$STATE_DIR/decomposition"
  mkdir -p "$brief_dir"
  context="$(context_bullet_list "$STATE_DIR/plan.md" "$CONTRACT_FILE")"
  prompt="$brief_dir/prompt.md"
  compose_role_task cpo "$(task_file project_decomposition)" \
    "CONTEXT_FILES=$context" > "$prompt"

  dispatch_role cpo "$prompt" "$brief_dir/sections.md" "" "decompose the product"
  names="$(split_section_blocks "$brief_dir/sections.md" "$brief_dir/briefs")"

  # Created in the order the officer emitted them, because a dependency must
  # already exist before the section that names it.
  for name in ${(f)names}; do
    brief_file="$(first_line_of "$(/bin/ls "$brief_dir/briefs" | grep -- "-${name}.md$")")"
    [[ -n "$brief_file" ]] || fail "no brief was written for section '$name'"
    if ! cmd_init_section "$name" --file "$brief_dir/briefs/$brief_file" >/dev/null; then
      fail "section '$name' could not be created; see $brief_dir/briefs/$brief_file"
    fi
    created=$(( created + 1 ))
  done
  printf 'decompose -> %d section(s): %s\n' "$created" "${names//$'\n'/, }"
}
