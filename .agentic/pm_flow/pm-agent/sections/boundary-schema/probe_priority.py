"""Scope probe: does the checker require the loss text after the priority token?

Also asks the shell pair (validate_section_brief + extract_section_priority)
about the same brief, so the assignment can name an observed disagreement
rather than a suspected one.
"""

import re
import subprocess
import tempfile
from pathlib import Path

REPO = Path("/Users/salah/code/personal/pm-flow")
FIX = REPO / "tests/fixtures/boundary_schema/brief_valid.md"
FLOW = REPO / "template/.agentic/pm_flow"
EXPORT = FLOW / "export.py"
SHELL = FLOW / "pm_flow.sh"

HARNESS = r"""
eval "$(python3 - "%(shell)s" <<'PY'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
out = []
for name in ("fail", "assert_matches", "validate_section_brief",
             "extract_section_priority"):
    m = re.search(rf"^{name}\(\) \{{\n(.*?)^\}}\n", text, re.S | re.M)
    out.append(m.group(0))
sys.stdout.write("\n".join(out))
PY
)"
brief="$(/bin/cat "%(brief)s")"
if validate_section_brief "$brief" >/dev/null 2>&1; then
  printf 'validate_section_brief: ACCEPT\n'
else
  printf 'validate_section_brief: REJECT\n'
fi
if extract_section_priority "$brief" >/dev/null 2>&1; then
  printf 'extract_section_priority: ACCEPT\n'
else
  printf 'extract_section_priority: REJECT (%%s)\n' \
    "$(extract_section_priority "$brief" 2>&1 >/dev/null)"
fi
"""

src = FIX.read_text()
variants = {
    "priority_no_loss": re.sub(
        r"(?ms)(^#{1,6}\s+Priority\s*$\n)(.*?)(?=^#{1,6}\s)",
        r"\1\n- must-have\n\n",
        src,
    ),
    "priority_illegal_token": re.sub(
        r"(?ms)(^#{1,6}\s+Priority\s*$\n)(.*?)(?=^#{1,6}\s)",
        r"\1\n- critical: the product stops without it\n\n",
        src,
    ),
    "valid": src,
}

work = Path(tempfile.mkdtemp(prefix="bs-probe."))
for name, text in variants.items():
    brief = work / f"{name}.md"
    brief.write_text(text)
    checker = subprocess.run(
        ["python3", str(EXPORT), "check", "--kind", "brief", str(brief)],
        capture_output=True,
        text=True,
    )
    script = work / f"{name}.zsh"
    script.write_text(HARNESS % {"shell": SHELL, "brief": brief})
    shell = subprocess.run(
        ["zsh", str(script)], capture_output=True, text=True
    )
    print(f"=== {name}")
    print(
        "checker:",
        "ACCEPT" if checker.returncode == 0 else f"REJECT ({checker.stderr.strip()})",
    )
    print(shell.stdout.strip() or shell.stderr.strip())
