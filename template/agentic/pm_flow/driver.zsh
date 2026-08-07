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
#
# The walk stops at `failure_streak_reset.txt`. A rescue that passes review
# clears the escalation directory but cannot rewrite the cycle that failed, so
# without this marker the very next tick recounts the same NO_GO run, escalates
# again, and convenes another panel forever - on the success path, at the most
# expensive dispatch mix in the flow.
#
# An UNPARSED verdict counts as a failure. It used to count as nothing at all,
# which made a formatting miss strictly cheaper than an honest rejection.
consecutive_failures() {
  local section_dir="$1"
  local newest failures cycle decision floor
  newest="$(latest_cycle "$section_dir")"
  floor="$(first_line_or "$section_dir/failure_streak_reset.txt" 0)"
  [[ "$floor" == <-> ]] || floor=0
  failures=0
  for (( cycle = newest; cycle > floor; cycle-- )); do
    decision="$(cycle_decision "$(cycle_dir_for "$section_dir" "$cycle")")"
    case "$decision" in
      NO_GO|UNPARSED) (( failures += 1 )) ;;
      "") continue ;;
      *) break ;;
    esac
  done
  printf '%s\n' "$failures"
}

# Trailing cycles that were accepted without ever completing the section.
# GO_WITH_CHANGES resets no counter and costs nothing, so a section can accept
# eight cycles in a row while converging on nothing and never arm the escalation
# ladder. This is the signal that catches motion without convergence.
accepted_without_completion() {
  local section_dir="$1"
  local newest cycle decision accepted
  newest="$(latest_cycle "$section_dir")"
  accepted=0
  for (( cycle = newest; cycle >= 1; cycle-- )); do
    decision="$(cycle_decision "$(cycle_dir_for "$section_dir" "$cycle")")"
    case "$decision" in
      GO|GO_WITH_CHANGES) (( accepted += 1 )) ;;
      "") continue ;;
      *) break ;;
    esac
  done
  printf '%s\n' "$accepted"
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
  local converge_after accepted reviewed_at

  # A quarantined section is out of the run but not out of the project. It used
  # to be that any fatal dispatch ended the whole run, so one broken section
  # stopped six healthy ones.
  if [[ -f "$section_dir/quarantine.txt" ]]; then
    printf 'quarantined\n'; return
  fi
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
    UNPARSED)
      # The review was written and paid for; only its verdict was unreadable.
      # Re-ask for the verdict rather than letting the section advance as
      # though the cycle had passed, which is what happened when an unparsed
      # decision fell through to `scope`.
      threshold="$(escalation_threshold)"
      failures="$(consecutive_failures "$section_dir")"
      if (( failures >= threshold )); then
        printf 'escalate\n'; return
      fi
      printf 'review\n'; return
      ;;
    NO_GO)
      threshold="$(escalation_threshold)"
      failures="$(consecutive_failures "$section_dir")"
      if (( failures >= threshold )); then
        printf 'escalate\n'; return
      fi
      printf 'scope\n'; return
      ;;
    *)
      converge_after="$(convergence_threshold)"
      if (( converge_after > 0 )); then
        accepted="$(accepted_without_completion "$section_dir")"
        reviewed_at="$(first_line_or "$section_dir/convergence/last_cycle.txt" 0)"
        [[ "$reviewed_at" == <-> ]] || reviewed_at=0
        if (( accepted >= converge_after && newest - reviewed_at >= converge_after )); then
          printf 'converge\n'; return
        fi
      fi
      printf 'scope\n'; return
      ;;
  esac
}

config_positive_int() {
  python3 - "$AGENT_CONFIG_FILE" "$1" "$2" "$3" "$4" <<'PY'
import json
import sys
from pathlib import Path

config_path, section, key, default, floor = sys.argv[1:]
config = json.loads(Path(config_path).read_text())
value = config.get(section, {}).get(key, int(default))
if not isinstance(value, int) or isinstance(value, bool) or value < int(floor):
    raise SystemExit(f"{section}.{key} must be >= {floor}, got {value!r}")
print(value)
PY
}

escalation_threshold() {
  config_positive_int escalation failures_before_consultant 2 1
}

# Zero disables the convergence review entirely.
convergence_threshold() {
  config_positive_int escalation cycles_before_convergence_review 6 0
}

step_claim_ceiling() {
  config_positive_int supervision max_step_claims 3 1
}

failure_brief_window() {
  config_positive_int escalation failure_brief_cycles 3 1
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
  local attempts ceiling
  attempts="$(first_line_or "$claim_dir/attempts.txt" 1)"
  [[ "$attempts" == <-> ]] || attempts=1
  (( attempts += 1 ))
  printf '%s\n' "$attempts" > "$claim_dir/attempts.txt"
  ceiling="$(step_claim_ceiling)"
  if (( attempts > ceiling )); then
    # This used to be a hardcoded 3 that ended the run and permanently bricked
    # the cycle. It is now configurable, and the caller turns the failure into
    # a quarantine so the rest of the project keeps moving.
    fail "dispatch for $(basename "$claim_dir") has been retried $attempts times (ceiling $ceiling); stopping rather than spending more"
  fi
  return 0
}

rescue_attempt_budget() {
  config_positive_int escalation max_rescue_attempts 1 1
}

context_bullet_list() {
  local context_path
  for context_path in "$@"; do
    [[ -f "$context_path" ]] || continue
    printf -- '- %s\n' "$(repo_relative_path "$context_path")"
  done
}

# --- money ------------------------------------------------------------------
#
# `--max-ticks` counts events whose cost varies by more than an order of
# magnitude and rises with cycle depth, so it is not a budget. Every dispatch
# appends what it actually cost to a ledger, and the run is governed on the sum.

