#!/usr/bin/env python3
"""Deterministic quality checks for the exact prompts pm-flow dispatches."""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from dataclasses import asdict, dataclass
from pathlib import Path


WORD_RE = re.compile(r"\b[\w'-]+\b")
META_RE = re.compile(r"<!--\s*pm-flow-prompt\s+([^>]+?)\s*-->")
PAIR_RE = re.compile(r"([a-z_]+)=([^\s]+)")
PLACEHOLDER_RE = re.compile(r"{{[A-Z0-9_]+}}")
TASK_RE = re.compile(r"(?im)^#\s+Task:\s+")

# Whole composed prompt: persona, domain delta, task, and the rendered context
# list. Set just above what the shipped layers compose to, so growth is a
# finding rather than a surprise.
PHASE_WORD_BUDGETS = {
    "section_scope": 850,
    "developer_assignment": 650,
    "section_review": 750,
    "section_handoff": 700,
    "section_analysis": 750,
    "project_decomposition": 950,
    "portfolio_review": 1100,
    "convergence_review": 700,
    "section_maintenance": 700,
    "section_rescue": 700,
    "consultant_panel_adjudication": 900,
    "consultant_panel": 600,
    "section_proposal": 1000,
}


@dataclass(frozen=True)
class Finding:
    severity: str
    code: str
    message: str


def words(text: str) -> list[str]:
    return WORD_RE.findall(text)


def metadata(text: str) -> dict[str, str]:
    match = META_RE.search(text)
    if not match:
        return {}
    return dict(PAIR_RE.findall(match.group(1)))


def normalized_paragraphs(text: str) -> list[tuple[str, int]]:
    found = []
    for block in re.split(r"\n\s*\n", text):
        cleaned = re.sub(r"<!--.*?-->", "", block, flags=re.S)
        cleaned = re.sub(r"[`*_#>|-]", " ", cleaned)
        cleaned = " ".join(cleaned.lower().split())
        count = len(words(cleaned))
        if count >= 12:
            found.append((cleaned, count))
    return found


def context_paths(text: str, repo_root: Path | None) -> list[dict[str, object]]:
    paths = []
    for raw in re.findall(r"(?m)^-\s+(`?[^\n`]+\.md`?)\s*$", text):
        value = raw.strip("`")
        path = Path(value)
        if not path.is_absolute() and repo_root is not None:
            path = repo_root / path
        item: dict[str, object] = {"path": value, "exists": path.is_file()}
        if path.is_file():
            body = path.read_text(errors="replace")
            item.update(bytes=len(body.encode()), words=len(words(body)))
        paths.append(item)
    return paths


