set -u
WT=/Users/salah/code/personal/.pm-flow-worktrees/pm-flow/pm-agent/persona-cards
BASE=$(mktemp -d /tmp/pmreview-mut.XXXXXX)
ROOT="$BASE/root"
mkdir -p "$ROOT"
/bin/cp -R "$WT/tests" "$WT/template" "$WT/src" "$ROOT/"
CAT="$ROOT/template/.agentic/pm_flow/catalog.py"
/bin/cp "$CAT" "$BASE/catalog.pristine.py"

echo "=== control: unmutated copy ==="
zsh "$ROOT/tests/persona_cards_test.sh" > "$BASE/control.log" 2>&1
echo "control_exit=$?"
tail -n 3 "$BASE/control.log"

mutate () { # $1 = mutation id
python3 - "$BASE/catalog.pristine.py" "$CAT" "$1" <<'PY'
import sys
from pathlib import Path
src, dst, which = sys.argv[1], sys.argv[2], sys.argv[3]
text = Path(src).read_text()
if which == "1":
    # Swallow the card refusal so validation stops guarding the store write.
    old_raise = '                raise PackError(f"{error}\\n" + "\\n".join(details)) from error'
    assert old_raise in text, "raise site not found"
    text = text.replace(old_raise, "                card = None")
elif which == "2":
    old_raise = '                raise PackError(f"{error}\\n" + "\\n".join(details)) from error'
    assert old_raise in text, "raise site not found"
    text = text.replace(
        old_raise,
        '                raise PackError(f"personas[0]: {error}\\n" + "\\n".join(details)) from error')
elif which == "3":
    old = '{"key", "file", "layer", "title", "summary", "tags", "card"}'
    assert old in text
    text = text.replace(old, '{"key", "file", "layer", "title", "summary", "tags"}')
Path(dst).write_text(text)
print(f"mutation {which} applied")
PY
}

for m in 1 2 3; do
  mutate "$m"
  echo "=== mutation $m ==="
  zsh "$ROOT/tests/persona_cards_test.sh" > "$BASE/mut-$m.log" 2>&1
  echo "mutation_${m}_exit=$?"
  tail -n 6 "$BASE/mut-$m.log"
done

/bin/cp "$BASE/catalog.pristine.py" "$CAT"
echo "=== revert check against the worktree original ==="
md5 -q "$CAT" "$WT/template/.agentic/pm_flow/catalog.py"
echo "=== worktree catalog.py untouched by this review ==="
git -C "$WT" status --porcelain=v1
echo "logs kept in $BASE"