cost_ledger_file() {
  printf '%s/cost_ledger.tsv\n' "$RUNS_DIR"
}

record_dispatch_cost() {
  local response_json="$1"
  local section_key="$2"
  local role="$3"
  local label="$4"
  local ledger cost
  ledger="$(cost_ledger_file)"
  mkdir -p "$RUNS_DIR"
  cost="$(python3 "$SCRIPT_DIR/cost.py" one "$response_json" 2>/dev/null || printf '')"
  # The response path is recorded so the same dispatch is never counted twice:
  # once from this row and again from the envelope still sitting on disk.
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(now_iso_utc)" "${section_key:-(project)}" "$role" "${label//$'\t'/ }" \
    "$cost" "$response_json" >> "$ledger"
}

# What the project has spent. With no section key this is the whole project.
#
# This is the ledger plus every response envelope the ledger has never seen, so
# a project that was already deep into its spend before the ledger existed does
# not read as zero and get authorised for the whole budget again.
spent_usd() {
  python3 "$SCRIPT_DIR/cost.py" total "$PROJECT_DIR" "$(cost_ledger_file)" "${1:-}"
}

cmd_cost() {
  python3 "$SCRIPT_DIR/cost.py" report "$PROJECT_DIR" "$(cost_ledger_file)"
}

budget_limit() {
  python3 - "$AGENT_CONFIG_FILE" "$1" <<'PY'
import json
import sys
from pathlib import Path

config = json.loads(Path(sys.argv[1]).read_text())
value = config.get("budget", {}).get(sys.argv[2], 0)
if not isinstance(value, (int, float)) or isinstance(value, bool) or value < 0:
    raise SystemExit(f"budget.{sys.argv[2]} must be a non-negative number, got {value!r}")
print(f"{float(value):.4f}")
PY
}

# Checked before every dispatch. A limit of 0 means unlimited.
assert_within_budget() {
  local section_key="${1:-}"
  local limit spent
  limit="$(budget_limit max_usd)"
  spent="$(spent_usd)"
  if [[ "$(python3 -c 'import sys; print("1" if float(sys.argv[1]) > 0 and float(sys.argv[2]) >= float(sys.argv[1]) else "0")' "$limit" "$spent")" == "1" ]]; then
    fail "project budget exhausted: \$$spent spent against budget.max_usd \$$limit"
  fi
  [[ -n "$section_key" ]] || return 0
  limit="$(budget_limit max_usd_per_section)"
  spent="$(spent_usd "$section_key")"
  if [[ "$(python3 -c 'import sys; print("1" if float(sys.argv[1]) > 0 and float(sys.argv[2]) >= float(sys.argv[1]) else "0")' "$limit" "$spent")" == "1" ]]; then
    fail "section $section_key budget exhausted: \$$spent spent against budget.max_usd_per_section \$$limit"
  fi
}

# Dispatch one role and capture its text. Output is written through a temporary
# file and renamed, so a partial write is never visible to the next tick.
dispatch_role() {
  local role="$1"
  local prompt_file="$2"
  local output_md="$3"
  local heartbeat="$4"
  local label="$5"
  local section_key="${6:-${DISPATCH_SECTION_KEY:-}}"
  local response_json="${output_md%.md}.response.json"
  local staged="${output_md}.staging"

  assert_within_budget "$section_key"

  local dispatch_args=("$role" --prompt-file "$prompt_file" --output "$response_json" --label "$label")
  [[ -z "$heartbeat" ]] || dispatch_args+=(--heartbeat "$heartbeat")

  local dispatch_status=0
  "$SCRIPT_DIR/agent_exec.sh" "${dispatch_args[@]}" >/dev/null || dispatch_status=$?
  # Record the cost even when the dispatch failed: a call that errored after
  # the model had already answered still cost money.
  record_dispatch_cost "$response_json" "$section_key" "$role" "$label"
  if (( dispatch_status != 0 )); then
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
  local report_out="${3:-}"
  local relative report
  [[ -f "$assignment" ]] || return 0
  relative="$(repo_relative_path "$output_md")"
  # Checked explicitly rather than left to ERR_EXIT: this must stop the tick.
  if ! report="$(python3 - "$assignment" "$relative" "${output_md:t}" <<'PY'
import re
import sys
from pathlib import Path

assignment, relative, basename = sys.argv[1], sys.argv[2], sys.argv[3]

# Language that hands a path to a role.
grant = re.compile(r"writab|may\s+(?:only\s+)?write|write\s+only|may\s+be\s+written", re.I)
# A prohibition mentions writability too. "result.md is not writable" is the
# opposite of a grant, and an assignment that says so must not be rejected for
# saying it, so a negation just before the phrase disarms it.
negated = re.compile(r"(?:not|never|cannot|can't|no|nor|non-)\W+\w*\s*$", re.I)
# The dispatch output, as a full repo-relative path or as an unqualified name.
# The lookbehind keeps `cycles/003/result.md` from matching this cycle's file.
target = re.compile(
    r"%s|(?<![\w/.-])%s" % (re.escape(relative), re.escape(basename)), re.I
)
# A grant reaches only to the end of its own clause, so a rejection-conditions
# paragraph that mentions writable paths in one clause and result.md in another
# is not a grant. A trailing colon instead opens the list the grant introduces.
# A terminator is punctuation followed by space, so the dots inside
# `heartbeat.txt` and `result.md` do not end the clause that grants them.
clause_end = re.compile(r"[.;](?=\s|$)|\n\s*\n|\n(?=#)")
listed = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s")

text = Path(assignment).read_text()
lines = text.splitlines()


def line_of(offset):
    return text.count("\n", 0, offset) + 1


def list_block_end(offset):
    """End of the bullet list a colon-terminated grant introduces."""
    index = line_of(offset)  # 1-based line holding the colon
    end = offset
    for line in lines[index:]:
        if not line.strip() or listed.match(line):
            end += len(line) + 1
            continue
        break
    return end


offenders = []
for match in grant.finditer(text):
    if negated.search(text[max(0, match.start() - 40):match.start()]):
        continue
    span = text[match.end():]
    stop = clause_end.search(span)
    reach = match.end() + (stop.start() if stop else len(span))
    # A colon-terminated grant carries into the list it introduces.
    if text[match.end():reach].rstrip().endswith(":") or (
        stop and stop.group().startswith(":")
    ):
        reach = max(reach, list_block_end(reach))
    line_start = text.rfind("\n", 0, match.start()) + 1
    if text[line_start:].split("\n", 1)[0].rstrip().endswith(":"):
        reach = max(reach, list_block_end(line_start))
    hit = target.search(text, match.end(), reach)
    if hit:
        number = line_of(hit.start())
        offenders.append((number, lines[number - 1].strip()))

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
    # The manager wrote the assignment, so the manager can fix it. This used to
    # be unrecoverable: the tick failed with the explanation on stderr and the
    # cycle stayed wedged on the same rejected assignment forever.
    if [[ -n "$report_out" ]]; then
      printf '%s\n' "$report" > "$report_out"
      return 1
    fi
    fail "$report"
  fi
  return 0
}

# Record the verdict, or record that there wasn't one.
#
# An unparseable verdict used to leave no decision.txt at all, so the next tick
# read the cycle as though it had passed: the section advanced, the escalation
# counter never moved, and a formatting miss was strictly cheaper than an honest
# rejection. UNPARSED is now a state of its own that counts as a failure.
record_cycle_decision() {
  local cycle_dir="$1"
  local source_md="$2"
  local allowed="$3"
  local decision reason
  local staged="$cycle_dir/.decision.txt.staging"
  if ! decision="$(markdown_verdict_parse "$(/bin/cat "$source_md")" "$allowed" 2>"$cycle_dir/.verdict_error.txt")"; then
    reason="$(/bin/cat "$cycle_dir/.verdict_error.txt" 2>/dev/null || true)"
    {
      printf 'The response at %s carries no readable verdict.\n\n' "$(repo_relative_path "$source_md")"
      printf 'Parser said: %s\n\n' "${reason:-unknown}"
      printf 'Answer again. Keep every section you already wrote, and end with a\n'
      printf 'heading `Decision` whose first line begins with exactly one of:\n%s\n' "${allowed//,/, }"
    } > "$cycle_dir/verdict_feedback.md"
    rm -f "$cycle_dir/.verdict_error.txt"
    printf 'UNPARSED\n' > "$staged"
    mv "$staged" "$cycle_dir/decision.txt"
    printf 'UNPARSED\n'
    return 0
  fi
  rm -f "$cycle_dir/.verdict_error.txt" "$cycle_dir/verdict_feedback.md"
  decision="${decision%%$'\n'*}"
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
  local newest cycle_dir decision
  newest="$(latest_cycle "$section_dir")"
  if (( newest > 0 )); then
    cycle_dir="$(cycle_dir_for "$section_dir" "$newest")"
    if [[ ! -f "$cycle_dir/assignment.md" ]]; then
      decision="$(cycle_decision "$cycle_dir")"
      # A cycle with neither an assignment nor a verdict is a scope that died
      # mid-flight; finish it instead of opening another. An UNPARSED verdict
      # or a rejected assignment is the same situation: the scope has to be
      # asked again, and it costs less to re-ask in place.
      if [[ -z "$decision" || "$decision" == "UNPARSED" || -f "$cycle_dir/rescope_reason.txt" ]]; then
        printf '%s\n' "$cycle_dir"
        return
      fi
    fi
  fi
  (( newest += 1 ))
  cycle_dir="$(cycle_dir_for "$section_dir" "$newest")"
  mkdir -p "$cycle_dir"
  printf '%s\n' "$cycle_dir"
}

# Recent history only.
#
# This used to append assignment + result + review for every prior cycle
# forever, so the scope context grew linearly and the scope call's cost grew
# with it. `state.md` is the manager's own durable summary and is already in the
# scope context; that is what the older cycles are for.
scope_history_window() {
  config_positive_int escalation scope_history_cycles 2 1
}

cycle_history_files() {
  local section_dir="$1"
  local upto="$2"
  local window="${3:-0}"
  local cycle cycle_dir start
  start=1
  if (( window > 0 && upto - window > 1 )); then
    start=$(( upto - window ))
  fi
  for (( cycle = start; cycle < upto; cycle++ )); do
    cycle_dir="$(cycle_dir_for "$section_dir" "$cycle")"
    context_bullet_list \
      "$cycle_dir/assignment.md" \
      "$cycle_dir/result.md" \
      "$cycle_dir/review.md"
  done
}

# Record that the section cannot be closed from inside the flow.
#
# A manager that has correctly diagnosed an unreachable acceptance criterion
# previously had no way to say so: the scope step accepted only ASSIGN or
# COMPLETE, so the only legal move was to assign another cycle that also could
# not close.
record_blocked_external() {
  local section_dir="$1"
  local cycle_dir="$2"
  local blocker="$3"
  local section_key summary handoff
  section_key="$(basename "$section_dir")"
  summary="Blocked on an external dependency: ${blocker}"
  summary="${summary//$'\n'/ }"
  (( ${#summary} <= 200 )) || summary="${summary[1,197]}..."
  handoff="$cycle_dir/blocked_handoff.md"
  {
    printf '## Outcome\n\n- %s\n\n' "$summary"
    printf '## Decisions\n\n- The section manager stopped scoping cycles because no assignment\n'
    printf '  available to it can satisfy the acceptance criteria.\n\n'
    printf '## Interfaces\n\n- Nothing new. Dependent sections must assume this capability is unavailable.\n\n'
    printf '## Risks\n\n- The dependency may never arrive, in which case the section must be rescoped\n'
    printf '  or abandoned as a product decision.\n\n'
    printf '## Next action\n\n- Resolve the external dependency, then reopen this section with an\n'
    printf '  `active` handoff.\n'
  } > "$handoff"
  cmd_section_handoff "$section_key" blocked "$summary" --file "$handoff" >/dev/null
}

do_scope() {
  local section_dir="$1"
  local cycle_dir cycle_number prompt context section_key
  section_key="$(basename "$section_dir")"
  cycle_dir="$(open_or_resume_cycle "$section_dir")"
  cycle_number="$(basename "$cycle_dir")"
  claim_step "$cycle_dir/.claim-scope"

  context="$(context_bullet_list "$section_dir/brief.md" "$section_dir/state.md" "$CONTRACT_FILE" \
      "$section_dir/convergence/latest.md" "$cycle_dir/rescope_reason.txt" "$cycle_dir/verdict_feedback.md")
$(section_dependency_context "$section_dir")
$(cycle_history_files "$section_dir" "${cycle_number#0}" "$(scope_history_window)")"
  prompt="$cycle_dir/scope_prompt.md"
  compose_role_task pm "$(task_file section_scope)" \
    "SECTION_KEY=$section_key" \
    "CYCLE=$cycle_number" \
    "CONTEXT_FILES=$context" > "$prompt"

  dispatch_role pm "$prompt" "$cycle_dir/scope.md" "" "scope $section_key $cycle_number"
  local decision blocker assignment
  decision="$(record_cycle_decision "$cycle_dir" "$cycle_dir/scope.md" "ASSIGN,COMPLETE,BLOCKED_EXTERNAL")"
  case "$decision" in
    ASSIGN)
      rm -f "$cycle_dir/rescope_reason.txt"
      # Only the assignment reaches the developer. The whole scope response
      # used to be copied verbatim, editorial included.
      if ! assignment="$(extract_assignment_sections "$(/bin/cat "$cycle_dir/scope.md")" 2>/dev/null)"; then
        assignment="$(/bin/cat "$cycle_dir/scope.md")"
      fi
      printf '%s\n' "$assignment" > "$cycle_dir/.assignment.staging"
      mv "$cycle_dir/.assignment.staging" "$cycle_dir/assignment.md"
      ;;
    BLOCKED_EXTERNAL)
      blocker="$(extract_markdown_decision_line "$(/bin/cat "$cycle_dir/scope.md")" \
        "ASSIGN,COMPLETE,BLOCKED_EXTERNAL" || true)"
      blocker="$(printf '%s' "$blocker" | \
        sed -E 's/^[[:space:]]*BLOCKED_EXTERNAL[[:space:]]*[-:,.]*[[:space:]]*//; s/[[:space:]]+$//')"
      if [[ -z "$blocker" ]]; then
        # The token has to name what is blocking, or the state it produces is
        # unactionable. Treat a bare token as an unreadable verdict.
        {
          printf 'BLOCKED_EXTERNAL must name the external dependency and what would\n'
          printf 'unblock it, on the same line as the token. Answer again with, for\n'
          printf 'example: `BLOCKED_EXTERNAL no paper gateway credentials exist on this\n'
          printf 'host; a human must install and log into one`.\n'
        } > "$cycle_dir/verdict_feedback.md"
        printf 'UNPARSED\n' > "$cycle_dir/.decision.txt.staging"
        mv "$cycle_dir/.decision.txt.staging" "$cycle_dir/decision.txt"
        printf 'scope %s -> UNPARSED (BLOCKED_EXTERNAL named no dependency)\n' "$cycle_number"
        return 0
      fi
      record_blocked_external "$section_dir" "$cycle_dir" "$blocker"
      printf 'scope %s -> BLOCKED_EXTERNAL (%s)\n' "$cycle_number" "$blocker"
      return 0
      ;;
  esac
  printf 'scope %s -> %s\n' "$cycle_number" "$decision"
}

do_develop() {
  local section_dir="$1"
  local newest cycle_dir cycle_number prompt context heartbeat dev_status
  newest="$(latest_cycle "$section_dir")"
  cycle_dir="$(cycle_dir_for "$section_dir" "$newest")"
  cycle_number="$(basename "$cycle_dir")"
  if ! assert_output_not_writable "$cycle_dir/assignment.md" "$cycle_dir/result.md" \
      "$cycle_dir/rescope_reason.txt"; then
    mv "$cycle_dir/assignment.md" "$cycle_dir/assignment.rejected.md"
    rm -f "$cycle_dir/.claim-scope/attempts.txt"
    printf 'develop %s -> assignment rejected; returning the cycle to scope\n' "$cycle_number"
    return 0
  fi
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

  # The developer's own status has been part of the response contract all along
  # and was parsed by nothing. Record it so the review sees a claim the
  # developer made about itself, and so a BLOCKED developer is visible before
  # the review reads three pages to discover it.
  dev_status="$(extract_markdown_decision "$(/bin/cat "$cycle_dir/result.md")" \
    "DELIVERED,PARTIAL,BLOCKED" Status 2>/dev/null || printf 'UNSTATED\n')"
  printf '%s\n' "$dev_status" > "$cycle_dir/dev_status.txt"
  printf 'develop %s -> result (developer status: %s)\n' "$cycle_number" "$dev_status"
}

do_review() {
  local section_dir="$1"
  local newest cycle_dir cycle_number prompt context decision
  newest="$(latest_cycle "$section_dir")"
  cycle_dir="$(cycle_dir_for "$section_dir" "$newest")"
  cycle_number="$(basename "$cycle_dir")"
  claim_step "$cycle_dir/.claim-review"

  context="$(context_bullet_list "$cycle_dir/assignment.md" "$cycle_dir/result.md" \
    "$section_dir/brief.md" "$cycle_dir/verdict_feedback.md")"
  prompt="$cycle_dir/review_prompt.md"
  compose_role_task pm "$(task_file section_review)" \
    "SECTION_KEY=$(basename "$section_dir")" \
    "CYCLE=$cycle_number" \
    "CONTEXT_FILES=$context" > "$prompt"

  dispatch_role pm "$prompt" "$cycle_dir/review.md" "" "review $(basename "$section_dir") $cycle_number"
  decision="$(record_cycle_decision "$cycle_dir" "$cycle_dir/review.md" "GO,GO_WITH_CHANGES,NO_GO")"
  printf 'review %s -> %s (developer said %s; consecutive failures: %s)\n' \
    "$cycle_number" "$decision" "$(first_line_or "$cycle_dir/dev_status.txt" UNSTATED)" \
    "$(consecutive_failures "$section_dir")"
}

# The product officer, reading only the brief and the last two reviews, is asked
# whether a section that keeps being accepted is actually converging.
do_converge() {
  local section_dir="$1"
  local section_key newest review_dir prompt context decision index cycle cycle_dir reviews
  section_key="$(basename "$section_dir")"
  newest="$(latest_cycle "$section_dir")"
  review_dir="$section_dir/convergence/$(printf '%03d' "$newest")"
  mkdir -p "$review_dir"
  claim_step "$review_dir/.claim-converge"

  reviews=""
  index=0
  for (( cycle = newest; cycle >= 1 && index < 2; cycle-- )); do
    cycle_dir="$(cycle_dir_for "$section_dir" "$cycle")"
    [[ -f "$cycle_dir/review.md" ]] || continue
    reviews+="$(context_bullet_list "$cycle_dir/review.md")"$'\n'
    (( index += 1 ))
  done
  context="$(context_bullet_list "$section_dir/brief.md")
${reviews%$'\n'}"

  prompt="$review_dir/prompt.md"
  compose_role_task cpo "$(task_file convergence_review)" \
    "SECTION_KEY=$section_key" \
    "ACCEPTED_CYCLES=$(accepted_without_completion "$section_dir")" \
    "CONTEXT_FILES=$context" > "$prompt"

  dispatch_role cpo "$prompt" "$review_dir/review.md" "" "converge $section_key"
  decision="$(extract_markdown_decision "$(/bin/cat "$review_dir/review.md")" \
    "CONTINUE,RESCOPE,BLOCKED_EXTERNAL,ABANDON" 2>/dev/null || printf 'CONTINUE\n')"
  printf '%s\n' "$decision" > "$review_dir/decision.txt"
  printf '%s\n' "$newest" > "$section_dir/convergence/last_cycle.txt"
  /bin/cp "$review_dir/review.md" "$section_dir/convergence/latest.md"

  case "$decision" in
    BLOCKED_EXTERNAL)
      record_blocked_external "$section_dir" "$review_dir" \
        "the product officer's convergence review found no reachable acceptance path"
      ;;
    ABANDON)
      do_abandon "$section_dir" "Abandoned by a convergence review after $(accepted_without_completion "$section_dir") accepted cycles closed nothing" >/dev/null
      ;;
  esac
  printf 'converge -> %s\n' "$decision"
}

