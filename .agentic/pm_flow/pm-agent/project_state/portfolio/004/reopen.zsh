#!/usr/bin/env zsh
# Portfolio review 004: reopen store-ledger after extending its boundary.
set -e
pm-flow --project pm-agent section-handoff store-ledger active \
  "Reopened by a portfolio review: the three engine fixtures and README line that touch the TSV are in Owned paths; acceptance unchanged; next is T4." \
  --file /Users/salah/code/personal/pm-flow/.agentic/pm_flow/pm-agent/project_state/portfolio/004/reopen_handoff.md
printf -- '--- status.txt: '
cat /Users/salah/code/personal/pm-flow/.agentic/pm_flow/pm-agent/sections/store-ledger/status.txt
printf -- '--- registry line: '
grep -n '^| store-ledger' /Users/salah/code/personal/pm-flow/.agentic/pm_flow/pm-agent/project_state/sections.md
