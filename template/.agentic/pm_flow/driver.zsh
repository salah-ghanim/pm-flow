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

latest_numbered_dir() {
  local parent="$1"
  [[ -d "$parent" ]] || { printf '0\n'; return; }
  local newest=0 entry name
  for entry in "$parent"/*(/N); do
    name="$(basename "$entry")"
    [[ "$name" == <-> ]] || continue
    (( name > newest )) && newest="$name"
  done
  printf '%s\n' "$newest"
}

latest_cycle() {
  latest_numbered_dir "$(section_cycles_dir "$1")"
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

# A dispatch that runs inside a section worktree has a working directory that is
# not the repository root, so a repo-relative context path resolves to nothing
# there. `begin_worktree_dispatch` sets this to `absolute` for the length of
# such a dispatch and back afterwards.
CONTEXT_PATH_STYLE="relative"

context_bullet_list() {
  local context_path
  for context_path in "$@"; do
    [[ -f "$context_path" ]] || continue
    if [[ "$CONTEXT_PATH_STYLE" == absolute ]]; then
      printf -- '- %s\n' "${context_path:A}"
    else
      printf -- '- %s\n' "$(repo_relative_path "$context_path")"
    fi
  done
}

# How a role should invoke the heartbeat script.
#
# It used to be written into the task files as `./.agentic/pm_flow/heartbeat.sh`,
# relative to the repository root. That is wrong twice over now: a dispatch in a
# section worktree has a different root, and once the engine is an installed
# package there is no copy at that path at all. The installed script's own
# location is right in every case.
heartbeat_command() {
  printf '%s/heartbeat.sh\n' "$SCRIPT_DIR"
}

# The same choice for a single path, for the prompt substitutions that name one
# file rather than a list.
dispatch_path() {
  if [[ "$CONTEXT_PATH_STYLE" == absolute ]]; then
    printf '%s\n' "${1:A}"
  else
    repo_relative_path "$1"
  fi
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

config_number() {
  python3 - "$AGENT_CONFIG_FILE" "$1" "$2" "$3" <<'PY'
import json
import sys
from pathlib import Path

config_path, section, key, default = sys.argv[1:]
config = json.loads(Path(config_path).read_text())
value = config.get(section, {}).get(key, float(default))
if not isinstance(value, (int, float)) or isinstance(value, bool) or value < 0:
    raise SystemExit(f"{section}.{key} must be a non-negative number, got {value!r}")
print(f"{float(value):.4f}")
PY
}

budget_limit() {
  config_number budget "$1" 0
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

# --- telemetry --------------------------------------------------------------
#
# The flow is the only thing that knows what a project, a topology, a section
# and a role are, so it is the thing that has to describe the work. Neither
# agent CLI can: one of them emits no GenAI semantic conventions at all, and
# neither has any concept of the section it is working on.
#
# Spans are recorded to the store as work happens and shipped to a backend
# afterwards, because an unattended run outlives whatever was listening when it
# started. `pm_flow.sh trace export` is what ships them.
#
# Nothing here may end a run. Every call is guarded and every failure swallowed:
# a broken recorder costs an observation, and a dead dispatch costs money.
#
# NOT YET CALLED. Wiring these into dispatch_role regressed the scheduling tests
# in a way that has not been explained - the dispatch stopped producing its
# output with no error on any stream - so the call sites were removed and the
# helpers left in place. Re-wire them only together with a test that proves a
# dispatch still happens, which is what `trace-commands` exists to do.

TELEMETRY_TRACE_ID=""
TELEMETRY_RUN_KEY=""
TELEMETRY_ROOT_SPAN=""
TELEMETRY_TOPOLOGY=""
TELEMETRY_ATTEMPT_ID=""
TELEMETRY_ATTEMPT_SPAN=""

telemetry_store_file() {
  printf '%s/pm_flow.db\n' "${RUNS_DIR:-}"
}

# Every variable this touches is read through `${x:-}`. Under `set -u` a bare
# reference to an unset name is fatal, and telemetry reaching a dispatch before
# the project paths are resolved would then kill the run it was only supposed to
# describe. Nothing here may be the reason a dispatch does not happen.
config_setting() {
  local config_file="${AGENT_CONFIG_FILE:-}"
  [[ -f "$config_file" ]] || { printf '%s\n' "$3"; return 0; }
  python3 - "$config_file" "$1" "$2" "$3" <<'PY_CONFIG' 2>/dev/null || printf '%s\n' "$3"
import json
import sys
from pathlib import Path

config_path, section, key, default = sys.argv[1:]
try:
    config = json.loads(Path(config_path).read_text())
except (OSError, ValueError):
    config = {}
value = config.get(section, {}).get(key, default)
if isinstance(value, bool):
    value = "1" if value else "0"
print("" if value is None else value)
PY_CONFIG
}

telemetry_enabled() {
  [[ -n "${SCRIPT_DIR:-}" && -f "$SCRIPT_DIR/telemetry.py" ]] || return 1
  # Without a resolved project there is nowhere to record to, and asking anyway
  # would dereference paths that do not exist yet.
  [[ -n "${RUNS_DIR:-}" && -n "${PROJECT_KEY:-}" ]] || return 1
  [[ "$(config_setting telemetry enabled 1)" != "0" ]]
}

# Read one `key=value` line out of a telemetry.py result.
telemetry_field() {
  printf '%s\n' "$1" | sed -n "s/^$2=//p" | /usr/bin/head -n 1
}

telemetry_begin_run() {
  local command="${1:-run}" output domain
  telemetry_enabled || return 0
  resolve_domain 2>/dev/null || true
  domain="${DOMAIN:-generic}"
  TELEMETRY_TOPOLOGY="${PM_FLOW_TOPOLOGY:-$(config_setting telemetry topology default)}"
  [[ -n "$TELEMETRY_TOPOLOGY" ]] || TELEMETRY_TOPOLOGY="default"
  mkdir -p "$RUNS_DIR" 2>/dev/null || true

  # Re-index the definitions at the top of every run. A persona or config edit
  # between runs then belongs to the run that used it, instead of being
  # attributed to whatever the store happened to hold from last time.
  python3 "$SCRIPT_DIR/catalog.py" --db "$(telemetry_store_file)" sync \
    --flow "$SCRIPT_DIR" --project "${PROJECT_KEY:-}" --domain "$domain" \
    --topology "$TELEMETRY_TOPOLOGY" >/dev/null 2>&1 || true

  output="$(python3 "$SCRIPT_DIR/telemetry.py" --db "$(telemetry_store_file)" \
    run-start --project "${PROJECT_KEY:-}" --topology "$TELEMETRY_TOPOLOGY" \
    --domain "$domain" --command "$command" 2>/dev/null)" || return 0
  TELEMETRY_RUN_KEY="$(telemetry_field "$output" run_key)"
  TELEMETRY_TRACE_ID="$(telemetry_field "$output" trace_id)"
  TELEMETRY_ROOT_SPAN="$(telemetry_field "$output" span_id)"
  [[ -n "$TELEMETRY_RUN_KEY" ]] || return 0
  export PM_FLOW_STORE="$(telemetry_store_file)"
  export PM_FLOW_RUN_KEY="$TELEMETRY_RUN_KEY"
  export PM_FLOW_TRACE_ID="$TELEMETRY_TRACE_ID"
  return 0
}

telemetry_end_run() {
  local status="${1:-ok}"
  [[ -n "$TELEMETRY_RUN_KEY" ]] || return 0
  python3 "$SCRIPT_DIR/telemetry.py" --db "$(telemetry_store_file)" run-end \
    --run "$TELEMETRY_RUN_KEY" --span "$TELEMETRY_ROOT_SPAN" \
    --status "$status" >/dev/null 2>&1 || true
  telemetry_autoexport
  return 0
}

# Ship on the way out, when an endpoint is configured. A run that finishes with
# a live collector should not need a second command to appear in it.
telemetry_autoexport() {
  local endpoint
  endpoint="$(config_setting telemetry otlp_endpoint '')"
  [[ -n "$endpoint" ]] || return 0
  python3 "$SCRIPT_DIR/trace_export.py" --db "$(telemetry_store_file)" \
    --otlp "$endpoint" >/dev/null 2>&1 || true
  return 0
}

# Open a span for one dispatch, and hand the child CLI a traceparent so a
# backend that honours W3C context nests its own spans under this one instead of
# starting a disconnected trace.
#
# Arguments are assembled into an array rather than interpolated: zsh does not
# word-split a parameter expansion, so `${key:+--task "$key"}` would arrive as a
# single argument spelled `--task mysection`.
telemetry_begin_attempt() {
  local role="$1" prompt_file="$2" label="$3" section_key="$4" output_md="$5"
  local cycle="" output parent
  TELEMETRY_ATTEMPT_ID=""
  TELEMETRY_ATTEMPT_SPAN=""
  telemetry_enabled || return 0
  [[ -n "$TELEMETRY_RUN_KEY" ]] || return 0

  # sections/<key>/cycles/007/result.md carries the cycle in its path, which is
  # the only place it exists: the driver derives state from paths rather than
  # holding it anywhere.
  if [[ "$output_md" == */cycles/* ]]; then
    cycle="${output_md##*/cycles/}"
    cycle="${cycle%%/*}"
    if [[ "$cycle" == <-> ]]; then
      cycle=$(( 10#$cycle ))
    else
      cycle=""
    fi
  fi

  local args=(--db "$(telemetry_store_file)" attempt-start
              --run "$TELEMETRY_RUN_KEY" --parent-span "$TELEMETRY_ROOT_SPAN"
              --role "$role" --label "$label" --name "$role: $label"
              --prompt-file "$prompt_file")
  [[ -z "$section_key" ]] || args+=(--task "$section_key")
  [[ -z "$cycle" ]] || args+=(--cycle "$cycle")

  output="$(python3 "$SCRIPT_DIR/telemetry.py" "${args[@]}" 2>/dev/null)" || return 0
  TELEMETRY_ATTEMPT_ID="$(telemetry_field "$output" attempt_id)"
  TELEMETRY_ATTEMPT_SPAN="$(telemetry_field "$output" span_id)"
  parent="$(telemetry_field "$output" traceparent)"
  [[ -z "$parent" ]] || export TRACEPARENT="$parent"
  return 0
}

# Close it. The backend, model and token counts are read back out of the
# response envelope rather than passed in, so the dispatcher stays the only
# thing that resolves a role to a binding.
telemetry_end_attempt() {
  local response_json="$1" output_md="$2" status="${3:-ok}"
  local events="${response_json%.json}.events.jsonl"
  unset TRACEPARENT
  [[ -n "$TELEMETRY_ATTEMPT_ID" ]] || return 0
  local args=(--db "$(telemetry_store_file)" attempt-end
              --attempt "$TELEMETRY_ATTEMPT_ID" --status "$status"
              --response "$response_json")
  [[ -z "$output_md" ]] || args+=(--output-file "$output_md")
  [[ ! -f "$events" ]] || args+=(--events "$events")
  python3 "$SCRIPT_DIR/telemetry.py" "${args[@]}" >/dev/null 2>&1 || true
  TELEMETRY_ATTEMPT_ID=""
  TELEMETRY_ATTEMPT_SPAN=""
  return 0
}

# --- governance -------------------------------------------------------------
#
# The product officer used to have three dispatch points and two of them were
# conditional on failure, so a project could run 46 dispatches and $67 without a
# single whole-product review ever being convened. Nothing was broken: nobody was
# ever summoned to look. This is the cadence that summons it whether or not
# anything has gone wrong.
#
# Every counter here is derived from files on disk, like the rest of the driver.
# What is stored is only the baseline the last review was taken at.

portfolio_dir() {
  printf '%s/portfolio\n' "$STATE_DIR"
}

# Zero disables the trigger.
portfolio_dispatch_threshold() {
  config_positive_int governance portfolio_review_dispatches 12 0
}

portfolio_idle_cycle_threshold() {
  config_positive_int governance portfolio_review_idle_cycles 8 0
}

portfolio_usd_threshold() {
  config_number governance portfolio_review_usd 20
}

# One row per dispatch. A tick count is not persisted anywhere and would not
# survive a fresh process; the ledger row is the durable unit, and a tick buys
# exactly one dispatch except at a parallel rescue.
dispatch_count() {
  local ledger count
  ledger="$(cost_ledger_file)"
  [[ -f "$ledger" ]] || { printf '0\n'; return; }
  count="$(/usr/bin/wc -l < "$ledger" | tr -d '[:space:]')"
  printf '%s\n' "${count:-0}"
}

# Arithmetic here uses the assignment form rather than `(( total += n ))`:
# `(( ))` reports the value of the expression as its exit status, so adding zero
# to zero looks like a failed command and `set -e` ends the run.
project_cycle_count() {
  local section_dir total=0
  [[ -d "$SECTIONS_DIR" ]] || { printf '0\n'; return; }
  for section_dir in "$SECTIONS_DIR"/*(/N); do
    [[ "$(basename "$section_dir")" != .* ]] || continue
    total=$(( total + $(latest_cycle "$section_dir") ))
  done
  printf '%s\n' "$total"
}

sections_with_status() {
  local wanted="$1"
  local section_dir total=0 lifecycle
  [[ -d "$SECTIONS_DIR" ]] || { printf '0\n'; return; }
  for section_dir in "$SECTIONS_DIR"/*(/N); do
    [[ "$(basename "$section_dir")" != .* ]] || continue
    lifecycle="$(first_line_or "$section_dir/status.txt" planned)"
    [[ "$lifecycle" == "$wanted" ]] || continue
    total=$(( total + 1 ))
  done
  printf '%s\n' "$total"
}

live_section_count() {
  local section_dir total=0 lifecycle
  [[ -d "$SECTIONS_DIR" ]] || { printf '0\n'; return; }
  for section_dir in "$SECTIONS_DIR"/*(/N); do
    [[ "$(basename "$section_dir")" != .* ]] || continue
    lifecycle="$(first_line_or "$section_dir/status.txt" planned)"
    case "$lifecycle" in done|cancelled) continue ;; esac
    total=$(( total + 1 ))
  done
  printf '%s\n' "$total"
}

portfolio_baseline() {
  first_line_or "$(portfolio_dir)/baseline_$1.txt" "${2:-0}"
}

record_portfolio_baseline() {
  local dir
  dir="$(portfolio_dir)"
  mkdir -p "$dir"
  printf '%s\n' "$(dispatch_count)"      > "$dir/baseline_dispatches.txt"
  printf '%s\n' "$(spent_usd)"           > "$dir/baseline_usd.txt"
  printf '%s\n' "$(project_cycle_count)" > "$dir/baseline_cycles.txt"
  printf '%s\n' "$(sections_with_status done)" > "$dir/baseline_done.txt"
  printf '%s\n' "$(now_iso_utc)"         > "$dir/last_review_at.txt"
}

portfolio_usd_since() {
  python3 -c 'import sys; print("%.4f" % (float(sys.argv[1]) - float(sys.argv[2])))' \
    "$(spent_usd)" "$(portfolio_baseline usd 0)"
}

# What triggered a review, or nothing. Whichever fires first wins; the reason is
# recorded with the review so the officer knows why it was convened.
portfolio_review_due() {
  # A project with nothing live left to steer does not need steering.
  (( $(live_section_count) > 0 )) || return 0

  local threshold since delta
  threshold="$(portfolio_dispatch_threshold)"
  if (( threshold > 0 )); then
    since=$(( $(dispatch_count) - $(portfolio_baseline dispatches 0) ))
    if (( since >= threshold )); then
      printf '%d dispatch(es) since the last portfolio review (threshold %d)\n' \
        "$since" "$threshold"
      return 0
    fi
  fi

  delta="$(portfolio_usd_since)"
  threshold="$(portfolio_usd_threshold)"
  if [[ "$(python3 -c 'import sys; print("1" if float(sys.argv[1]) > 0 and float(sys.argv[2]) >= float(sys.argv[1]) else "0")' "$threshold" "$delta")" == "1" ]]; then
    printf '$%s spent since the last portfolio review (threshold $%s)\n' "$delta" "$threshold"
    return 0
  fi

  threshold="$(portfolio_idle_cycle_threshold)"
  if (( threshold > 0 )) && \
     (( $(sections_with_status done) == $(portfolio_baseline done 0) )); then
    since=$(( $(project_cycle_count) - $(portfolio_baseline cycles 0) ))
    if (( since >= threshold )); then
      printf '%d cycle(s) since the last portfolio review with no section reaching done (threshold %d)\n' \
        "$since" "$threshold"
      return 0
    fi
  fi
  return 0
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
  # Set by begin_worktree_dispatch and empty otherwise, so a project without
  # git, or with isolation turned off, dispatches exactly as it always did.
  if [[ -n "${DISPATCH_WORK_ROOT:-}" ]]; then
    dispatch_args+=(--work-root "$DISPATCH_WORK_ROOT")
    local granted
    for granted in "${DISPATCH_EXTRA_DIRS[@]}"; do
      dispatch_args+=(--extra-dir "$granted")
    done
  fi

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

# A domain may replace what a role is asked to do on a call, the same way it may
# replace who the role is. The generic task set asks for code, tests and commits;
# a research domain asks for sourced findings and a counter-search. Overlay wins,
# generic falls through, so existing domains are unaffected.
task_file() {
  [[ -n "${DOMAIN:-}" ]] || resolve_domain
  local override="$SCRIPT_DIR/domains/$DOMAIN/tasks/$1.md"
  if [[ -f "$override" ]]; then
    printf '%s\n' "$override"
    return
  fi
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
    printf '## What is unproven\n\n- Every acceptance criterion behind the blocked dependency. Nothing here has\n'
    printf '  been demonstrated against the real system.\n\n'
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
      "$section_dir/convergence/latest.md" "$section_dir/portfolio_rescope.txt" \
      "$cycle_dir/rescope_reason.txt" "$cycle_dir/verdict_feedback.md")
$(section_dependency_context "$section_dir")
$(cycle_history_files "$section_dir" "${cycle_number#0}" "$(scope_history_window)")"
  prompt="$cycle_dir/scope_prompt.md"
  compose_role_task pm "$(task_file section_scope)" \
    "SECTION_KEY=$section_key" \
    "CYCLE=$cycle_number" \
    "CONTEXT_FILES=$context" > "$prompt"

  dispatch_role pm "$prompt" "$cycle_dir/scope.md" "" "scope $section_key $cycle_number"
  # The product officer's rescope reason has now been delivered to the manager
  # that had to act on it, so it stops riding along in every later scope.
  rm -f "$section_dir/portfolio_rescope.txt"
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

  # The developer is the role that changes code, so it is the role that runs in
  # the section's worktree. The cycle directory travels with it as a grant: the
  # assignment has to be readable and the heartbeat writable, and both live with
  # the run records rather than with the code.
  # The section directory, not just the cycle: the assignment lives in the cycle
  # but the brief and the section state are its parents, and a role that cannot
  # read its own brief is worse off inside a worktree than it was outside one.
  begin_worktree_dispatch "$(basename "$section_dir")" "$section_dir"
  context="$(context_bullet_list "$cycle_dir/assignment.md" "$section_dir/brief.md" "$section_dir/state.md")"
  prompt="$cycle_dir/develop_prompt.md"
  compose_role_task developer "$(task_file developer_assignment)" \
    "SECTION_KEY=$(basename "$section_dir")" \
    "CYCLE=$cycle_number" \
    "CONTEXT_FILES=$context" \
    "HEARTBEAT_SCRIPT=$(heartbeat_command)" \
    "HEARTBEAT_FILE=$(dispatch_path "$heartbeat")" > "$prompt"

  dispatch_role developer "$prompt" "$cycle_dir/result.md" "$heartbeat" \
    "develop $(basename "$section_dir") $cycle_number"
  end_worktree_dispatch

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
  case "$decision" in
    GO|GO_WITH_CHANGES) integrate_section_work "$section_dir" "$cycle_number" ;;
  esac
}

# An accepted cycle is the only thing that moves code out of a section's
# worktree. A rejected one leaves it on the branch, where the next cycle
# continues from it and the main tree never saw it.
integrate_section_work() {
  local section_dir="$1"
  local cycle_number="$2"
  local section_key merge_status
  worktree_isolation_enabled || return 0
  section_key="$(basename "$section_dir")"
  local tree_path
  tree_path="$(section_worktree_path "$section_key")" || return 0
  [[ -d "$tree_path" ]] || return 0
  commit_section_worktree "$tree_path" \
    "$section_key: accepted cycle $cycle_number" || true
  merge_status=0
  merge_section_worktree "$section_dir" || merge_status=$?
  case "$merge_status" in
    0) printf '        merged %s into %s\n' "$(section_worktree_branch "$section_key")" \
         "$(driver_base_branch 2>/dev/null || printf 'HEAD\n')" ;;
    2) : ;;  # nothing new on the branch; a cycle may legitimately change no code
    *) printf '        merge held back: %s\n' \
         "$(first_line_or "$section_dir/merge_blocked.txt" 'see merge_blocked.txt')" ;;
  esac
  return 0
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

  # Rescue paths are dispatched concurrently and are meant to be independent
  # attempts at the same problem, so they cannot share one tree: two of them
  # editing the same file is the whole reason the panel was convened. Each path
  # gets its own worktree, named for the path rather than the section.
  # Created before anything forks: `git worktree add` takes a repository-wide
  # lock, and several of them starting at once is a race this dispatch does not
  # need to run.
  if worktree_isolation_enabled; then
    for (( index = 1; index <= path_count; index++ )); do
      ensure_section_worktree "$(basename "$section_dir")-rescue-$index" >/dev/null 2>&1 || true
    done
  fi
  for (( index = 1; index <= path_count; index++ )); do
    local attempt_dir="$escalation_dir/rescue_$index"
    mkdir -p "$attempt_dir"
    (
      begin_worktree_dispatch "$(basename "$section_dir")-rescue-$index" "$section_dir"
      context="$(context_bullet_list "$section_dir/brief.md" \
        "$escalation_dir/failure_brief.md" "$escalation_dir/adjudication.md")"
      prompt="$attempt_dir/prompt.md"
      compose_role_task 10x_developer "$(task_file section_rescue)" \
        "SECTION_KEY=$(basename "$section_dir")" \
        "CONTEXT_FILES=$context" \
        "CHOSEN_PATH=$(printf '%s\n' "$paths" | sed -n "${index}p")" \
        "HEARTBEAT_SCRIPT=$(heartbeat_command)" \
        "HEARTBEAT_FILE=$(dispatch_path "$attempt_dir/heartbeat.txt")" > "$prompt"
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
  integrate_rescue_work "$section_dir" "$escalation_dir"
  mv "$escalation_dir" "${escalation_dir}-resolved-$(now_compact_utc)"
  printf 'review-rescue -> %s; section resumes\n' "$decision"
}

# A rescue that held still has its work sitting in one worktree per path.
#
# One path merges: there is a single answer and the review accepted it. Several
# paths do not, and must not. Parallel rescue exists so independent attempts at
# the same problem are made without seeing each other, so merging them together
# would combine two solutions to one problem into a tree neither author wrote.
# The branches are named instead and the manager chooses.
integrate_rescue_work() {
  local section_dir="$1"
  local escalation_dir="$2"
  local section_key index delivered=() attempt_dir
  worktree_isolation_enabled || return 0
  section_key="$(basename "$section_dir")"
  for attempt_dir in "$escalation_dir"/rescue_<->(/N); do
    index="${attempt_dir:t}"
    index="${index#rescue_}"
    [[ -f "$attempt_dir/result.md" ]] || continue
    commit_section_worktree "$(section_worktree_path "$section_key-rescue-$index")" \
      "$section_key: rescue path $index" >/dev/null 2>&1 || true
    delivered+=("$index")
  done
  if (( ${#delivered[@]} == 1 )); then
    local only="${delivered[1]}"
    local merged=0
    merge_rescue_branch "$section_dir" "$section_key-rescue-$only" || merged=$?
    if (( merged == 0 )); then
      printf '        merged rescue path %s\n' "$only"
    fi
  elif (( ${#delivered[@]} > 1 )); then
    {
      printf '# Rescue branches awaiting a choice\n\n'
      printf 'Parallel rescue ran %d independent attempts at the same problem, so\n' "${#delivered[@]}"
      printf 'they were not merged together: combining them would produce a tree no\n'
      printf 'author wrote. Each path is committed on its own branch. Pick one.\n\n'
      for index in "${delivered[@]}"; do
        printf -- '- path %s: `%s`\n' "$index" "$(section_worktree_branch "$section_key-rescue-$index")"
      done
    } > "$section_dir/rescue_branches.txt"
    printf '        %d rescue branches held for a choice; see rescue_branches.txt\n' \
      "${#delivered[@]}"
  fi
  for index in "${delivered[@]}"; do
    remove_section_worktree "$section_key-rescue-$index"
  done
  return 0
}

# The same merge discipline as an accepted cycle, against a branch that is not
# the section's own.
merge_rescue_branch() {
  local section_dir="$1"
  local worktree_key="$2"
  local branch base ahead
  branch="$(section_worktree_branch "$worktree_key")"
  base="$(driver_base_branch)" || return 1
  git_worktree show-ref --verify --quiet "refs/heads/$branch" || return 1
  ahead="$(git_worktree rev-list --count "$base..$branch" 2>/dev/null || printf '0\n')"
  [[ "$ahead" == <-> ]] || ahead=0
  (( ahead > 0 )) || return 2
  if ! git_worktree merge-tree --write-tree "$base" "$branch" >/dev/null 2>&1; then
    printf 'merging %s into %s conflicts; it was left on its branch\n' "$branch" "$base" \
      > "$section_dir/merge_blocked.txt"
    return 1
  fi
  if ! git_worktree merge --no-ff --no-edit \
      -m "merge($worktree_key): accepted rescue work" "$branch" >/dev/null 2>&1; then
    git_worktree merge --abort >/dev/null 2>&1 || true
    printf 'the main working tree has changes %s would overwrite; nothing merged\n' "$branch" \
      > "$section_dir/merge_blocked.txt"
    return 1
  fi
  return 0
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
    printf '## What is unproven\n\n- Everything this section was to deliver. No capability here was\n'
    printf '  demonstrated.\n\n'
    printf '## Next action\n\n- Reconcile the product plan without this section.\n'
  } > "$escalation_dir/abandon_handoff.md"
  cmd_section_handoff "$(basename "$section_dir")" cancelled "$summary" \
    --file "$escalation_dir/abandon_handoff.md" >/dev/null
  remove_section_worktree "$(basename "$section_dir")"
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
  # The section is finished, so its checkout is dead weight. The branch stays:
  # it is the history of how the section got there, and removing a worktree
  # never removes work.
  remove_section_worktree "$section_key"
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

# --- section worktrees -----------------------------------------------------
#
# Sections owning disjoint paths is an honour system. It holds only while every
# role obeys its brief, it cannot survive two sections touching the same file,
# and it cannot run two sections at once with any confidence. A git worktree per
# section makes the isolation structural instead of contractual.
#
# It is also what makes it safe for pm-flow to work on its own machinery. A
# developer rewriting driver.zsh while driver.zsh is executing the run is a live
# hazard; inside a worktree that developer is rewriting a different copy, and
# the change reaches the running engine only when a human merges the branch.
#
# Orchestration state does not move. The cycle directory, the section state and
# the handoff stay in the main tree, because the product officer and the next
# fresh process read them there. Only the code work moves: the dispatch runs
# with the worktree as its working root, and the cycle directory is granted
# alongside it so the role can still read its assignment and write its heartbeat.

DISPATCH_WORK_ROOT=""
DISPATCH_EXTRA_DIRS=()

worktree_isolation_enabled() {
  [[ "$(config_setting isolation worktrees 1)" != "0" ]] || return 1
  command -v git >/dev/null 2>&1 || return 1
  # The answer is the output, not the exit status. `rev-parse
  # --is-inside-work-tree` prints `false` and exits zero from inside a .git
  # directory, so testing the status alone calls a bare directory a worktree.
  [[ "$(git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree 2>/dev/null)" == "true" ]]
}

# Under `.git`, not under the repository. A worktree inside the working tree
# would be walked by every `find`, matched by every glob, and would need a
# .gitignore entry in a file this flow does not own.
worktrees_root() {
  local common
  common="$(git -C "$PROJECT_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  [[ -n "$common" ]] || return 1
  printf '%s/pm-flow/worktrees/%s\n' "${common%/}" "${PROJECT_KEY:-project}"
}

section_worktree_branch() {
  printf 'pm-flow/%s/%s\n' "${PROJECT_KEY:-project}" "$1"
}

section_worktree_path() {
  local root
  root="$(worktrees_root)" || return 1
  printf '%s/%s\n' "$root" "$1"
}

# The branch the driver merges into: whatever the main tree currently has
# checked out. A detached HEAD has no branch to merge into, so isolation stays
# on but the merge back is refused rather than guessed at.
driver_base_branch() {
  local branch
  branch="$(git -C "$PROJECT_ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null)" || return 1
  [[ -n "$branch" ]] || return 1
  printf '%s\n' "$branch"
}

git_worktree() {
  git -C "$PROJECT_ROOT" "$@"
}

# Create the section's worktree, or hand back the one it already has. Prints the
# path; prints nothing and fails if the worktree cannot be established, and the
# caller then dispatches against the main tree exactly as it did before.
ensure_section_worktree() {
  local section_key="$1"
  local tree_path branch
  tree_path="$(section_worktree_path "$section_key")" || return 1
  branch="$(section_worktree_branch "$section_key")"
  # A worktree, not merely a directory that happens to sit where one belongs.
  # These live under .git, where `rev-parse --is-inside-work-tree` answers for
  # the repository rather than for the path, so the check is that this path is
  # its own top level.
  local existing
  existing="$(git -C "$tree_path" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -e "$tree_path/.git" && -n "$existing" && "${existing:A}" == "${tree_path:A}" ]]; then
    printf '%s\n' "$tree_path"
    return 0
  fi
  # A directory that is not a worktree is a leftover from a killed run. Prune
  # first: git refuses to add a worktree whose administrative record still
  # exists, and that record outlives the directory.
  rm -rf -- "$tree_path"
  git_worktree worktree prune >/dev/null 2>&1 || true
  mkdir -p -- "${tree_path:h}"
  if git_worktree show-ref --verify --quiet "refs/heads/$branch"; then
    git_worktree worktree add --force "$tree_path" "$branch" >/dev/null 2>&1 || return 1
  else
    git_worktree worktree add --force -b "$branch" "$tree_path" HEAD >/dev/null 2>&1 || return 1
  fi
  printf '%s\n' "$tree_path"
}

# Bring the section's branch up to the base before it is worked on again, so a
# section is never rebuilding against a tree three merges old. Only a
# fast-forward is taken: a real merge here could conflict, and a conflict in the
# section's own worktree at the start of a cycle is a worse place to discover it
# than at the merge back, where there is a manager to tell.
sync_section_worktree() {
  local tree_path="$1"
  local base
  base="$(driver_base_branch)" || return 0
  git -C "$tree_path" merge --ff-only "$base" >/dev/null 2>&1 || true
}

# Everything the role changed, on the section's own branch. Returns 1 when there
# was nothing to commit, which is the ordinary case for a cycle that only wrote
# a report.
commit_section_worktree() {
  local tree_path="$1"
  local message="$2"
  git -C "$tree_path" add -A >/dev/null 2>&1 || return 1
  if git -C "$tree_path" diff --cached --quiet 2>/dev/null; then
    return 1
  fi
  git -C "$tree_path" \
    -c user.name="${PM_FLOW_GIT_NAME:-pm-flow}" \
    -c user.email="${PM_FLOW_GIT_EMAIL:-pm-flow@localhost}" \
    commit --quiet --no-verify -m "$message" >/dev/null 2>&1 || return 1
  return 0
}

# Merge an accepted section back into the base branch.
#
# The conflict check runs first and touches nothing: `merge-tree --write-tree`
# computes the merge in the object database and reports whether it is clean. A
# merge attempted without it would leave conflict markers in the main working
# tree, which is exactly the failure this section is forbidden to cause. On any
# refusal the branch is left intact, the reason is written next to the section,
# and the main tree is as it was.
merge_section_worktree() {
  local section_dir="$1"
  local section_key tree_path branch base reason
  section_key="$(basename "$section_dir")"
  tree_path="$(section_worktree_path "$section_key")" || return 1
  branch="$(section_worktree_branch "$section_key")"
  rm -f "$section_dir/merge_blocked.txt"

  if ! base="$(driver_base_branch)"; then
    printf 'the main tree has a detached HEAD; %s stays on its branch\n' "$branch" \
      > "$section_dir/merge_blocked.txt"
    return 1
  fi
  if ! git_worktree show-ref --verify --quiet "refs/heads/$branch"; then
    return 1
  fi
  # Nothing new on the branch is not a failure. A cycle that only produced a
  # report has nothing to merge and must not be reported as blocked.
  local ahead
  ahead="$(git_worktree rev-list --count "$base..$branch" 2>/dev/null || printf '0\n')"
  [[ "$ahead" == <-> ]] || ahead=0
  (( ahead > 0 )) || return 2
  if ! git_worktree merge-tree --write-tree "$base" "$branch" >/dev/null 2>&1; then
    {
      printf 'merging %s into %s conflicts, so nothing was merged and the main\n' "$branch" "$base"
      printf 'working tree was not touched. Resolve it in the worktree:\n\n'
      printf '  git -C %s merge %s\n\n' "$tree_path" "$base"
      printf 'then let the next accepted cycle merge it back.\n'
    } > "$section_dir/merge_blocked.txt"
    return 1
  fi
  if ! git_worktree merge --no-ff --no-edit \
      -m "merge($section_key): accepted work from $branch" "$branch" >/dev/null 2>&1; then
    # merge-tree said it was clean, so this is a local-changes refusal: git
    # stops before writing anything rather than overwrite an edit in progress.
    git_worktree merge --abort >/dev/null 2>&1 || true
    {
      printf 'the main working tree has changes that %s would overwrite, so\n' "$branch"
      printf 'nothing was merged. Commit or stash them and the next accepted\n'
      printf 'cycle will merge the section back.\n'
    } > "$section_dir/merge_blocked.txt"
    return 1
  fi
  return 0
}

remove_section_worktree() {
  local section_key="$1"
  local tree_path
  tree_path="$(section_worktree_path "$section_key")" || return 0
  [[ -d "$tree_path" ]] || return 0
  git_worktree worktree remove --force "$tree_path" >/dev/null 2>&1 || rm -rf -- "$tree_path"
  git_worktree worktree prune >/dev/null 2>&1 || true
}

# A killed run leaves worktrees behind, and git refuses to reuse a path whose
# administrative record survived the directory. Pruning at the start of every
# run means the next one never inherits that. Worktrees for sections that no
# longer exist go with it; their branches stay, so no work is destroyed.
prune_section_worktrees() {
  worktree_isolation_enabled || return 0
  local root entry key
  git_worktree worktree prune >/dev/null 2>&1 || true
  root="$(worktrees_root)" || return 0
  [[ -d "$root" ]] || return 0
  for entry in "$root"/*(/N); do
    key="$(basename "$entry")"
    [[ -d "$SECTIONS_DIR/$key" ]] && continue
    remove_section_worktree "$key"
  done
}

# The workspace a section's dispatches run in, and the directories they are
# granted. Sets DISPATCH_WORK_ROOT and DISPATCH_EXTRA_DIRS for dispatch_role,
# and CONTEXT_PATH_STYLE so the prompt names files by a path that resolves from
# there. Leaves all three at their defaults when isolation is off or the
# worktree could not be established, which is how a non-git project keeps
# working unchanged.
begin_worktree_dispatch() {
  local section_key="$1"
  shift
  DISPATCH_WORK_ROOT=""
  DISPATCH_EXTRA_DIRS=()
  CONTEXT_PATH_STYLE="relative"
  worktree_isolation_enabled || return 0
  # Never `local path`: zsh ties that name to PATH, and declaring it local
  # empties PATH for the rest of the function, so the very git this needs stops
  # being on it. It cost an afternoon once.
  local tree_path
  tree_path="$(ensure_section_worktree "$section_key")" || return 0
  [[ -n "$tree_path" ]] || return 0
  sync_section_worktree "$tree_path"
  DISPATCH_WORK_ROOT="$tree_path"
  DISPATCH_EXTRA_DIRS=("$@")
  CONTEXT_PATH_STYLE="absolute"
  return 0
}

end_worktree_dispatch() {
  DISPATCH_WORK_ROOT=""
  DISPATCH_EXTRA_DIRS=()
  CONTEXT_PATH_STYLE="relative"
}

# The tree a section's dispatches actually change. With isolation on that is the
# section's worktree, and watching the main tree instead would report every
# dispatch as having changed nothing.
section_tree_root() {
  local section_key="$1"
  local tree_path
  if worktree_isolation_enabled && tree_path="$(section_worktree_path "$section_key")" \
      && [[ -d "$tree_path" ]]; then
    printf '%s\n' "$tree_path"
    return 0
  fi
  printf '%s\n' "$PROJECT_ROOT"
}

# The repository as the dispatch found it, so a failed dispatch's leftovers can
# be named rather than silently inherited by the next one.
snapshot_worktree() {
  local target="$1"
  local tree="${2:-$PROJECT_ROOT}"
  {
    printf 'head %s\n' "$(git -C "$tree" rev-parse HEAD 2>/dev/null || printf 'unknown\n')"
    git -C "$tree" status --porcelain 2>/dev/null || true
  } > "$target"
}

report_orphaned_worktree() {
  local section_dir="$1"
  local before="$section_dir/.pre_dispatch.txt"
  local after="$section_dir/.post_dispatch.txt"
  [[ -f "$before" ]] || return 0
  snapshot_worktree "$after" "$(section_tree_root "$(basename "$section_dir")")"
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
  snapshot_worktree "$section_dir/.pre_dispatch.txt" \
    "$(section_tree_root "$(basename "$section_dir")")"
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
  prune_section_worktrees
  if [[ -n "$requested_section" ]]; then
    section_dir="$(resolve_section_dir "$requested_section")"
    action="$(section_next_action "$section_dir")"
    case "$action" in
      waiting-dependencies) printf 'waiting=%s\n' "$(basename "$section_dir")"; return 0 ;;
      quarantined)          printf 'quarantined=%s\n' "$(basename "$section_dir")"; return 0 ;;
      idle)                 printf 'idle=%s\n' "$(basename "$section_dir")"; return 0 ;;
    esac
  else
    # Project-level work comes first. A portfolio review that only ran when no
    # section was actionable would never run at all: there is always a section
    # willing to scope another cycle.
    local project_action
    project_action="$(project_next_action)"
    case "$project_action" in
      decompose|portfolio-review)
        printf 'section=%s\n' "(project)"
        printf 'action=%s\n' "$project_action"
        if [[ "$project_action" == "decompose" ]]; then
          printf 'result=%s\n' "$(do_decompose)"
        else
          printf 'result=%s\n' "$(run_portfolio_review)"
        fi
        printf 'spent_usd=%s\n' "$(spent_usd)"
        return 0
        ;;
    esac
    section_dir="$(first_line_of "$(actionable_sections)")"
    if [[ -z "$section_dir" ]]; then
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
  # A killed run leaves worktrees whose administrative record outlives the
  # directory, and git then refuses to reuse the path. Clearing that once per
  # run is what keeps a crash from blocking the next one.
  prune_section_worktrees
  local tick=0 section_dir action quarantined deadlocked project_action
  while (( tick < max_ticks )); do
    if [[ -n "${SECTION_OVERRIDE:-}" ]]; then
      section_dir="$(resolve_section_dir "$SECTION_OVERRIDE")"
      action="$(section_next_action "$section_dir")"
      case "$action" in
        idle|waiting-dependencies|quarantined) section_dir="" ;;
      esac
    else
      # Project-level work preempts section work. There is always a section
      # willing to scope one more cycle, so a review that waited for an idle
      # queue would never be convened.
      project_action="$(project_next_action)"
      case "$project_action" in
        decompose)
          (( tick += 1 ))
          printf '[tick %d] (project): decompose\n' "$tick"
          do_decompose | sed 's/^/          /'
          continue
          ;;
        portfolio-review)
          (( tick += 1 ))
          printf '[tick %d] (project): portfolio review ($%s spent)\n' "$tick" "$(spent_usd)"
          run_portfolio_review | sed 's/^/          /'
          continue
          ;;
      esac
      section_dir="$(first_line_of "$(actionable_sections)")"
    fi
    if [[ -z "$section_dir" ]]; then
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
  local section_dir position=0 project_action
  project_action="$(project_next_action)"
  case "$project_action" in
    decompose|portfolio-review)
      position=1
      printf '%d %-24s %s\n' "$position" "(project)" "$project_action"
      ;;
  esac
  for section_dir in ${(f)"$(actionable_sections)"}; do
    [[ -n "$section_dir" ]] || continue
    (( position += 1 ))
    printf '%d %-24s %s\n' "$position" "$(basename "$section_dir")" \
      "$(section_next_action "$section_dir")"
  done
  (( position > 0 )) || printf 'nothing actionable\n'
}

cmd_status() {
  local section_dir lifecycle action deadlocked due reviews
  printf '%-24s %-13s %-10s %-22s %s\n' "SECTION" "PRIORITY" "STATUS" "NEXT ACTION" "SPENT USD"
  [[ -d "$SECTIONS_DIR" ]] || return 0
  for section_dir in "$SECTIONS_DIR"/*(/N); do
    [[ "$(basename "$section_dir")" != .* ]] || continue
    lifecycle="$(first_line_or "$section_dir/status.txt" unknown)"
    action="$(section_next_action "$section_dir")"
    printf '%-24s %-13s %-10s %-22s %s\n' "$(basename "$section_dir")" \
      "$(section_priority "$section_dir")" "$lifecycle" "$action" \
      "$(spent_usd "$(basename "$section_dir")")"
  done
  printf '\ntotal spent: $%s\n' "$(spent_usd)"
  reviews="$(latest_numbered_dir "$(portfolio_dir)")"
  due="$(portfolio_review_due)"
  printf 'portfolio reviews: %s (last at %s)\n' "$reviews" \
    "$(first_line_or "$(portfolio_dir)/last_review_at.txt" never)"
  [[ -z "$due" ]] || printf 'portfolio review due: %s\n' "$due"
  deadlocked="$(deadlocked_sections)"
  [[ -z "$deadlocked" ]] || printf 'deadlocked:\n%s\n' "$(printf '%s\n' "$deadlocked" | sed 's/^/  /')"
}

# --- project level ---------------------------------------------------------

# The product officer cuts the product into sections once, before any section
# work exists, and reviews the whole portfolio on a cadence after that. This is
# derived like everything else: no sections on disk means the project has not
# been decomposed yet.
project_next_action() {
  local section_dir decomposed=0
  if [[ -d "$SECTIONS_DIR" ]]; then
    for section_dir in "$SECTIONS_DIR"/*(/N); do
      [[ "$(basename "$section_dir")" != .* ]] || continue
      decomposed=1
      break
    done
  fi
  if (( decomposed == 0 )); then
    printf 'decompose\n'
    return
  fi
  if [[ -n "$(portfolio_review_due)" ]]; then
    printf 'portfolio-review\n'
    return
  fi
  printf 'idle\n'
}

# One bounded row per section: what it is for, what it costs, and whether it is
# waiting on something that has never been dispatched. This is the only bulk
# reading the officer is given, and it is deliberately a table rather than a
# document.
portfolio_facts() {
  local section_dir key lifecycle cycles waiting dependency dependency_dir
  printf '# Section facts, as the driver observes them\n\n'
  printf 'Derived from files on disk, not from anybody reporting. Treat every claim\n'
  printf 'in a handoff as unverified until a probe of your own says otherwise.\n\n'
  printf '| section | priority | status | cycles | spent | waiting on |\n'
  printf '| --- | --- | --- | --- | --- | --- |\n'
  [[ -d "$SECTIONS_DIR" ]] || return 0
  for section_dir in "$SECTIONS_DIR"/*(/N); do
    key="$(basename "$section_dir")"
    [[ "$key" != .* ]] || continue
    lifecycle="$(first_line_or "$section_dir/status.txt" planned)"
    cycles="$(latest_cycle "$section_dir")"
    waiting=""
    if [[ -f "$section_dir/dependency_handoffs.txt" ]]; then
      while IFS= read -r dependency; do
        [[ -n "$dependency" ]] || continue
        dependency_dir="$(dirname "$PROJECT_ROOT/$dependency")"
        waiting+="$(basename "$dependency_dir") (cycles $(latest_cycle "$dependency_dir"), $(first_line_or "$dependency_dir/status.txt" unknown)) "
      done < "$section_dir/dependency_handoffs.txt"
    fi
    printf '| %s | %s | %s | %s | %s | %s |\n' \
      "$key" "$(section_priority "$section_dir")" "$lifecycle" "$cycles" \
      "$(spent_usd "$key")" "${waiting:-nothing}"
  done
  printf '\n'
}

# Parse the officer's verdicts. Writes two TSVs and refuses the review rather
# than acting on half of it: a portfolio review that cannot be read is cheaper
# to re-ask than a CUT applied to the wrong section.
portfolio_parse_review() {
  local review_md="$1"
  local live_keys="$2"
  local verdicts_out="$3"
  local plan_out="$4"
  python3 - "$review_md" "$live_keys" "$verdicts_out" "$plan_out" <<'PY'
import re
import sys
from pathlib import Path

review_md, live_csv, verdicts_out, plan_out = sys.argv[1:5]
text = Path(review_md).read_text()
live = [key for key in live_csv.split(",") if key]

WANTED = {"verdicts", "plan structure", "shortest path"}

# A heading is an atx line or a bold-only line. A bare numbered line counts too,
# but only when it names one of the sections being looked for, so a numbered
# verdict line never reads as a section boundary.
atx_re = re.compile(r"^\s*#{1,6}\s+(?:\d+[.)]\s*)?\**\s*(.+?)\s*\**\s*:?\s*$")
bold_re = re.compile(r"^\s*(?:\d+[.)]\s*)?\*\*(.+?)\*\*\s*:?\s*$")
numbered_re = re.compile(r"^\s*\d+[.)]\s*\**(.+?)\**\s*:?\s*$")


def heading_name(line):
    for pattern in (atx_re, bold_re):
        match = pattern.match(line)
        if match:
            return match.group(1).strip().lower()
    match = numbered_re.match(line)
    if match and match.group(1).strip().lower() in WANTED:
        return match.group(1).strip().lower()
    return None


blocks, current, buffer = {}, None, []
for line in text.splitlines():
    name = heading_name(line)
    if name is not None:
        if current:
            blocks.setdefault(current, []).extend(buffer)
        current = name if name in WANTED else None
        buffer = []
        continue
    if current:
        buffer.append(line)
if current:
    blocks.setdefault(current, []).extend(buffer)

problems = []

verdict_re = re.compile(
    r"^\s*(?:[-*+]|\d+[.)])?\s*`?(?P<key>[A-Za-z0-9][A-Za-z0-9_-]*)`?\s*[:|-]\s*"
    r"(?P<verdict>CONTINUE|RESCOPE|CUT|BLOCK)\b[\s:,.-]*(?P<reason>.*?)\s*$"
)
verdicts, unknown = {}, []
for line in blocks.get("verdicts", []):
    match = verdict_re.match(line)
    if not match:
        continue
    key = match.group("key")
    verdict = match.group("verdict")
    reason = match.group("reason").strip().strip("`*_ ")
    if key not in live:
        unknown.append(key)
        continue
    if verdict != "CONTINUE" and not reason:
        problems.append(
            f"the {verdict} on {key} states no reason; it is what gets recorded "
            f"against the section, so it is required"
        )
        continue
    verdicts[key] = (verdict, reason)

if not verdicts and not problems:
    problems.append(
        "the Verdicts section has no readable line; use `- <section-key>: "
        "CONTINUE|RESCOPE|CUT|BLOCK <reason>`"
    )
if unknown:
    problems.append(
        "these are not section keys in this project: " + ", ".join(sorted(set(unknown)))
    )

CHECKS = {
    "unstarted dependency": "UNSTARTED_DEPENDENCY",
    "unreachable section": "UNREACHABLE_SECTION",
    "must-have inflation": "MUST_HAVE_INFLATION",
    "linear-chain risk": "LINEAR_CHAIN_RISK",
}
check_re = re.compile(
    r"^\s*(?:[-*+]|\d+[.)])?\s*\**(?P<label>[A-Za-z][A-Za-z -]*?)\**\s*[:|-]\s*"
    r"(?P<verdict>FOUND|CLEAR)\b[\s:,.-]*(?P<detail>.*?)\s*$",
    re.I,
)
checks = {}
for line in blocks.get("plan structure", []):
    match = check_re.match(line)
    if not match:
        continue
    label = " ".join(match.group("label").split()).lower()
    if label not in CHECKS:
        continue
    verdict = match.group("verdict").upper()
    detail = match.group("detail").strip().strip("`*_ ")
    if verdict == "FOUND" and not detail:
        problems.append(f"the {label} check reports FOUND but names nothing")
        continue
    checks[CHECKS[label]] = (verdict, detail)

missing = [name for label, name in CHECKS.items() if name not in checks]
if missing:
    problems.append(
        "the Plan structure section is missing a FOUND or CLEAR line for: "
        + ", ".join(missing)
    )

if not "".join(blocks.get("shortest path", [])).strip():
    problems.append("the Shortest path section is empty")

if problems:
    raise SystemExit("\n".join(f"- {problem}" for problem in problems))

# A section the officer did not judge continues. Silence is not a cut.
rows = []
for key in live:
    verdict, reason = verdicts.get(key, ("CONTINUE", "not judged in this review"))
    rows.append(f"{key}\t{verdict}\t{reason}")
Path(verdicts_out).write_text("\n".join(rows) + "\n")
Path(plan_out).write_text(
    "\n".join(f"{name}\t{value[0]}\t{value[1]}" for name, value in checks.items()) + "\n"
)
PY
}

portfolio_log_entries() {
  config_positive_int governance portfolio_log_full_entries 4 1
}

# The officer is a fresh process every time, so without this it re-derives its
# whole view on each review and cannot see slow failure: a section that has been
# nearly done for four reviews, or a shortest path that has not changed in
# three. Older entries are compacted to their summary line so the log stays
# readable in a context that is meant to stay small.
portfolio_log_append() {
  local review_md="$1"
  local log_md="$2"
  local index="$3"
  local spend="$4"
  local keep="$5"
  python3 - "$review_md" "$log_md" "$index" "$spend" "$keep" <<'PY'
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

review_md, log_md, index, spend, keep = sys.argv[1:6]
keep = int(keep)
text = Path(review_md).read_text()

WANTED = {"completion criteria", "verdicts", "shortest path"}
atx_re = re.compile(r"^\s*#{1,6}\s+(?:\d+[.)]\s*)?\**\s*(.+?)\s*\**\s*:?\s*$")
bold_re = re.compile(r"^\s*(?:\d+[.)]\s*)?\*\*(.+?)\*\*\s*:?\s*$")
numbered_re = re.compile(r"^\s*\d+[.)]\s*\**(.+?)\**\s*:?\s*$")


def heading_name(line):
    for pattern in (atx_re, bold_re):
        match = pattern.match(line)
        if match:
            return match.group(1).strip().lower()
    match = numbered_re.match(line)
    if match and match.group(1).strip().lower() in WANTED:
        return match.group(1).strip().lower()
    return None


blocks, current, buffer = {}, None, []
for line in text.splitlines():
    name = heading_name(line)
    if name is not None:
        if current:
            blocks.setdefault(current, []).extend(buffer)
        current = name if name in WANTED else None
        buffer = []
        continue
    if current:
        buffer.append(line)
if current:
    blocks.setdefault(current, []).extend(buffer)


def lines_of(name):
    return [line.rstrip() for line in blocks.get(name, []) if line.strip()]


criteria = lines_of("completion criteria")
verdicts = lines_of("verdicts")
path_lines = lines_of("shortest path")
met = sum(1 for line in criteria if re.search(r"\bMET\b", line)
          and not re.search(r"\bNOT\s+MET\b", line, re.I))
tally = {}
for line in verdicts:
    found = re.search(r"\b(CONTINUE|RESCOPE|CUT|BLOCK)\b", line)
    if found:
        tally[found.group(1)] = tally.get(found.group(1), 0) + 1
shortest = re.sub(r"^\s*(?:[-*+]|\d+[.)])\s*", "", path_lines[0]).strip() if path_lines else "not stated"
if len(shortest) > 160:
    shortest = shortest[:157] + "..."

stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
summary = (
    f"- Summary: {met} of {len(criteria)} criteria met; verdicts "
    + (", ".join(f"{name} {count}" for name, count in sorted(tally.items())) or "none")
    + f"; shortest path: {shortest}"
)

entry = [f"## Review {int(index):03d} - {stamp} - ${spend} spent", "", summary, ""]
for title, body in (
    ("Completion criteria", criteria),
    ("Verdicts", verdicts),
    ("Shortest path", path_lines),
):
    entry.extend([f"### {title}", ""])
    entry.extend(body or ["- not stated"])
    entry.append("")

HEADER = [
    "# Portfolio review log",
    "",
    "Newest first. Read this before anything else: one review cannot see a",
    "section that has been nearly done for four of them, or a shortest path that",
    "has not moved in three. Older entries are compacted to their summary line.",
    "",
]

existing = []
if Path(log_md).is_file():
    body = Path(log_md).read_text()
    parts = re.split(r"(?m)^(?=##\s+Review\s)", body)
    existing = [part.rstrip() for part in parts[1:] if part.strip()]


def compact(block):
    head = block.splitlines()[0]
    for line in block.splitlines():
        if line.startswith("- Summary:"):
            return f"{head}\n\n{line}"
    return head


kept = [entry_text for entry_text in existing[: max(keep - 1, 0)]]
older = [compact(entry_text) for entry_text in existing[max(keep - 1, 0):]]
Path(log_md).write_text(
    "\n".join(HEADER + ["\n".join(entry).rstrip(), ""] + [b + "\n" for b in kept + older])
)
PY
}

# The officer's verdict, published over the section through the same path a
# manager's handoff takes: the same validation, the same locking, the same index
# refresh. A CUT that did not go through here would leave a cancelled section
# with a live handoff still claiming otherwise.
publish_governance_handoff() {
  local section_dir="$1"
  local section_status="$2"
  local headline="$3"
  local reason="$4"
  local unproven="$5"
  local next_action="$6"
  local section_key summary handoff
  section_key="$(basename "$section_dir")"
  summary="$headline: $reason"
  summary="${summary//$'\n'/ }"
  (( ${#summary} <= 200 )) || summary="${summary[1,197]}..."
  handoff="$section_dir/.governance_handoff.md"
  {
    printf '## Outcome\n\n- %s\n\n' "$summary"
    printf '## Decisions\n\n- The product officer decided this in a portfolio review, against the\n'
    printf '  mission and the evidence it probed, not against this section reporting.\n\n'
    printf '## Interfaces\n\n- Nothing new. Any section expecting this capability must be reconciled\n'
    printf '  without it.\n\n'
    printf '## Risks\n\n- %s\n\n' "$reason"
    printf '## What is unproven\n\n- %s\n\n' "$unproven"
    printf '## Next action\n\n- %s\n' "$next_action"
  } > "$handoff"
  cmd_section_handoff "$section_key" "$section_status" "$summary" --file "$handoff" >/dev/null
  rm -f "$handoff"
}

apply_portfolio_verdict() {
  local key="$1"
  local verdict="$2"
  local reason="$3"
  local section_dir="$SECTIONS_DIR/$key"
  if [[ ! -d "$section_dir" ]]; then
    printf '  %s -> %s ignored: no such section\n' "$key" "$verdict"
    return 0
  fi
  case "$verdict" in
    CONTINUE)
      printf '  %s -> CONTINUE\n' "$key"
      ;;
    RESCOPE)
      {
        printf '# Rescoped by a portfolio review\n\n'
        printf 'The product officer reviewed the whole product on %s and rescoped\n' "$(now_iso_utc)"
        printf 'this section. What has to change:\n\n- %s\n\n' "$reason"
        printf 'Scope the next cycle against this, not against the previous cycle.\n'
      } > "$section_dir/portfolio_rescope.txt"
      printf '  %s -> RESCOPE (%s)\n' "$key" "$reason"
      ;;
    CUT)
      publish_governance_handoff "$section_dir" cancelled "Cut by a portfolio review" \
        "$reason" \
        "Everything this section was to deliver; it was cut before proving any of it." \
        "Reconcile the product plan without this section."
      printf '  %s -> CUT (%s)\n' "$key" "$reason"
      ;;
    BLOCK)
      publish_governance_handoff "$section_dir" blocked "Blocked by a portfolio review" \
        "$reason" \
        "Every acceptance criterion behind the blocker named above." \
        "Resolve the blocker, then reopen this section with an active handoff."
      printf '  %s -> BLOCK (%s)\n' "$key" "$reason"
      ;;
    *)
      printf '  %s -> %s ignored: not a portfolio verdict\n' "$key" "$verdict"
      ;;
  esac
}

live_section_keys() {
  local section_dir key lifecycle listing=""
  [[ -d "$SECTIONS_DIR" ]] || return 0
  for section_dir in "$SECTIONS_DIR"/*(/N); do
    key="$(basename "$section_dir")"
    [[ "$key" != .* ]] || continue
    lifecycle="$(first_line_or "$section_dir/status.txt" planned)"
    case "$lifecycle" in done|cancelled) continue ;; esac
    listing+="$key,"
  done
  printf '%s\n' "${listing%,}"
}

do_portfolio_review() {
  local dir review_dir index prompt context decision due keys
  dir="$(portfolio_dir)"
  mkdir -p "$dir"
  due="$(portfolio_review_due)"
  index="$(latest_numbered_dir "$dir")"
  # A review whose verdicts could not be read is re-asked in its own directory
  # rather than opening another, exactly as an UNPARSED cycle is.
  if (( index == 0 )) || [[ -f "$dir/$(printf '%03d' "$index")/verdicts.tsv" ]]; then
    index=$(( index + 1 ))
  fi
  review_dir="$dir/$(printf '%03d' "$index")"
  mkdir -p "$review_dir"
  claim_step "$review_dir/.claim-portfolio-review"
  printf '%s\n' "${due:-convened by hand}" > "$review_dir/trigger.txt"
  portfolio_facts > "$review_dir/facts.md"

  local handoffs="" section_dir key lifecycle
  for section_dir in "$SECTIONS_DIR"/*(/N); do
    key="$(basename "$section_dir")"
    [[ "$key" != .* ]] || continue
    lifecycle="$(first_line_or "$section_dir/status.txt" planned)"
    case "$lifecycle" in done|cancelled) continue ;; esac
    handoffs+="$(context_bullet_list "$section_dir/handoff.md")"$'\n'
  done

  context="$(context_bullet_list "$STATE_DIR/plan.md" "$STATE_DIR/portfolio_log.md" \
      "$CONTRACT_FILE" "$SECTIONS_INDEX_FILE" "$review_dir/facts.md" \
      "$review_dir/verdict_feedback.md")
${handoffs%$'\n'}"

  prompt="$review_dir/prompt.md"
  compose_role_task cpo "$(task_file portfolio_review)" \
    "DISPATCHES_SINCE=$(( $(dispatch_count) - $(portfolio_baseline dispatches 0) ))" \
    "CYCLES_SINCE=$(( $(project_cycle_count) - $(portfolio_baseline cycles 0) ))" \
    "SPEND_SINCE=\$$(portfolio_usd_since)" \
    "DONE_SECTIONS=$(sections_with_status done)" \
    "CONTEXT_FILES=$context" > "$prompt"

  dispatch_role cpo "$prompt" "$review_dir/review.md" "" "portfolio review $index"

  decision="$(record_cycle_decision "$review_dir" "$review_dir/review.md" "ON_TRACK,OFF_TRACK")"
  if [[ "$decision" == "UNPARSED" ]]; then
    printf 'portfolio review %03d -> UNPARSED; it will be re-asked\n' "$index"
    return 0
  fi

  keys="$(live_section_keys)"
  if ! portfolio_parse_review "$review_dir/review.md" "$keys" \
      "$review_dir/.verdicts.staging" "$review_dir/.plan_structure.staging" \
      2> "$review_dir/.parse_error.txt"; then
    {
      printf 'The portfolio review at %s could not be acted on.\n\n' \
        "$(repo_relative_path "$review_dir/review.md")"
      /bin/cat "$review_dir/.parse_error.txt"
      printf '\nAnswer again. Keep everything you already wrote and fix only these.\n'
    } > "$review_dir/verdict_feedback.md"
    rm -f "$review_dir/.parse_error.txt" "$review_dir/.verdicts.staging" \
      "$review_dir/.plan_structure.staging"
    printf 'portfolio review %03d -> verdicts unreadable; it will be re-asked\n' "$index"
    return 0
  fi
  rm -f "$review_dir/.parse_error.txt" "$review_dir/verdict_feedback.md"
  mv "$review_dir/.plan_structure.staging" "$review_dir/plan_structure.tsv"
  mv "$review_dir/.verdicts.staging" "$review_dir/verdicts.tsv"

  portfolio_log_append "$review_dir/review.md" "$STATE_DIR/portfolio_log.md" \
    "$index" "$(spent_usd)" "$(portfolio_log_entries)"
  /bin/cp "$review_dir/review.md" "$dir/latest.md"

  printf 'portfolio review %03d -> %s (%s)\n' "$index" "$decision" "${due:-convened by hand}"
  local verdict reason
  while IFS=$'\t' read -r key verdict reason; do
    [[ -n "$key" ]] || continue
    apply_portfolio_verdict "$key" "$verdict" "$reason"
  done < "$review_dir/verdicts.tsv"
  while IFS=$'\t' read -r key verdict reason; do
    [[ "$verdict" == "FOUND" ]] || continue
    printf '  plan structure: %s - %s\n' "$key" "$reason"
  done < "$review_dir/plan_structure.tsv"

  record_portfolio_baseline
  refresh_sections_index
}

# A governance dispatch that dies must not wedge the run. The baseline advances
# so the next tick returns to section work, and the failure is left on disk.
run_portfolio_review() {
  assert_within_budget
  # Not named `status`: zsh ties that name to `$?` and makes it read-only, so
  # `local status=0` fails and takes the whole review with it.
  local review_status=0
  ( do_portfolio_review ) || review_status=$?
  if (( review_status != 0 )); then
    printf '%s\n' "$(now_iso_utc)" > "$(portfolio_dir)/last_failure.txt"
    record_portfolio_baseline
    printf 'portfolio review failed; the baseline advanced and the run continues\n'
  fi
  return 0
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

required = ["Objective", "Scope", "Priority", "Owned paths", "Dependencies",
            "Acceptance", "Rejection conditions"]
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
    if ! extract_section_priority "$(/bin/cat "$brief_dir/briefs/$brief_file")" >/dev/null 2>&1; then
      problems+="section '$name': Priority must be must-have or nice-to-have plus what the product loses"$'\n'
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

# --- on demand --------------------------------------------------------------
#
# The loop above is the only thing that decides when high-level work happens: a
# portfolio review waits for a governance threshold, a manager only speaks at a
# scope or a review, and a panel only convenes after repeated failure. The owner
# has no way in. These three commands are that way in.
#
# Each takes the driver lock rather than queueing behind it. A hand-run command
# that waited would dispatch into the middle of somebody else's tick, against
# state that changed while it waited.

# The same review the thresholds convene: same prompt, same verdict parsing, and
# the verdicts take effect the same way. It advances the governance baseline on
# success, so asking for one does not leave the loop about to ask for another.
cmd_portfolio_review() {
  (( $# == 0 )) || fail "portfolio-review takes no arguments"
  [[ "$(project_next_action)" != "decompose" ]] || \
    fail "this project has no sections yet; decompose it before reviewing the portfolio"
  acquire_driver_lock
  run_portfolio_review
  printf 'spent_usd=%s\n' "$(spent_usd)"
}

# One section's manager, asked where the section stands, outside a cycle.
#
# The scope call is the only place a manager currently speaks about its own
# section, and it can only answer by opening a cycle. This asks the same role
# the same kind of question and opens nothing: no cycle directory, no
# assignment, no verdict, and nothing downstream reads the answer.
cmd_section_analysis() {
  local section_input="${1:-}"
  [[ -n "$section_input" ]] || fail "section-analysis requires a section name"
  local body_mode="" body_path=""
  if [[ "${2:-}" == "--file" ]]; then
    body_mode="file"
    body_path="${3:-}"
  elif [[ -n "${2:-}" ]]; then
    fail "unknown section-analysis argument: ${2:-}"
  fi

  local section_dir section_key
  section_dir="$(resolve_section_dir "$section_input")"
  section_key="$(basename "$section_dir")"

  local question=""
  if [[ -n "$body_mode" ]]; then
    question="$(read_body_arg "$body_mode" "$body_path")"
    [[ -n "$question" ]] || fail "the focusing question must not be empty"
  fi

  acquire_driver_lock
  assert_within_budget "$section_key"

  local analysis_dir cycles_before
  analysis_dir="$section_dir/analysis/$(now_compact_utc)"
  mkdir -p "$analysis_dir"
  cycles_before="$(latest_cycle "$section_dir")"
  [[ -z "$question" ]] || printf '%s\n' "$question" > "$analysis_dir/question.md"

  local context prompt
  context="$(context_bullet_list "$section_dir/brief.md" "$section_dir/state.md" \
      "$section_dir/handoff.md" "$CONTRACT_FILE" "$analysis_dir/question.md" \
      "$section_dir/convergence/latest.md")
$(section_dependency_context "$section_dir")
$(cycle_history_files "$section_dir" "$(( cycles_before + 1 ))" "$(scope_history_window)")"
  prompt="$analysis_dir/prompt.md"
  compose_role_task pm "$(task_file section_analysis)" \
    "SECTION_KEY=$section_key" \
    "CYCLE=$(printf '%03d' "$cycles_before")" \
    "CONTEXT_FILES=$context" > "$prompt"

  dispatch_role pm "$prompt" "$analysis_dir/analysis.md" "" \
    "analysis $section_key" "$section_key"
  /bin/cp "$analysis_dir/analysis.md" "$section_dir/analysis/latest.md"

  # Nothing here writes a cycle, but the dispatched manager can write anywhere in
  # the project workspace. A cycle that appeared during an assessment is the one
  # failure this command cannot leave silent.
  local cycles_after
  cycles_after="$(latest_cycle "$section_dir")"
  if [[ "$cycles_after" != "$cycles_before" ]]; then
    printf 'WARNING: the analysis dispatch changed the cycle count from %s to %s; inspect %s\n' \
      "$cycles_before" "$cycles_after" "$(repo_relative_path "$section_dir/cycles")" >&2
  fi
  if grep -qE '^[[:space:]]*(ASSIGN|COMPLETE|BLOCKED_EXTERNAL)\b' "$analysis_dir/analysis.md"; then
    printf 'WARNING: the analysis answered with a scope verdict; no cycle was opened and nothing acts on it\n' >&2
  fi

  printf 'recorded=section-analysis\n'
  printf 'section=%s\n' "$section_key"
  printf 'analysis=%s\n' "$analysis_dir/analysis.md"
  printf 'cycles=%s\n' "$cycles_after"
  printf 'spent_usd=%s\n' "$(spent_usd)"
}

# The consultant panel, convened on a question instead of on a failure.
#
# The seats run through the same dispatcher as the failure panel, in parallel
# and blind to each other, and the product officer adjudicates through the same
# task. Only what the seats are told to read differs.
cmd_proposals() {
  local name_input="${1:-}"
  [[ -n "$name_input" ]] || fail "proposals requires a name for the panel"
  local body_mode="stdin" body_path=""
  if [[ "${2:-}" == "--file" ]]; then
    body_mode="file"
    body_path="${3:-}"
  elif [[ -n "${2:-}" ]]; then
    fail "unknown proposals argument: ${2:-}"
  fi

  local name question
  name="$(slugify "$name_input")"
  question="$(read_body_arg "$body_mode" "$body_path")"
  [[ -n "$question" ]] || fail "the question must not be empty"

  acquire_driver_lock
  assert_within_budget

  local panel_dir
  panel_dir="$PROJECT_DIR/panels/$name/$(now_compact_utc)"
  mkdir -p "$panel_dir"
  printf '%s\n' "$question" > "$panel_dir/question.md"

  local consultant_persona="$panel_dir/consultant_prompt.md"
  {
    compose_role_prompt consultant
    printf '\n---\n\n# The question\n\n'
    printf 'Panel: %s\n\n' "$name"
    printf 'Read `%s` for the question you are answering' \
      "$(repo_relative_path "$panel_dir/question.md")"
    if [[ -f "$STATE_DIR/plan.md" ]]; then
      printf ', and `%s` for what the product is for' "$(repo_relative_path "$STATE_DIR/plan.md")"
    fi
    printf '.\n\n'
    printf 'You are one seat of a panel answering that question at the same time as\n'
    printf 'the others. You cannot see their answers and they cannot see yours, so\n'
    printf 'answer the question you were asked rather than covering every position.\n\n'
    printf 'Respond with these sections only, each as a Markdown heading:\n'
    printf '1. What the question turns on\n2. Prior art considered\n3. Proposals\n'
    printf '4. What would prove each one\n5. Recommendation\n\n'
    printf 'Give at least two proposals, each naming what it costs and what it gives\n'
    printf 'up. Recommendation must be exactly one line: the proposal you would take,\n'
    printf 'and the one observation that would change your mind.\n'
  } > "$consultant_persona"

  run_panel_seats "$panel_dir" "$consultant_persona"

  local panel_files
  panel_files="$(panel_proposal_bullets "$panel_dir")"
  panel_files+="- Question: $(repo_relative_path "$panel_dir/question.md")"
  if [[ -f "$STATE_DIR/plan.md" ]]; then
    panel_files+=$'\n'"- Plan: $(repo_relative_path "$STATE_DIR/plan.md")"
  fi

  compose_role_task cpo \
    "$SCRIPT_DIR/tasks/consultant_panel_adjudication.md" \
    "PANEL_SUBJECT=A panel of independent consultants was convened on a question, not on a failure. The question is the first thing to read; every proposal below answers it." \
    "PANEL_FILES=$panel_files" \
    > "$panel_dir/adjudication_prompt.md"

  dispatch_role cpo "$panel_dir/adjudication_prompt.md" "$panel_dir/adjudication.md" "" \
    "proposals $name"

  local decision
  decision="$(extract_markdown_decision "$(/bin/cat "$panel_dir/adjudication.md")" \
    "ADOPT,ADOPT_PARALLEL,SYNTHESIZE,ABANDON" 2>/dev/null || printf 'UNPARSED\n')"
  printf '%s\n' "$decision" > "$panel_dir/decision.txt"

  printf 'recorded=proposals\n'
  printf 'panel=%s\n' "$name"
  printf 'panel_dir=%s\n' "$panel_dir"
  printf 'seats=%s\n' "$PANEL_SEATS"
  printf 'proposals=%s\n' "$PANEL_PROPOSALS"
  printf 'adjudication=%s\n' "$panel_dir/adjudication.md"
  printf 'decision=%s\n' "$decision"
  printf 'spent_usd=%s\n' "$(spent_usd)"
  [[ "$PANEL_SEAT_FAILURE" == "0" ]] || printf 'note=at least one seat failed; see the seat logs\n'
}
