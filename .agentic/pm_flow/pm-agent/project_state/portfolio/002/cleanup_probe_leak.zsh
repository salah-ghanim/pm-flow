#!/bin/zsh
# Remove fixture sections and run dirs that tests/prompt_quality_test.sh wrote
# into the live pm-agent project when run from inside a dispatch (review 002).
set -u
P=/Users/salah/code/personal/pm-flow/.agentic/pm_flow/pm-agent
for s in alpha delta epsilon eta gamma zeta; do
  [ -d "$P/sections/$s" ] && rm -r "$P/sections/$s" && echo "removed sections/$s"
done
for r in 20260823T181716Z-eta-d23ae785 20260823T181715Z-zeta-b9dcf81f \
         20260823T181715Z-epsilon-ac6eac91 20260823T181714Z-delta-f90f2c8a \
         20260823T181713Z-gamma-fff06a2b 20260823T181713Z-alpha-24de8c30; do
  [ -d "$P/runs/$r" ] && rm -r "$P/runs/$r" && echo "removed runs/$r"
done
ls "$P/sections"