do_escalate() {
  local section_dir="$1"
  local escalation_dir panel_output panel_dir brief cycle cycle_dir
  escalation_dir="$(escalation_dir_for "$section_dir")"
  mkdir -p "$escalation_dir"
  claim_step "$escalation_dir/.claim-panel"

  # The panel is told what was tried and observed, not merely that it failed.
  # The window is bounded for the same reason the scope context is: a section
  # deep enough to reach a panel has enough history to swamp the panel's own
  # reasoning with it.
  local newest window start
  newest="$(latest_cycle "$section_dir")"
  window="$(failure_brief_window)"
  start=1
  if (( newest - window + 1 > 1 )); then
    start=$(( newest - window + 1 ))
  fi
  brief="$escalation_dir/failure_brief.md"
  {
    printf '# Failure history for section %s\n\n' "$(basename "$section_dir")"
    printf 'This section failed %s consecutive review cycles.\n' \
      "$(consecutive_failures "$section_dir")"
    if (( start > 1 )); then
      printf 'Cycles %03d to %03d are shown; %d earlier cycle(s) are omitted.\n' \
        "$start" "$newest" "$(( start - 1 ))"
    fi
    printf '\n'
    for (( cycle = start; cycle <= newest; cycle++ )); do
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
  #
  # Breaking the streak needs a record the cycle history can see. Removing the
  # escalation directory alone left the newest cycle holding NO_GO, so the very
  # next tick recounted the same failures, escalated again, and convened another
  # panel - an unbounded loop on the success path.
  printf '%s\n' "$(latest_cycle "$section_dir")" > "$section_dir/failure_streak_reset.txt"
  mv "$escalation_dir" "${escalation_dir}-resolved-$(now_compact_utc)"
  printf 'review-rescue -> %s; section resumes\n' "$decision"
}

do_abandon() {
  local section_dir="$1"
  local escalation_dir summary
  escalation_dir="$(escalation_dir_for "$section_dir")"
  mkdir -p "$escalation_dir"
  summary="${2:-Abandoned after a consultant panel found no viable path}"
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
  local newest cycle_dir prompt context handoff report attempt section_key
  section_key="$(basename "$section_dir")"
  newest="$(latest_cycle "$section_dir")"
  cycle_dir="$(cycle_dir_for "$section_dir" "$newest")"
  claim_step "$cycle_dir/.claim-complete"

  context="$(context_bullet_list "$section_dir/brief.md" "$section_dir/state.md" "$cycle_dir/scope.md")
$(cycle_history_files "$section_dir" "$newest" "$(scope_history_window)")"
  prompt="$cycle_dir/handoff_prompt.md"
  compose_role_task pm "$(task_file section_handoff)" \
    "SECTION_KEY=$section_key" \
    "CONTEXT_FILES=$context" > "$prompt"

  handoff="$cycle_dir/handoff.md"
  # A handoff over the context budget used to be re-requested with the identical
  # prompt and no feedback, so the second attempt missed the cap the same way
  # and the cycle bricked. Say by how much, once, then stop.
  for attempt in 1 2; do
    dispatch_role pm "$prompt" "$handoff" "" "handoff $section_key (attempt $attempt)"
    report="$(handoff_budget_report "$(/bin/cat "$handoff")")"
    [[ -n "$report" ]] || break
    printf '%s\n' "$report" > "$cycle_dir/handoff_feedback.md"
    (( attempt < 2 )) || fail "the section handoff missed its budget twice:
$report"
    {
      printf '\n---\n\n# Your previous handoff was rejected\n\n'
      printf 'You already wrote this handoff once and it did not fit:\n\n%s\n\n' "$report"
      printf 'Write it again, shorter, with the same five headings and nothing else.\n'
    } >> "$prompt"
  done

  # A `done` handoff requires a recorded completion decision. Under the driver
  # that decision is the pm's COMPLETE verdict, backed by the review history in
  # this section's cycles, so record it against the section's run before
  # publishing.
  load_run "$(resolve_section_run "$section_key")"
  write_completion_marker "DONE" "$cycle_dir"

  cmd_section_handoff "$section_key" done \
    "Section completed and validated across $newest cycle(s)" --file "$handoff" >/dev/null
  printf 'complete -> section done\n'
}

# --- the loop --------------------------------------------------------------

run_action() {
  local section_dir="$1"
  local action="$2"
  case "$action" in
    scope)         do_scope "$section_dir" ;;
    develop)       do_develop "$section_dir" ;;
    review)        do_review "$section_dir" ;;
    converge)      do_converge "$section_dir" ;;
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

