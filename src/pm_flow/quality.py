"""Rank the quality findings in pm-flow's durable artifacts."""

from __future__ import annotations

import argparse
import importlib.util
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from types import ModuleType
from typing import Any

from pm_flow import paths
from pm_flow.paths import Paths


ARTIFACT_NAMES = ("plan.md", "brief.md", "workplan.md", "state.md", "handoff.md")
SECTION_ARTIFACT_NAMES = ARTIFACT_NAMES[1:]

PLAN_HEADINGS = (
    "Mission",
    "Project-wide constraints",
    "Section graph",
    "Integration order",
    "Project-level decisions",
    "Completion criteria",
    "Next coordination actions",
)
LEGACY_BRIEF_HEADINGS = (
    "Objective",
    "Scope",
    "Priority",
    "Owned paths",
    "Dependencies",
    "Acceptance",
    "Rejection conditions",
)
EXPANDED_BRIEF_HEADINGS = (
    "Objective",
    "Current baseline",
    "Deliverables",
    "User-visible scenarios",
    "Interfaces produced",
    "Interfaces consumed",
    "Scope",
    "Non-goals",
    "Priority",
    "Owned paths",
    "Dependencies",
    "Constraints and fixed decisions",
    "Acceptance",
    "Rejection conditions",
    "Open questions",
)
WORKPLAN_HEADINGS = (
    "Design summary",
    "Interfaces and data changes",
    "Integration and end-to-end validation",
    "Risks and rollback",
    "Acceptance coverage",
)
STATE_HEADINGS = (
    "Current task",
    "Completed tasks and evidence",
    "Active decisions",
    "Blockers",
    "Next eligible task",
)
HANDOFF_HEADINGS = (
    "Outcome",
    "Decisions",
    "Interfaces",
    "Risks",
    "What is unproven",
    "Next action",
)


@dataclass
class Artifact:
    path: Path
    label: str
    kind: str
    section_key: str | None
    text: str
    word_count: int
    length_over: int
    findings: list[Any]


def load_prompt_quality() -> ModuleType:
    source = paths.engine_root() / "prompt_quality.py"
    spec = importlib.util.spec_from_file_location("_pm_flow_prompt_quality", source)
    if spec is None or spec.loader is None:
        raise SystemExit(f"cannot load prompt quality helpers: {source}")
    module = importlib.util.module_from_spec(spec)
    # Dataclasses resolve their defining module through sys.modules while the
    # class body executes.
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    for name in ("Finding", "normalized_paragraphs", "words"):
        if not hasattr(module, name):
            raise SystemExit(f"prompt quality helper is missing {name}: {source}")
    return module


def load_budgets() -> dict[str, int]:
    rubric = paths.engine_root() / "artifact_quality.md"
    try:
        text = rubric.read_text(errors="replace")
    except OSError as exc:
        raise SystemExit(f"cannot read artifact quality rubric: {rubric}: {exc}") from exc

    header = re.search(
        r"(?im)^\|\s*File\s*\|\s*Word budget\s*\|\s*$",
        text,
    )
    if not header:
        raise SystemExit(f"rubric has no '| File | Word budget |' table: {rubric}")

    rows: dict[str, int] = {}
    for line in text[header.end():].splitlines()[1:]:
        if not line.lstrip().startswith("|"):
            break
        match = re.match(r"^\|\s*`?([^|`]+?)`?\s*\|\s*(\d+)\s*\|\s*$", line)
        if match:
            name, value = match.groups()
            rows[name.strip()] = int(value)

    missing = [name for name in ARTIFACT_NAMES if name not in rows]
    if missing:
        raise SystemExit("rubric word budget table is missing: " + ", ".join(missing))
    return {name: rows[name] for name in ARTIFACT_NAMES}


def markdown_section(text: str, heading: str) -> str:
    match = re.search(
        rf"(?im)^##\s+{re.escape(heading)}\s*$",
        text,
    )
    if not match:
        return ""
    tail = text[match.end():]
    end = re.search(r"(?m)^#{1,2}\s+", tail)
    return tail[:end.start()] if end else tail


def has_heading(text: str, heading: str) -> bool:
    return bool(re.search(rf"(?im)^##\s+{re.escape(heading)}\s*$", text))


def required_headings(kind: str, text: str) -> tuple[str, ...]:
    if kind == "plan.md":
        return PLAN_HEADINGS
    if kind == "brief.md":
        return EXPANDED_BRIEF_HEADINGS if has_heading(text, "Deliverables") else LEGACY_BRIEF_HEADINGS
    if kind == "workplan.md":
        return WORKPLAN_HEADINGS
    if kind == "state.md":
        return STATE_HEADINGS
    return HANDOFF_HEADINGS


