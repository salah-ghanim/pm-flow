#!/bin/zsh
WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/outcome-record
OUT=/Users/salah/code/personal/pm-flow/.agentic/pm_flow/pm-agent/sections/outcome-record/probe_004

mkdir -p "$OUT"

zsh "$WT/tests/outcome_record_test.sh" > "$OUT/outcome_record.log" 2>&1
printf 'outcome_record_test EXIT=%s\n' "$?"

zsh "$WT/tests/otel_semconv_test.sh" > "$OUT/otel_semconv.log" 2>&1
printf 'otel_semconv_test EXIT=%s\n' "$?"

zsh "$WT/template/.agentic/pm_flow/tests/run.zsh" > "$OUT/template_run.log" 2>&1
printf 'template_run EXIT=%s\n' "$?"

printf -- '--- jaeger container after the suites ---\n'
docker ps --format '{{.ID}} {{.Image}} {{.Status}}'
