#!/bin/zsh -f
set -uo pipefail
exec python3 "${0:A:h}/probe_priority.py"
