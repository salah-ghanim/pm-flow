#!/bin/zsh
set -e
pm-flow --project pm-agent export --json > /private/tmp/pm-flow-portfolio-008-export.json
jq -c '.sections[] | select(.key == "real-install") | {key, acceptance}' /private/tmp/pm-flow-portfolio-008-export.json
