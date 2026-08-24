#!/bin/zsh -f
set -uo pipefail
TMP=/var/folders/9x/9xzxgmhn75q66kr2x3n691hw0000gn/T//aq-review.7X98GD

count_tokens() {
  grep -o 'boundaries: references outside section ownership: [^|]*' "$1" \
    | sed 's/boundaries: references outside section ownership: //' \
    | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -c .
}

print -r -- "flagged path tokens (live tree): before $(count_tokens $TMP/live.before.out)  after $(count_tokens $TMP/live.after.out)"
print -r -- ""
print -r -- "--- tokens that STOPPED being flagged (sample of distinct) ---"
grep -o 'boundaries: references outside section ownership: [^|]*' "$TMP/live.before.out" | sed 's/boundaries: references outside section ownership: //' | tr ',' '\n' | sed 's/^ *//; s/ *$//' | sort -u > "$TMP/tok.before"
grep -o 'boundaries: references outside section ownership: [^|]*' "$TMP/live.after.out" | sed 's/boundaries: references outside section ownership: //' | tr ',' '\n' | sed 's/^ *//; s/ *$//' | sort -u > "$TMP/tok.after"
comm -23 "$TMP/tok.before" "$TMP/tok.after" | head -80
print -r -- "distinct tokens dropped: $(comm -23 "$TMP/tok.before" "$TMP/tok.after" | grep -c .)"
print -r -- "distinct tokens ADDED (should be zero): $(comm -13 "$TMP/tok.before" "$TMP/tok.after" | grep -c .)"
comm -13 "$TMP/tok.before" "$TMP/tok.after"
