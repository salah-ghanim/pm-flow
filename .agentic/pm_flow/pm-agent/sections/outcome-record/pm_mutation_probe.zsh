#!/bin/zsh -f
# PM review probe for outcome-record cycle 003.
# Builds throwaway copies of the developer tree and mutates the evaluation
# event so the suite's assertions can be shown load-bearing.
set -uo pipefail

SRC=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/outcome-record
BASE="$(mktemp -d "${TMPDIR:-/tmp}/pm-review-003.XXXXXX")"
printf 'PROBE BASE: %s\n' "$BASE"

make_copy() {
  local dest="$1"
  mkdir -p "$dest/template/.agentic" "$dest/src" "$dest/tests/fixtures"
  cp -R "$SRC/template/.agentic/pm_flow" "$dest/template/.agentic/pm_flow"
  cp -R "$SRC/src/pm_flow" "$dest/src/pm_flow"
  cp -R "$SRC/tests/fixtures/outcome_record" "$dest/tests/fixtures/outcome_record"
  cp "$SRC/tests/outcome_record_test.sh" "$dest/tests/outcome_record_test.sh"
}

# --- control: an unmutated copy must still pass -------------------------
make_copy "$BASE/control"
printf '\n===== CONTROL (unmutated copy) =====\n'
zsh "$BASE/control/tests/outcome_record_test.sh" > "$BASE/control.log" 2>&1
printf 'CONTROL EXIT: %s\n' "$?"
tail -n 3 "$BASE/control.log"

# --- M1: the verdict attribute is constant, not the parsed token --------
make_copy "$BASE/m1"
M1="$BASE/m1/template/.agentic/pm_flow/telemetry.py"
python3 - "$M1" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
old = '        evaluation["score_label"]: args.text,\n'
new = '        evaluation["score_label"]: "GO",\n'
assert text.count(old) == 1, "mutation anchor M1 not unique"
open(path, "w", encoding="utf-8").write(text.replace(old, new))
print("M1 applied: verdict token replaced by a constant")
PY
printf '\n===== M1 (verdict attribute no longer carries the token) =====\n'
zsh "$BASE/m1/tests/outcome_record_test.sh" > "$BASE/m1.log" 2>&1
printf 'M1 EXIT: %s\n' "$?"
tail -n 4 "$BASE/m1.log"

# --- M2: the event lands on some attempt span, not the producing one ----
make_copy "$BASE/m2"
M2="$BASE/m2/template/.agentic/pm_flow/telemetry.py"
python3 - "$M2" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
old = '        "SELECT span_id FROM attempts WHERE id = ?", (args.attempt,)\n'
new = '        "SELECT span_id FROM attempts ORDER BY id LIMIT 1", ()\n'
assert text.count(old) == 1, "mutation anchor M2 not unique"
open(path, "w", encoding="utf-8").write(text.replace(old, new))
print("M2 applied: event pinned to the first attempt span")
PY
printf '\n===== M2 (event on the wrong attempt span) =====\n'
zsh "$BASE/m2/tests/outcome_record_test.sh" > "$BASE/m2.log" 2>&1
printf 'M2 EXIT: %s\n' "$?"
tail -n 4 "$BASE/m2.log"

# --- M3: v1.36.0 pin must degrade, not raise ----------------------------
make_copy "$BASE/m3"
M3="$BASE/m3/src/pm_flow/semconv.py"
python3 - "$M3" <<'PY'
import importlib.util, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
old = 'REVISION = "v1.38.0"\n'
assert text.count(old) == 1, "mutation anchor M3 not unique"
open(path, "w", encoding="utf-8").write(text.replace(old, 'REVISION = "v1.36.0"\n'))
spec = importlib.util.spec_from_file_location("probe_semconv", path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
print("M3 pin:", mod.REVISION, "evaluation_event() ->", repr(mod.evaluation_event()))
PY

rm -rf "$BASE/control" "$BASE/m1" "$BASE/m2" "$BASE/m3"
printf '\nprobe trees removed; logs kept under %s\n' "$BASE"
