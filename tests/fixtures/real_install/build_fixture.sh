#!/bin/zsh -f
set -euo pipefail

if [[ "$#" != 2 ]]; then
  printf 'usage: %s <pm-flow-checkout> <fixture-repository>\n' "$0" >&2
  exit 2
fi

REPO_ROOT="$(cd -P -- "$1" && pwd -P)"
FIXTURE_REPO="$2"
FLOW="$FIXTURE_REPO/agentic/pm_flow"

mkdir -p "$FLOW"
git -C "$FIXTURE_REPO" init --quiet
git -C "$FIXTURE_REPO" config user.email real-install-test@example.invalid
git -C "$FIXTURE_REPO" config user.name real-install-test

# Start with what the old installer copied, so changes to the packaged layout
# are reflected by the fixture rather than frozen into a static test tree.
/bin/cp -R "$REPO_ROOT/template/.agentic/pm_flow/." "$FLOW/"
rm -rf -- "$FLOW/__pycache__" "$FLOW/project"
rm -f -- "$FLOW/.project-key" "$FLOW/projects.md"
for candidate in "$FLOW"/*(.N); do
  [[ "$(/usr/bin/head -c 2 "$candidate" 2>/dev/null)" == "#!" ]] || continue
  chmod +x "$candidate"
done

mkdir -p "$FLOW/.pm-flow"
printf 'version 0.2.0\nroot template\nengine x deadbeef agentic/pm_flow/pm_flow.sh\n' \
  > "$FLOW/.pm-flow/MANIFEST"
printf '# the copy-version lifecycle this install was managed by\n' \
  > "$FLOW/upgrade.py"

python3 - "$REPO_ROOT/template/.agentic/pm_flow/config.json" "$FLOW/config.json" <<'PY'
import json
import sys
from pathlib import Path

config = json.loads(Path(sys.argv[1]).read_text().replace("{{DOMAIN}}", "generic"))
config["operator_note"] = "golden-grid operator setting"
Path(sys.argv[2]).write_text(json.dumps(config, indent=2) + "\n")
PY

create_workspace() {
  local key="$1" domain="$2" marker="$3"
  local workspace="$FLOW/$key"
  local section="$workspace/sections/$key-section"

  mkdir -p "$workspace/project_state" "$workspace/runs" "$workspace/roles" "$section"
  printf '# %s task contract\n\nLegacy contract for %s.\n' "$marker" "$key" \
    > "$workspace/task_contract.md"
  printf '{\n  "version": 1,\n  "domain": "%s"\n}\n' "$domain" \
    > "$workspace/project.json"
  printf '# Plan\n\nPreserve the %s workspace.\n' "$marker" \
    > "$workspace/project_state/plan.md"
  printf '# Sections\n\nLegacy registry for %s.\n' "$key" \
    > "$workspace/project_state/sections.md"
  printf 'Legacy start prompt for %s.\n' "$key" \
    > "$workspace/project_state/start.md"
  printf 'Legacy resume prompt for %s.\n' "$key" \
    > "$workspace/project_state/resume.md"
  printf '## Local overlay\n\n%s workspace role marker.\n' "$marker" \
    > "$workspace/roles/pm.md"

  printf '%s section\n' "$marker" > "$section/name.txt"
  printf 'active\n' > "$section/status.txt"
  printf 'must-have\n' > "$section/priority.txt"
  printf 'Legacy section for %s.\n' "$key" > "$section/summary.txt"
  printf '2026-01-01T00:00:00Z\n' > "$section/updated_at.txt"
  printf '## Objective\n\n- Preserve %s.\n' "$key" > "$section/brief.md"

  {
    printf '2026-01-01T00:00:00Z\t%s-section\tdeveloper\tfirst\t1.250000\tresponses/%s-first.json\n' "$key" "$key"
    printf '2026-01-01T00:01:00Z\t%s-section\tpm\tsecond\t2.500000\tresponses/%s-second.json\n' "$key" "$key"
    printf '2026-01-01T00:02:00Z\t%s-section\tdeveloper\tthird\t3.750000\tresponses/%s-third.json\n' "$key" "$key"
  } > "$workspace/runs/cost_ledger.tsv"
}

create_workspace alpha generic Alpha
create_workspace beta saas Beta
create_workspace gamma migration Gamma
# This real workspace deliberately collides with the copied scaffold name.
create_workspace project infrastructure Project

[[ ! -e "$FLOW/.project-key" && ! -e "$FLOW/projects.md" ]]
git -C "$FIXTURE_REPO" add -f agentic
git -C "$FIXTURE_REPO" commit --quiet -m 'legacy many-workspace install'