# Stamp the section's lifecycle on every tick.
#
# `status.txt` used to be written at creation and then only by `section-handoff`
# for `done` and `cancelled`, so every live section read `planned` forever - in
# the one generated file the product officer is allowed to read.
stamp_section_progress() {
  local section_dir="$1"
  local action="$2"
  local lifecycle
  lifecycle="$(first_line_or "$section_dir/status.txt" planned)"
  case "$lifecycle" in
    blocked|done|cancelled) return 0 ;;
  esac
  printf 'active\n' > "$section_dir/status.txt"
  printf '%s\n' "$(now_iso_utc)" > "$section_dir/updated_at.txt"
  printf 'Cycle %s; last action %s.\n' \
    "$(latest_cycle "$section_dir")" "$action" > "$section_dir/summary.txt"
}

# The repository as the dispatch found it, so a failed dispatch's leftovers can
# be named rather than silently inherited by the next one.
snapshot_worktree() {
  local target="$1"
  {
    printf 'head %s\n' "$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || printf 'unknown\n')"
    git -C "$PROJECT_ROOT" status --porcelain 2>/dev/null || true
  } > "$target"
}

report_orphaned_worktree() {
  local section_dir="$1"
  local before="$section_dir/.pre_dispatch.txt"
  local after="$section_dir/.post_dispatch.txt"
  [[ -f "$before" ]] || return 0
  snapshot_worktree "$after"
  if ! diff -q "$before" "$after" >/dev/null 2>&1; then
    {
      printf '# Uncommitted changes left by a failed dispatch\n\n'
      printf 'Recorded at %s for section %s.\n\n' "$(now_iso_utc)" "$(basename "$section_dir")"
      printf 'The dispatch failed after changing the working tree, and nothing\n'
      printf 'committed it. Review and either commit or discard these paths before\n'
      printf 'the section is released from quarantine.\n\n```diff\n'
      diff "$before" "$after" || true
      printf '```\n'
    } > "$section_dir/orphaned_worktree.txt"
  fi
  rm -f "$after"
}

