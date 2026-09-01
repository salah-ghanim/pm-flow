#!/bin/zsh -f
set -uo pipefail
LOG=/var/folders/9x/9xzxgmhn75q66kr2x3n691hw0000gn/T/pm-flow-doc-coupling.HnOGa1/mutated.log
print -r -- "pass_lines=$(/usr/bin/grep -c '^PASS' "$LOG")"
/usr/bin/grep -m 1 -A 2 '^FAIL' "$LOG"
