#!/bin/zsh
# Review 007 workspace trim: the raw Jaeger dump is 700KB and re-fetchable by
# one curl (trace_render_probe.zsh regenerates it); the log holds the extract.
set -u
D=/Users/salah/code/personal/pm-flow/.agentic/pm_flow/pm-agent/project_state/portfolio/007
rm -f "$D/jaeger_traces.json"
ls -la "$D"