def table_coverage_ids(workplan: str) -> set[str]:
    coverage = markdown_section(workplan, "Acceptance coverage")
    found: set[str] = set()
    for line in coverage.splitlines():
        match = re.match(r"^\s*\|\s*(A\d+)\s*\|", line, flags=re.IGNORECASE)
        if match:
            found.add(match.group(1).upper())
    return found


def bullet_values(text: str, heading: str) -> list[str]:
    values = []
    for line in markdown_section(text, heading).splitlines():
        match = re.match(r"^\s*[-*]\s+(.+?)\s*$", line)
        if match:
            value = match.group(1).strip().strip("`")
            if value.lower().rstrip(".") != "none":
                values.append(value)
    return values


def normalized_path(value: str, repo_root: Path) -> str:
    value = value.strip().rstrip(".,;:")
    candidate = Path(value)
    if candidate.is_absolute():
        try:
            return candidate.resolve().relative_to(repo_root).as_posix()
        except ValueError:
            return candidate.as_posix()
    while value.startswith("./"):
        value = value[2:]
    return value.rstrip("/")


def looks_like_path(value: str) -> bool:
    if not value or any(character.isspace() for character in value):
        return False
    if value in SECTION_ARTIFACT_NAMES:
        return True
    return "/" in value or bool(re.search(r"\.[A-Za-z0-9]{1,8}(?::\d+)?$", value))


def path_is_allowed(candidate: str, allowed: list[str]) -> bool:
    for owner in allowed:
        if candidate == owner or candidate.startswith(owner + "/"):
            return True
    return False


def boundary_violations(
    artifact: Artifact,
    brief: str,
    repo_root: Path,
    project_key: str,
    live_keys: set[str],
) -> list[str]:
    if artifact.section_key is None:
        return []

    owned = [normalized_path(value, repo_root) for value in bullet_values(brief, "Owned paths")]
    dependencies = bullet_values(brief, "Dependencies")
    dependency_keys = {
        match.group(1)
        for value in dependencies
        if (match := re.search(r"(?:^|/)sections/([^/]+)/handoff\.md$", value))
    }
    dependency_keys.update(value for value in dependencies if value in live_keys)
    dependency_paths = [
        normalized_path(value, repo_root)
        for value in dependencies
        if looks_like_path(value)
    ]
    own_section_root = normalized_path(
        str(Paths(repo_root, project_key).section_dir(artifact.section_key)),
        repo_root,
    )
    allowed = owned + dependency_paths + [
        f"{own_section_root}/{name}" for name in SECTION_ARTIFACT_NAMES
    ]

    violations: set[str] = set()
    for raw in re.findall(r"`([^`\n]+)`", artifact.text):
        value = raw.strip()
        if value in live_keys:
            if value != artifact.section_key and value not in dependency_keys:
                violations.add(value)
            continue
        if not looks_like_path(value):
            continue
        candidate = normalized_path(value, repo_root)
        if candidate in SECTION_ARTIFACT_NAMES:
            continue
        section_match = re.search(r"(?:^|/)sections/([^/]+)(?:/|$)", candidate)
        if section_match:
            key = section_match.group(1)
            if key == artifact.section_key:
                continue
            if key in dependency_keys and candidate.endswith("/handoff.md"):
                continue
        if not path_is_allowed(candidate, allowed):
            violations.add(candidate)
    return sorted(violations)


def collect_artifacts(layout: Paths, budgets: dict[str, int], helpers: ModuleType) -> list[Artifact]:
    candidates: list[tuple[Path, str, str | None]] = [
        (layout.state_dir / "plan.md", "plan.md", None),
    ]
    if layout.sections_dir.is_dir():
        keys = sorted(
            entry.name
            for entry in layout.sections_dir.iterdir()
            if entry.is_dir() and not entry.name.startswith(".")
        )
        for key in keys:
            section = layout.section_dir(key)
            candidates.extend((section / name, name, key) for name in SECTION_ARTIFACT_NAMES)

    artifacts = []
    for path, kind, section_key in candidates:
        if not path.is_file():
            continue
        text = path.read_text(errors="replace")
        word_count = len(helpers.words(text))
        artifacts.append(Artifact(
            path=path,
            label=layout.relative(path),
            kind=kind,
            section_key=section_key,
            text=text,
            word_count=word_count,
            length_over=max(0, word_count - budgets[kind]),
            findings=[],
        ))
    return artifacts


