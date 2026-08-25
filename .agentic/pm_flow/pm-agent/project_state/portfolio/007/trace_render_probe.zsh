#!/bin/zsh
# Portfolio review 007: settle the backend-render criterion.
# Export the pm-agent store's spans to the live Jaeger all-in-one, then read
# a trace back through Jaeger's own API.
set -u
cd /Users/salah/code/personal/pm-flow || exit 9
OUT=/Users/salah/code/personal/pm-flow/.agentic/pm_flow/pm-agent/project_state/portfolio/007

print -r -- "--- export ---"
pm-flow trace export --otlp http://localhost:4318/v1/traces
rc=$?
print -r -- "export_exit=$rc"

print -r -- "--- services ---"
curl -s 'http://localhost:16686/api/services' | tee "$OUT/jaeger_services.json"
print -r -- ""

print -r -- "--- traces for service pm-flow ---"
curl -s 'http://localhost:16686/api/traces?service=pm-flow&limit=5' > "$OUT/jaeger_traces.json"
python3 - "$OUT/jaeger_traces.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
traces = d.get("data") or []
print(f"traces_returned={len(traces)}")
for t in traces[:3]:
    spans = t.get("spans", [])
    print(f"traceID={t.get('traceID')} spans={len(spans)}")
    for s in spans[:5]:
        tags = {kv['key']: kv['value'] for kv in s.get('tags', [])}
        print("  span:", s.get("operationName"),
              "| gen_ai.usage.input_tokens=", tags.get("gen_ai.usage.input_tokens"),
              "| cost=", tags.get("pm_flow.cost_usd", tags.get("gen_ai.usage.cost")))
PY
print -r -- "probe_done"
