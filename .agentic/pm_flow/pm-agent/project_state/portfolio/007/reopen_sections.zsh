#!/bin/zsh
# Portfolio review 007: reopen run-detach (dependency resolved by boundary
# extension) and otel-semconv (its suite is red on main), then refresh the
# generated registry.
set -u
cd /Users/salah/code/personal/pm-flow || exit 9
D=/Users/salah/code/personal/pm-flow/.agentic/pm_flow/pm-agent/project_state/portfolio/007

pm-flow section-handoff run-detach active \
  "Reopened by portfolio review 007: install.sh joined Owned paths for three registry entries; T1a is assignable and packaged_layout_test.sh is the gate." \
  --file "$D/run-detach-reopen-handoff.md"
print -r -- "run-detach_exit=$?"

pm-flow section-handoff otel-semconv active \
  "Reopened by portfolio review 007: tests/otel_semconv_test.sh exits 1 on main (secondary span reports v1.37.0 against the test's v1.36.0 pin); acceptance unchanged." \
  --file "$D/otel-semconv-reopen-handoff.md"
print -r -- "otel-semconv_exit=$?"

pm-flow list-sections
print -r -- "list_exit=$?"
