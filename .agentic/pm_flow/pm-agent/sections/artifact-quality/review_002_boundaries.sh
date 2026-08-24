#!/bin/zsh -f
set -uo pipefail
OUT="$1"
grep 'boundaries:' "$OUT" | sed 's/ | shape:.*//' | sed 's/ | length:.*//' | sed 's/ | echo:.*//' | sed 's/ | stale:.*//'