quarantine_section() {
  local section_dir="$1"
  local action="$2"
  local exit_status="$3"
  local error_file="$4"
  {
    printf 'quarantined_at %s\n' "$(now_iso_utc)"
    printf 'action %s\n' "$action"
    printf 'exit_status %s\n' "$exit_status"
    printf 'reason\n'
    [[ ! -f "$error_file" ]] || /usr/bin/tail -n 20 "$error_file"
  } > "$section_dir/quarantine.txt"
  report_orphaned_worktree "$section_dir"
}

# One section's fatal dispatch used to end the whole run through `fail` ->
# `exit 1`, stopping every healthy section with it. The failure is now confined
# to the section that caused it.
perform_action() {
  local section_dir="$1"
  local action="$2"
  local action_status=0
  DISPATCH_SECTION_KEY="$(basename "$section_dir")"
  stamp_section_progress "$section_dir" "$action"
  snapshot_worktree "$section_dir/.pre_dispatch.txt"
  # The transition runs in its own subshell on purpose. Everything below it
  # reports a fatal condition through `fail`, which calls `exit`; without the
  # subshell that exit tears down the caller too and the quarantine below is
  # never reached.
  ( run_action "$section_dir" "$action" ) 2> "$section_dir/.last_error.txt" || action_status=$?
  if (( action_status != 0 )); then
    /usr/bin/tail -n 20 "$section_dir/.last_error.txt" >&2 || true
    quarantine_section "$section_dir" "$action" "$action_status" "$section_dir/.last_error.txt"
    printf '%s quarantined after a failed %s; the rest of the project continues\n' \
      "$(basename "$section_dir")" "$action"
  fi
  rm -f "$section_dir/.pre_dispatch.txt"
  refresh_sections_index
  return 0
}

