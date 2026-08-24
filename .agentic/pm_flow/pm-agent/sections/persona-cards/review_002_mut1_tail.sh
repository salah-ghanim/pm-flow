set -u
LOG=/tmp/pmreview-mut.T5glFf/mut-1.log
grep -n "surviving or changed rows" "$LOG"
echo "--- last PASS before failure ---"
grep -n "PASS: missing card module" "$LOG"