def add_findings(artifacts: list[Artifact], layout: Paths, helpers: ModuleType) -> None:
    finding = helpers.Finding
    by_section: dict[str, dict[str, Artifact]] = {}
    plan: Artifact | None = None
    for artifact in artifacts:
        if artifact.section_key is None:
            plan = artifact
        else:
            by_section.setdefault(artifact.section_key, {})[artifact.kind] = artifact

        if artifact.length_over:
            budget = artifact.word_count - artifact.length_over
            artifact.findings.append(finding(
                "warning",
                "length",
                f"{artifact.word_count} words exceeds the {budget}-word "
                f"{artifact.kind} budget by {artifact.length_over}",
            ))

        missing = [
            heading for heading in required_headings(artifact.kind, artifact.text)
            if not has_heading(artifact.text, heading)
        ]
        if missing:
            artifact.findings.append(finding(
                "warning",
                "shape",
                "missing headings: " + ", ".join(missing),
            ))

    # Echo comparisons are intentionally scoped one section at a time. The
    # helper owns normalization and the minimum paragraph size.
    plan_paragraphs = {
        value for value, _ in helpers.normalized_paragraphs(plan.text)
    } if plan else set()
    plan_echoes: set[str] = set()
    for section_artifacts in by_section.values():
        paragraphs = {
            kind: {value for value, _ in helpers.normalized_paragraphs(item.text)}
            for kind, item in section_artifacts.items()
        }
        echoed: dict[str, set[str]] = {kind: set() for kind in section_artifacts}
        kinds = sorted(section_artifacts)
        for index, left in enumerate(kinds):
            for right in kinds[index + 1:]:
                shared = paragraphs[left] & paragraphs[right]
                echoed[left].update(shared)
                echoed[right].update(shared)
        for kind in kinds:
            shared_with_plan = paragraphs[kind] & plan_paragraphs
            echoed[kind].update(shared_with_plan)
            plan_echoes.update(shared_with_plan)
            if echoed[kind]:
                section_artifacts[kind].findings.append(finding(
                    "warning",
                    "echo",
                    f"{len(echoed[kind])} normalized paragraph(s) repeat in another durable file",
                ))
    if plan and plan_echoes:
        plan.findings.append(finding(
            "warning",
            "echo",
            f"{len(plan_echoes)} normalized paragraph(s) repeat in a section file",
        ))

    live_keys = set(by_section)
    for key, section_artifacts in by_section.items():
        brief = section_artifacts.get("brief.md")
        workplan = section_artifacts.get("workplan.md")
        state = section_artifacts.get("state.md")

        if brief and workplan:
            brief_ids = set(re.findall(r"\bA\d+\b", brief.text, flags=re.IGNORECASE))
            brief_ids = {value.upper() for value in brief_ids}
            uncovered = sorted(brief_ids - table_coverage_ids(workplan.text))
            if uncovered:
                brief.findings.append(finding(
                    "warning",
                    "shape",
                    "acceptance IDs absent from workplan coverage table: " + ", ".join(uncovered),
                ))

        if state and workplan:
            design = markdown_section(workplan.text, "Design summary")
            design_paragraphs = {value for value, _ in helpers.normalized_paragraphs(design)}
            state_paragraphs = {value for value, _ in helpers.normalized_paragraphs(state.text)}
            if design_paragraphs & state_paragraphs:
                state.findings.append(finding(
                    "warning",
                    "stale",
                    "state repeats the workplan design summary",
                ))

        brief_text = brief.text if brief else ""
        for artifact in section_artifacts.values():
            violations = boundary_violations(
                artifact, brief_text, layout.repo_root, layout.project_key, live_keys,
            )
            if violations:
                artifact.findings.append(finding(
                    "warning",
                    "boundaries",
                    "references outside section ownership: " + ", ".join(violations),
                ))

    if plan and re.search(r"(?im)^\s*at review\b", plan.text):
        plan.findings.append(finding(
            "warning",
            "stale",
            "plan begins a line with review narration",
        ))


def render(artifact: Artifact) -> str:
    if not artifact.findings:
        return f"{artifact.label} | findings: none"
    ordered = sorted(artifact.findings, key=lambda item: (item.code, item.message))
    return artifact.label + " | " + " | ".join(
        f"{item.code}: {item.message}" for item in ordered
    )


def rank(project: str | None) -> int:
    helpers = load_prompt_quality()
    budgets = load_budgets()
    layout = Paths(project_key=project)
    artifacts = collect_artifacts(layout, budgets, helpers)
    add_findings(artifacts, layout, helpers)
    artifacts.sort(key=lambda item: (-len(item.findings), -item.length_over, item.label))
    for artifact in artifacts:
        print(render(artifact))
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    rank_parser = subparsers.add_parser("rank", help="print durable artifact findings worst first")
    rank_parser.add_argument("--project")
    args = parser.parse_args(argv)
    return rank(args.project)


if __name__ == "__main__":
    raise SystemExit(main())
