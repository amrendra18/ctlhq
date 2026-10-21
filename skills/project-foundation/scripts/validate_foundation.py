#!/usr/bin/env python3
"""Validate the mechanical integrity of project foundation documents."""

from __future__ import annotations

import argparse
import re
import sys
from collections import Counter
from pathlib import Path


REQUIRED_FILES = (
    "AGENTS.md",
    "PRD.md",
    "ENGINEERING_PLAN.md",
    "ENGINEERING_PRINCIPLES.md",
)
SINGLE_FILE_FILES = ("AGENTS.md", "README.md")
PLACEHOLDER_RE = re.compile(
    r"(?i)(?:\bTODO\b|\bFIXME\b|\bTBD\b|\[placeholder\]|lorem ipsum)"
)
HEADING_RE = re.compile(r"^(#{1,6})\s+(.+?)\s*$", re.MULTILINE)
MARKDOWN_LINK_RE = re.compile(r"(?<!!)\[[^\]]+\]\(([^)]+)\)")
REQUIREMENT_DEFINITION_RE = re.compile(
    r"(?m)^\s*[-*]\s+\*\*((?:[A-Z][A-Z0-9]*-\d{2,4}))\s*:\*\*"
)
REQUIREMENT_REFERENCE_RE = re.compile(r"\b[A-Z][A-Z0-9]*-\d{2,4}\b")
ABSOLUTE_HOME_RE = re.compile(r"(?:/Users/|/home/|[A-Za-z]:\\Users\\)")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate AGENTS.md, PRD.md, ENGINEERING_PLAN.md, and "
        "ENGINEERING_PRINCIPLES.md."
    )
    parser.add_argument("project_root", type=Path, help="project directory")
    parser.add_argument(
        "--single-file",
        action="store_true",
        help="Single file mode: validate README.md and AGENTS.md instead of the four documents",
    )
    return parser.parse_args()


def local_link_target(raw_target: str) -> str | None:
    target = raw_target.strip()
    if target.startswith("<") and target.endswith(">"):
        target = target[1:-1]
    target = target.split("#", 1)[0]
    if not target or target.startswith(("#", "http://", "https://", "mailto:")):
        return None
    return target


def validate(root: Path, single_file: bool = False) -> tuple[list[str], list[str]]:
    failures: list[str] = []
    warnings: list[str] = []
    documents: dict[str, str] = {}

    if not root.is_dir():
        return [f"project root is not a directory: {root}"], warnings

    for name in SINGLE_FILE_FILES if single_file else REQUIRED_FILES:
        path = root / name
        if not path.is_file():
            failures.append(f"missing required file: {name}")
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as error:
            failures.append(f"cannot read {name} as UTF-8: {error}")
            continue
        if not text.strip():
            failures.append(f"required file is empty: {name}")
            continue
        documents[name] = text

    for name, content in documents.items():
        placeholder = PLACEHOLDER_RE.search(content)
        if placeholder:
            line = content.count("\n", 0, placeholder.start()) + 1
            failures.append(
                f"{name}:{line} contains unresolved marker {placeholder.group(0)!r}"
            )

        headings = HEADING_RE.findall(content)
        h1_count = sum(level == "#" for level, _ in headings)
        if h1_count != 1:
            failures.append(f"{name} must contain exactly one level-one heading")

        normalized_headings = [title.strip().casefold() for _, title in headings]
        for title, count in Counter(normalized_headings).items():
            if count > 1:
                warnings.append(f"{name} repeats heading {title!r} {count} times")

        if ABSOLUTE_HOME_RE.search(content):
            warnings.append(f"{name} contains a user-home absolute path")

        for raw_target in MARKDOWN_LINK_RE.findall(content):
            target = local_link_target(raw_target)
            if target is None:
                continue
            resolved = (root / name).parent.joinpath(target)
            if not resolved.exists():
                failures.append(f"{name} has unresolved local link: {raw_target}")

    prd = documents.get("README.md" if single_file else "PRD.md", "")
    plan = documents.get("README.md" if single_file else "ENGINEERING_PLAN.md", "")
    definitions = REQUIREMENT_DEFINITION_RE.findall(prd)
    duplicate_definitions = sorted(
        identifier for identifier, count in Counter(definitions).items() if count > 1
    )
    if duplicate_definitions:
        failures.append(
            "PRD.md defines requirement identifiers more than once: "
            + ", ".join(duplicate_definitions)
        )

    if definitions and not single_file:  # one file holds both sides; nothing to cross-check
        defined = set(definitions)
        plan_references = set(REQUIREMENT_REFERENCE_RE.findall(plan))
        missing_from_plan = sorted(defined - plan_references)
        unknown_in_plan = sorted(plan_references - defined)
        if missing_from_plan:
            warnings.append(
                "PRD requirement identifiers absent from ENGINEERING_PLAN.md: "
                + ", ".join(missing_from_plan)
            )
        if unknown_in_plan:
            warnings.append(
                "ENGINEERING_PLAN.md references identifiers not defined in PRD.md: "
                + ", ".join(unknown_in_plan)
            )

    return failures, warnings


def main() -> int:
    args = parse_args()
    failures, warnings = validate(args.project_root.expanduser().resolve(), args.single_file)

    for message in failures:
        print(f"FAIL: {message}")
    for message in warnings:
        print(f"WARN: {message}")

    if failures:
        print(f"RESULT: FAIL ({len(failures)} failure(s), {len(warnings)} warning(s))")
        return 1
    print(f"RESULT: PASS ({len(warnings)} warning(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
