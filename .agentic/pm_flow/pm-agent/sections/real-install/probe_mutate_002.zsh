#!/bin/zsh
# PM review: mutation checks against a throwaway copy of the developer worktree.
set -uo pipefail
WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/real-install
OUT=/Users/salah/code/personal/pm-flow/.agentic/pm_flow/pm-agent/sections/real-install/review_002
COPY="$(mktemp -d "${TMPDIR:-/tmp}/pm-review-mutate.XXXXXX")"
mkdir -p "$OUT"

rsync -a --exclude '/.git' --exclude '/.venv' --exclude '/.agentic' "$WT/" "$COPY/"
print "copy=$COPY"

print "=== derivation check: the suite's install_array_names vs install.sh ==="
zsh -f -c '
  install_array_names() {
    sed -n "/^$1=(/,/^)/p" '"$COPY"'/install.sh | sed "1d;\$d;s/#.*//;s/^[[:space:]]*//;s/[[:space:]]*\$//;/^\$/d"
  }
  print "FILES: $(install_array_names COPIED_ENGINE_FILES | tr "\n" " ")"
  print "DIRS:  $(install_array_names COPIED_ENGINE_DIRS | tr "\n" " ")"
'

print "=== MUTATION A: revert the install.sh empty-element filter ==="
cp "$COPY/install.sh" "$COPY/install.sh.orig"
grep -vF 'candidates=("${(@)candidates:#}")' "$COPY/install.sh.orig" > "$COPY/install.sh"
chmod +x "$COPY/install.sh"
diff "$COPY/install.sh.orig" "$COPY/install.sh"
zsh "$COPY/tests/real_install_test.sh" > "$OUT/mutation_a.out" 2>&1
print "EXIT_A=$?"
tail -n 8 "$OUT/mutation_a.out"
cp "$COPY/install.sh.orig" "$COPY/install.sh"
chmod +x "$COPY/install.sh"

print "=== MUTATION B: change a fixture ledger amount (arithmetic must follow) ==="
sed -i.bak 's/1\.250000/9.000000/' "$COPY/tests/fixtures/real_install/build_fixture.sh"
grep -n '9\.000000' "$COPY/tests/fixtures/real_install/build_fixture.sh"
zsh "$COPY/tests/real_install_test.sh" > "$OUT/mutation_b.out" 2>&1
print "EXIT_B=$?"
grep 'workspace=' "$OUT/mutation_b.out"
tail -n 3 "$OUT/mutation_b.out"
mv "$COPY/tests/fixtures/real_install/build_fixture.sh.bak" "$COPY/tests/fixtures/real_install/build_fixture.sh"

print "=== MUTATION C: rename the workspace pm-overlay marker ==="
sed -i.bak 's/workspace role marker/workspace role sigil/' "$COPY/tests/fixtures/real_install/build_fixture.sh"
grep -n 'role sigil' "$COPY/tests/fixtures/real_install/build_fixture.sh"
zsh "$COPY/tests/real_install_test.sh" > "$OUT/mutation_c.out" 2>&1
print "EXIT_C=$?"
tail -n 8 "$OUT/mutation_c.out"
mv "$COPY/tests/fixtures/real_install/build_fixture.sh.bak" "$COPY/tests/fixtures/real_install/build_fixture.sh"

rm -rf "$COPY"
print "done"