# Sections in the order the project should work on them.
#
# Lexical order took the first line of a directory listing, so one section that
# happened to sort first took every dispatch while a zero-dependency section
# with four dependents got none. The order is: how many other sections are
# waiting on this one, then how long since it was last dispatched, then the key.
actionable_sections() {
  local section_dir action listing=""
  [[ -d "$SECTIONS_DIR" ]] || return 0
  for section_dir in "$SECTIONS_DIR"/*(/N); do
    [[ "$(basename "$section_dir")" != .* ]] || continue
    action="$(section_next_action "$section_dir")"
    case "$action" in
      idle|waiting-dependencies|quarantined) continue ;;
    esac
    listing+="$section_dir"$'\n'
  done
  [[ -n "$listing" ]] || return 0
  printf '%s' "$listing" | python3 -c '
import sys
from pathlib import Path

sections_dir = Path(sys.argv[1])
candidates = [Path(line) for line in sys.stdin.read().splitlines() if line.strip()]

dependents = {path.name: 0 for path in candidates}
for section_dir in sections_dir.iterdir():
    if not section_dir.is_dir() or section_dir.name.startswith("."):
        continue
    listing = section_dir / "dependency_handoffs.txt"
    if not listing.is_file():
        continue
    for line in listing.read_text(errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        # `.../sections/<key>/handoff.md`
        parts = line.split("/")
        if len(parts) < 2:
            continue
        key = parts[-2]
        if key in dependents and key != section_dir.name:
            dependents[key] += 1


def last_dispatch(path):
    stamp = path / "last_dispatch.txt"
    if not stamp.is_file():
        return 0
    try:
        return int(stamp.read_text().split()[0])
    except (ValueError, IndexError):
        return 0


candidates.sort(key=lambda path: (-dependents[path.name], last_dispatch(path), path.name))
print("\n".join(str(path) for path in candidates))
' "$SECTIONS_DIR"
}

stamp_dispatch_time() {
  printf '%s\n' "$(date +%s)" > "$1/last_dispatch.txt"
}

# A section can never become actionable again because something it depends on
# was cancelled. `run` used to print "run finished" and exit 0 on exactly that.
deadlocked_sections() {
  local section_dir dependencies_file relative dependency_dir dep_status
  [[ -d "$SECTIONS_DIR" ]] || return 0
  for section_dir in "$SECTIONS_DIR"/*(/N); do
    [[ "$(basename "$section_dir")" != .* ]] || continue
    [[ "$(section_next_action "$section_dir")" == "waiting-dependencies" ]] || continue
    dependencies_file="$section_dir/dependency_handoffs.txt"
    [[ -f "$dependencies_file" ]] || continue
    while IFS= read -r relative; do
      [[ -n "$relative" ]] || continue
      dependency_dir="$(dirname "$PROJECT_ROOT/$relative")"
      dep_status="$(first_line_or "$dependency_dir/status.txt" unknown)"
      if [[ "$dep_status" == "cancelled" ]] || [[ -f "$dependency_dir/quarantine.txt" ]]; then
        printf '%s waits on %s, which is %s\n' \
          "$(basename "$section_dir")" "$(basename "$dependency_dir")" \
          "$([[ -f "$dependency_dir/quarantine.txt" ]] && printf 'quarantined' || printf 'cancelled')"
        break
      fi
    done < "$dependencies_file"
  done
}

quarantined_sections() {
  local section_dir
  [[ -d "$SECTIONS_DIR" ]] || return 0
  for section_dir in "$SECTIONS_DIR"/*(/N); do
    [[ "$(basename "$section_dir")" != .* ]] || continue
    [[ -f "$section_dir/quarantine.txt" ]] || continue
    printf '%s\n' "$(basename "$section_dir")"
  done
}

cmd_tick() {
  local requested_section="${SECTION_OVERRIDE:-}"
  local section_dir action
  acquire_driver_lock
  if [[ -n "$requested_section" ]]; then
    section_dir="$(resolve_section_dir "$requested_section")"
    action="$(section_next_action "$section_dir")"
    case "$action" in
      waiting-dependencies) printf 'waiting=%s\n' "$(basename "$section_dir")"; return 0 ;;
      quarantined)          printf 'quarantined=%s\n' "$(basename "$section_dir")"; return 0 ;;
      idle)                 printf 'idle=%s\n' "$(basename "$section_dir")"; return 0 ;;
    esac
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
  # Checked here as well as inside the dispatch, so exhausting the budget stops
  # the run cleanly instead of quarantining whichever section noticed first.
  assert_within_budget "$(basename "$section_dir")"
  stamp_dispatch_time "$section_dir"
  # Capture before printing: a command substitution inside printf's arguments
  # discards the action's exit status, so a rejected action would report a
  # successful tick. cmd_run already propagates through its pipeline.
  local outcome action_status=0
  outcome="$(perform_action "$section_dir" "$action")" || action_status=$?
  printf 'result=%s\n' "$outcome"
  printf 'spent_usd=%s\n' "$(spent_usd)"
  if [[ -f "$section_dir/quarantine.txt" ]]; then
    printf 'quarantined=%s\n' "$(basename "$section_dir")"
    return 1
  fi
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

  acquire_driver_lock
  local tick=0 section_dir action quarantined deadlocked
  while (( tick < max_ticks )); do
    if [[ -n "${SECTION_OVERRIDE:-}" ]]; then
      section_dir="$(resolve_section_dir "$SECTION_OVERRIDE")"
      action="$(section_next_action "$section_dir")"
      case "$action" in
        idle|waiting-dependencies|quarantined) section_dir="" ;;
      esac
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
      break
    fi
    (( tick += 1 ))
    action="$(section_next_action "$section_dir")"
    printf '[tick %d] %s: %s ($%s spent)\n' \
      "$tick" "$(basename "$section_dir")" "$action" "$(spent_usd)"
    assert_within_budget "$(basename "$section_dir")"
    stamp_dispatch_time "$section_dir"
    perform_action "$section_dir" "$action" | sed 's/^/          /'
  done

  quarantined="$(quarantined_sections)"
  deadlocked="$(deadlocked_sections)"
  if (( tick >= max_ticks )); then
    printf 'run stopped at the %d tick budget; work remains ($%s spent)\n' "$max_ticks" "$(spent_usd)"
  else
    printf 'run finished after %d tick(s): no section has actionable work ($%s spent)\n' \
      "$tick" "$(spent_usd)"
  fi
  if [[ -n "$quarantined" ]]; then
    printf 'quarantined: %s\n' "${quarantined//$'\n'/, }"
  fi
  if [[ -n "$deadlocked" ]]; then
    printf 'deadlocked:\n%s\n' "$(printf '%s\n' "$deadlocked" | sed 's/^/  /')"
  fi
  # Non-zero only when nothing can move: every live section is quarantined, or a
  # dependency was cancelled and its dependents can never become actionable.
  if [[ -n "$deadlocked" ]]; then
    return 1
  fi
  if [[ -n "$quarantined" ]] && [[ -z "$(actionable_sections)" ]]; then
    return 1
  fi
  return 0
}

# The dispatch queue in the order the driver would work it, without dispatching
# anything. This is the cheap way to see what a run would do.
cmd_next() {
  local section_dir position=0
  for section_dir in ${(f)"$(actionable_sections)"}; do
    [[ -n "$section_dir" ]] || continue
    (( position += 1 ))
    printf '%d %-24s %s\n' "$position" "$(basename "$section_dir")" \
      "$(section_next_action "$section_dir")"
  done
  if (( position == 0 )); then
    if [[ "$(project_next_action)" == "decompose" ]]; then
      printf '1 %-24s %s\n' "(project)" "decompose"
      return 0
    fi
    printf 'nothing actionable\n'
  fi
}

cmd_status() {
  local section_dir lifecycle action deadlocked
  printf '%-24s %-10s %-22s %s\n' "SECTION" "STATUS" "NEXT ACTION" "SPENT USD"
  [[ -d "$SECTIONS_DIR" ]] || return 0
  for section_dir in "$SECTIONS_DIR"/*(/N); do
    [[ "$(basename "$section_dir")" != .* ]] || continue
    lifecycle="$(first_line_or "$section_dir/status.txt" unknown)"
    action="$(section_next_action "$section_dir")"
    printf '%-24s %-10s %-22s %s\n' "$(basename "$section_dir")" "$lifecycle" "$action" \
      "$(spent_usd "$(basename "$section_dir")")"
  done
  printf '\ntotal spent: $%s\n' "$(spent_usd)"
  deadlocked="$(deadlocked_sections)"
  [[ -z "$deadlocked" ]] || printf 'deadlocked:\n%s\n' "$(printf '%s\n' "$deadlocked" | sed 's/^/  /')"
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

  # Validate every brief before creating any of them. A decomposition that
  # failed on its fifth brief used to leave four sections created and no way to
  # retry: the project was no longer undecomposed, so the next tick never
  # offered `decompose` again.
  local index=0 problems=""
  for name in ${(f)names}; do
    index=$(( index + 1 ))
    # Matched by the index the splitter wrote, not by an unanchored suffix.
    # `client` used to match `01-ib-client.md`.
    brief_file="$(printf '%02d-%s.md' "$index" "$name")"
    if [[ ! -f "$brief_dir/briefs/$brief_file" ]]; then
      problems+="section '$name': no brief was written"$'\n'
      continue
    fi
    if ! validate_section_brief "$(/bin/cat "$brief_dir/briefs/$brief_file")" 2>/dev/null; then
      problems+="section '$name': brief is missing a required heading"$'\n'
      continue
    fi
    if ! extract_owned_paths "$(/bin/cat "$brief_dir/briefs/$brief_file")" >/dev/null 2>&1; then
      problems+="section '$name': Owned paths has no usable bullet"$'\n'
    fi
  done
  [[ -z "$problems" ]] || fail "the decomposition is not usable; nothing was created:
${problems%$'\n'}"

  # Created in the order the officer emitted them, because a dependency must
  # already exist before the section that names it.
  index=0
  for name in ${(f)names}; do
    index=$(( index + 1 ))
    brief_file="$(printf '%02d-%s.md' "$index" "$name")"
    if ! cmd_init_section "$name" --file "$brief_dir/briefs/$brief_file" >/dev/null; then
      fail "section '$name' could not be created after $created section(s) were; see $brief_dir/briefs/$brief_file"
    fi
    created=$(( created + 1 ))
  done
  printf 'decompose -> %d section(s): %s\n' "$created" "${names//$'\n'/, }"
}
