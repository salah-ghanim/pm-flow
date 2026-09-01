#!/bin/zsh
# Verify the developer's registry citations first-hand.
OUT=/Users/salah/code/personal/pm-flow/.agentic/pm_flow/pm-agent/sections/outcome-record/probe_004
mkdir -p "$OUT"

printf -- '=== v1.37.0 model/gen-ai/events.yaml ===\n'
curl -sS --max-time 20 -w '\nHTTP=%{http_code}\n' \
  https://raw.githubusercontent.com/open-telemetry/semantic-conventions/v1.37.0/model/gen-ai/events.yaml \
  -o "$OUT/v1370_events.yaml" 2>&1
/usr/bin/grep -nE '^\s*(id|name):' "$OUT/v1370_events.yaml"
printf -- '--- any evaluation in v1.37.0 events.yaml ---\n'
/usr/bin/grep -nic 'evaluation' "$OUT/v1370_events.yaml"

printf -- '=== v1.38.0 model/gen-ai/events.yaml ===\n'
curl -sS --max-time 20 -w '\nHTTP=%{http_code}\n' \
  https://raw.githubusercontent.com/open-telemetry/semantic-conventions/v1.38.0/model/gen-ai/events.yaml \
  -o "$OUT/v1380_events.yaml" 2>&1
/usr/bin/grep -nE '^\s*(id|name):' "$OUT/v1380_events.yaml"

printf -- '=== v1.38.0 registry gen-ai.md: provider.name and evaluation attrs ===\n'
curl -sS --max-time 20 -w '\nHTTP=%{http_code}\n' \
  https://raw.githubusercontent.com/open-telemetry/semantic-conventions/v1.38.0/docs/registry/attributes/gen-ai.md \
  -o "$OUT/v1380_registry.md" 2>&1
/usr/bin/grep -n 'gen_ai.provider.name' "$OUT/v1380_registry.md" | head -5
/usr/bin/grep -n 'gen_ai.evaluation.name\|gen_ai.evaluation.score.label' "$OUT/v1380_registry.md" | head -6

printf -- '=== v1.37.0 registry gen-ai.md: does it already have provider.name? ===\n'
curl -sS --max-time 20 -w '\nHTTP=%{http_code}\n' \
  https://raw.githubusercontent.com/open-telemetry/semantic-conventions/v1.37.0/docs/registry/attributes/gen-ai.md \
  -o "$OUT/v1370_registry.md" 2>&1
/usr/bin/grep -n 'gen_ai.provider.name' "$OUT/v1370_registry.md" | head -3