def audit_text(text: str, path: Path, repo_root: Path | None) -> dict[str, object]:
    meta = metadata(text)
    phase = meta.get("phase", "unknown")
    all_words = words(text)
    task_match = TASK_RE.search(text)
    task_words = words(text[task_match.start():]) if task_match else []
    task_ratio = len(task_words) / len(all_words) if all_words else 0.0
    findings: list[Finding] = []

    placeholders = sorted(set(PLACEHOLDER_RE.findall(text)))
    if placeholders:
        findings.append(Finding(
            "error", "unresolved-placeholder",
            "unresolved template values: " + ", ".join(placeholders),
        ))

    if not meta:
        findings.append(Finding(
            "warning", "missing-runtime-contract",
            "prompt has no pm-flow runtime metadata",
        ))

    # Compared on whitespace-folded, punctuation-stripped text: a fact that
    # wraps across a line or sits in backticks is the same fact.
    lower = " ".join(re.sub(r"[`*_]", "", text.lower()).split())
    forbidden = {
        "every-history": r"history (?:above )?(?:includes|contains) every previous",
        "model-family-assumption": r"share a model family",
        "historical-incident": (
            r"\bthis used to\b|\bused to (?:be|require|append|ship|ask|mean)\b"
            r"|\bcodex-usage\W+was accepted\b|\bcost a project\b|\bonce waited on\b"
            r"|\bhave each cost\b"
        ),
    }
    for code, pattern in forbidden.items():
        if re.search(pattern, lower):
            findings.append(Finding(
                "error", code,
                "prompt embeds a false runtime fact or a historical incident",
            ))

    if meta.get("commit_owner") == "driver":
        role_commit = re.search(
            r"\b(?:you|the (?:manager|reviewer|developer))\s+"
            r"(?:must\s+|should\s+|will\s+|may\s+|can\s+)?commit\b"
            r"|\bcommit after every accepted",
            lower,
        )
        if role_commit:
            findings.append(Finding(
                "error", "commit-owner-contradiction",
                "runtime contract names the driver as commit owner but instructs a role to commit",
            ))

    paragraphs = normalized_paragraphs(text)
    counts = Counter(value for value, _ in paragraphs)
    duplicate_words = sum(
        count * (occurrences - 1)
        for value, count in paragraphs
        if (occurrences := counts[value]) > 1
    )
    duplicate_ratio = duplicate_words / len(all_words) if all_words else 0.0
    if duplicate_ratio > 0.08:
        findings.append(Finding(
            "warning", "duplicate-prose",
            f"{duplicate_ratio:.1%} of prompt words repeat an earlier paragraph",
        ))

    budget = PHASE_WORD_BUDGETS.get(phase, 1400)
    if len(all_words) > budget:
        findings.append(Finding(
            "warning", "word-budget",
            f"{len(all_words)} words exceeds the {budget}-word budget for {phase}",
        ))
    if task_match and task_ratio < 0.35:
        findings.append(Finding(
            "warning", "task-starvation",
            f"only {task_ratio:.1%} of prompt words describe the phase task",
        ))

    requirements = {
        "section_scope": ("workplan.md", "acceptance ids", "validation", "writable paths"),
        "developer_assignment": ("assignment.md", "acceptance ids", "validation"),
        "section_review": ("acceptance matrix", "drift", "validation commands"),
    }
    missing = [term for term in requirements.get(phase, ()) if term not in lower]
    # `lower` is whitespace-folded above, so a fact wrapped across a line
    # boundary in the template still counts as present.
    if missing:
        findings.append(Finding(
            "error", "missing-task-facts",
            "phase task omits: " + ", ".join(missing),
        ))

    contexts = context_paths(text, repo_root)
    context_words = sum(int(item.get("words", 0)) for item in contexts)
    if len(contexts) > 8:
        findings.append(Finding(
            "warning", "context-fanout",
            f"prompt asks the role to read {len(contexts)} context files",
        ))
    if context_words > 9000:
        findings.append(Finding(
            "warning", "context-budget",
            f"listed context contains approximately {context_words} words",
        ))

    return {
        "schema_version": 1,
        "path": str(path),
        "runtime": meta,
        "metrics": {
            "words": len(all_words),
            "bytes": len(text.encode()),
            "task_words": len(task_words),
            "task_ratio": round(task_ratio, 4),
            "duplicate_ratio": round(duplicate_ratio, 4),
            "context_files": len(contexts),
            "context_words": context_words,
        },
        "context": contexts,
        "findings": [asdict(item) for item in findings],
    }


def render_report(result: dict[str, object]) -> str:
    findings = result["findings"]
    assert isinstance(findings, list)
    severities = Counter(item["severity"] for item in findings)
    status = "FAIL" if severities["error"] else "WARN" if findings else "PASS"
    metrics = result["metrics"]
    assert isinstance(metrics, dict)
    lines = [
        f"{status} {result['path']} "
        f"words={metrics['words']} task_ratio={float(metrics['task_ratio']):.0%} "
        f"context_files={metrics['context_files']} context_words={metrics['context_words']}"
    ]
    lines.extend(
        f"  {item['severity'].upper()} {item['code']}: {item['message']}"
        for item in findings
    )
    return "\n".join(lines)


def audit_paths(paths: list[Path], repo_root: Path | None, strict: bool,
                manifest: Path | None, as_json: bool) -> int:
    results = [audit_text(path.read_text(errors="replace"), path, repo_root) for path in paths]
    if manifest is not None:
        if len(results) != 1:
            raise SystemExit("--manifest requires exactly one prompt")
        manifest.parent.mkdir(parents=True, exist_ok=True)
        manifest.write_text(json.dumps(results[0], indent=2, sort_keys=True) + "\n")
    if as_json:
        print(json.dumps(results, indent=2, sort_keys=True))
    else:
        print("\n".join(render_report(item) for item in results))

    findings = [finding for result in results for finding in result["findings"]]
    if any(item["severity"] == "error" for item in findings):
        return 1
    if strict and findings:
        return 1
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    audit = subparsers.add_parser("audit")
    audit.add_argument("paths", nargs="*", type=Path)
    audit.add_argument("--all-under", type=Path)
    audit.add_argument("--repo-root", type=Path)
    audit.add_argument("--manifest", type=Path)
    audit.add_argument("--strict", action="store_true")
    audit.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)

    paths = list(args.paths)
    if args.all_under:
        paths.extend(sorted(args.all_under.rglob("*_prompt.md")))
    paths = list(dict.fromkeys(path.resolve() for path in paths))
    if not paths:
        raise SystemExit("no prompt files found")
    missing = [str(path) for path in paths if not path.is_file()]
    if missing:
        raise SystemExit("prompt file not found: " + ", ".join(missing))
    repo_root = args.repo_root.resolve() if args.repo_root else None
    return audit_paths(paths, repo_root, args.strict, args.manifest, args.json)


if __name__ == "__main__":
    raise SystemExit(main())
