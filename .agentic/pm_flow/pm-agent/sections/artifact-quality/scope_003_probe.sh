#!/bin/zsh -f
set -euo pipefail
OUT=/tmp/aq003
printf '%s\n' '--- occurrences of the known non-path noise set ---'
grep -c -E '^(/|/v1/traces|13937in/5out|notifications/initialized|resources/list|session/cancel|session/new|session/prompt|session/request_permission|tools/call)$' "$OUT/tokens.txt"
printf '%s\n' '--- files carrying at least one of them ---'
grep -E '13937in/5out|tools/call|session/prompt|resources/list|session/new|session/cancel|notifications/initialized|session/request_permission|/v1/traces' "$OUT/live.txt" | sed 's/ |.*//' | sort -u
printf '%s\n' '--- per-file dimension counts ---'
for d in length echo shape boundaries stale; do
  printf '%s %s\n' "$d" "$(grep -c "$d:" "$OUT/live.txt")"
done
