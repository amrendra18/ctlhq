"""Validate a Project Guide without changing the repository."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from collections.abc import Iterable
from dataclasses import dataclass, field
from datetime import datetime
from html.parser import HTMLParser
from pathlib import Path, PurePosixPath
from urllib.parse import unquote, urlsplit

SCHEMA_VERSION = 1
REQUIRED_PAGES = {
    "index.html": "overview",
    "experience.html": "experience",
    "architecture.html": "architecture",
    "workflows.html": "workflows",
    "validation.html": "validation",
}
REQUIRED_FILES = set(REQUIRED_PAGES) | {"styles.css", "manifest.json"}
COMMIT_PATTERN = re.compile(r"^[0-9a-f]{40}$")


class CheckError(RuntimeError):
    """A Git or environment error that prevents a complete check."""


@dataclass
class PageFacts:
    path: Path
    expected_section: str
    ids: set[str] = field(default_factory=set)
    duplicate_ids: set[str] = field(default_factory=set)
    links: list[tuple[str, str, str]] = field(default_factory=list)
    sections: list[str] = field(default_factory=list)
    source_meta: list[str] = field(default_factory=list)
    source_markers: list[str] = field(default_factory=list)
    nav_count: int = 0
    main_count: int = 0
    footer_count: int = 0
    html_language: str = ""
    has_viewport: bool = False
    stylesheet_links: list[str] = field(default_factory=list)
    script_count: int = 0
    title_parts: list[str] = field(default_factory=list)
    _title_depth: int = 0


class GuideParser(HTMLParser):
    def __init__(self, facts: PageFacts) -> None:
        super().__init__(convert_charrefs=True)
        self.facts = facts

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = {key.lower(): value or "" for key, value in attrs}
        tag = tag.lower()

        element_id = values.get("id")
        if element_id:
            if element_id in self.facts.ids:
                self.facts.duplicate_ids.add(element_id)
            self.facts.ids.add(element_id)

        if tag == "html":
            self.facts.html_language = values.get("lang", "").strip()
        elif tag == "title":
            self.facts._title_depth += 1
        elif tag == "meta":
            name = values.get("name", "").lower()
            if name == "viewport" and values.get("content", "").strip():
                self.facts.has_viewport = True
            if name == "project-guide-source":
                self.facts.source_meta.append(values.get("content", ""))
        elif tag == "nav":
            self.facts.nav_count += 1
        elif tag == "main":
            self.facts.main_count += 1
            section = values.get("data-guide-section", "").strip()
            if section:
                self.facts.sections.append(section)
        elif tag == "footer":
            self.facts.footer_count += 1
        elif tag == "script":
            self.facts.script_count += 1

        source_marker = values.get("data-source-commit", "").strip()
        if source_marker:
            self.facts.source_markers.append(source_marker)

        for attribute in ("href", "src"):
            value = values.get(attribute)
            if value:
                self.facts.links.append((tag, attribute, value.strip()))

        if tag == "link" and "stylesheet" in values.get("rel", "").lower().split():
            self.facts.stylesheet_links.append(values.get("href", "").strip())

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self.handle_starttag(tag, attrs)

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() == "title" and self.facts._title_depth:
            self.facts._title_depth -= 1

    def handle_data(self, data: str) -> None:
        if self.facts._title_depth:
            self.facts.title_parts.append(data)


def run_git(
    repo: Path, args: list[str], allowed_codes: Iterable[int] = (0,)
) -> subprocess.CompletedProcess[bytes]:
    try:
        result = subprocess.run(
            ["git", "-C", str(repo), *args],
            capture_output=True,
            check=False,
        )
    except OSError as exc:
        raise CheckError(f"could not run Git: {exc}") from exc

    if result.returncode not in set(allowed_codes):
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise CheckError(detail or f"Git command failed with exit {result.returncode}")
    return result


def inside(child: Path, parent: Path) -> bool:
    try:
        return os.path.commonpath((str(child.resolve()), str(parent.resolve()))) == str(
            parent.resolve()
        )
    except ValueError:
        return False


def safe_relative_path(value: object, field_name: str, errors: list[str]) -> str | None:
    if not isinstance(value, str) or not value.strip():
        errors.append(f"manifest {field_name} must be a non-empty string")
        return None
    candidate = value.strip().replace("\\", "/")
    path = PurePosixPath(candidate)
    if path.is_absolute() or any(part in {"", ".", ".."} for part in path.parts):
        errors.append(f"manifest {field_name} is not a safe relative path: {value!r}")
        return None
    if candidate != path.as_posix():
        errors.append(f"manifest {field_name} must be normalized: {value!r}")
        return None
    return candidate


def load_manifest(guide_dir: Path, errors: list[str]) -> dict[str, object] | None:
    manifest_path = guide_dir / "manifest.json"
    try:
        raw = manifest_path.read_text(encoding="utf-8")
    except OSError as exc:
        errors.append(f"cannot read {manifest_path}: {exc}")
        return None

    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        errors.append(f"manifest.json is invalid JSON: {exc}")
        return None
    if not isinstance(value, dict):
        errors.append("manifest.json must contain one JSON object")
        return None
    return value


def validate_manifest(
    manifest: dict[str, object], errors: list[str]
) -> tuple[str | None, str | None, list[str], list[str]]:
    if manifest.get("schemaVersion") != SCHEMA_VERSION:
        errors.append(f"manifest schemaVersion must be {SCHEMA_VERSION}")

    source = manifest.get("sourceCommit")
    if not isinstance(source, str) or not COMMIT_PATTERN.fullmatch(source):
        errors.append(
            "manifest sourceCommit must be a full lowercase 40-character Git SHA"
        )
        source_value = None
    else:
        source_value = source

    guide_root = safe_relative_path(manifest.get("guideRoot"), "guideRoot", errors)

    generated_at = manifest.get("generatedAt")
    if not isinstance(generated_at, str):
        errors.append("manifest generatedAt must be an RFC 3339 timestamp")
    else:
        try:
            parsed = datetime.fromisoformat(generated_at.replace("Z", "+00:00"))
            if parsed.tzinfo is None:
                raise ValueError("timezone missing")
        except ValueError:
            errors.append("manifest generatedAt must include a valid timezone")

    if manifest.get("productTreeClean") is not True:
        errors.append("manifest productTreeClean must be true")

    page_values = manifest.get("pages")
    pages: list[str] = []
    if not isinstance(page_values, list):
        errors.append("manifest pages must be an array")
    else:
        for index, value in enumerate(page_values):
            valid = safe_relative_path(value, f"pages[{index}]", errors)
            if valid:
                pages.append(valid)
        if len(pages) != len(set(pages)):
            errors.append("manifest pages contains duplicate paths")
        missing_pages = set(REQUIRED_PAGES) - set(pages)
        if missing_pages:
            errors.append(
                "manifest pages is missing: " + ", ".join(sorted(missing_pages))
            )

    file_values = manifest.get("files")
    files: list[str] = []
    if not isinstance(file_values, list):
        errors.append("manifest files must be an array")
    else:
        for index, value in enumerate(file_values):
            valid = safe_relative_path(value, f"files[{index}]", errors)
            if valid:
                files.append(valid)
        if len(files) != len(set(files)):
            errors.append("manifest files contains duplicate paths")
        missing_files = REQUIRED_FILES - set(files)
        if missing_files:
            errors.append(
                "manifest files is missing: " + ", ".join(sorted(missing_files))
            )
        if not set(pages).issubset(files):
            errors.append("every manifest page must also appear in files")

    return source_value, guide_root, pages, files


def parse_pages(
    guide_dir: Path, pages: list[str], source: str | None, errors: list[str]
) -> dict[str, PageFacts]:
    facts_by_page: dict[str, PageFacts] = {}
    for page in pages:
        if page not in REQUIRED_PAGES:
            continue
        page_path = guide_dir / page
        try:
            markup = page_path.read_text(encoding="utf-8")
        except OSError as exc:
            errors.append(f"cannot read declared page {page}: {exc}")
            continue

        facts = PageFacts(path=page_path, expected_section=REQUIRED_PAGES[page])
        parser = GuideParser(facts)
        parser.feed(markup)
        parser.close()

        title = "".join(facts.title_parts).strip()
        if not title:
            errors.append(f"{page} has no useful title")
        if not facts.html_language:
            errors.append(f"{page} has no html language")
        if not facts.has_viewport:
            errors.append(f"{page} has no viewport metadata")
        if facts.nav_count < 1:
            errors.append(f"{page} has no navigation element")
        if facts.main_count != 1:
            errors.append(f"{page} must contain exactly one main element")
        if facts.sections != [facts.expected_section]:
            errors.append(
                f"{page} main section must be {facts.expected_section!r}, found {facts.sections!r}"
            )
        if facts.footer_count < 1:
            errors.append(f"{page} has no footer")
        if facts.script_count:
            errors.append(f"{page} contains a script element")
        if facts.duplicate_ids:
            errors.append(
                f"{page} has duplicate ids: {', '.join(sorted(facts.duplicate_ids))}"
            )
        if "styles.css" not in facts.stylesheet_links:
            errors.append(f"{page} does not link the shared styles.css")
        if source:
            if facts.source_meta != [source]:
                errors.append(
                    f"{page} project-guide-source metadata does not match the manifest"
                )
            if source not in facts.source_markers:
                errors.append(
                    f"{page} does not show the manifest source commit in its footer"
                )

        nav_targets = {
            urlsplit(value).path
            for tag, attribute, value in facts.links
            if tag == "a" and attribute == "href"
        }
        missing_navigation = set(REQUIRED_PAGES) - nav_targets
        if missing_navigation:
            errors.append(
                f"{page} navigation is missing: {', '.join(sorted(missing_navigation))}"
            )
        facts_by_page[page] = facts
    return facts_by_page


def validate_declared_files(
    guide_dir: Path, files: list[str], errors: list[str]
) -> None:
    for relative in files:
        path = (guide_dir / relative).resolve()
        if not inside(path, guide_dir):
            errors.append(f"declared file escapes the guide root: {relative}")
        elif not path.is_file():
            errors.append(f"declared file is missing: {relative}")

    stylesheet = guide_dir / "styles.css"
    try:
        css = stylesheet.read_text(encoding="utf-8")
    except OSError as exc:
        errors.append(f"cannot read styles.css: {exc}")
        return
    lowered = css.lower()
    if "@import" in lowered or "url(" in lowered:
        errors.append("styles.css must not import or load other resources")
    if ":focus" not in lowered:
        errors.append("styles.css must define a visible focus style")


def validate_links(
    guide_dir: Path, facts_by_page: dict[str, PageFacts], errors: list[str]
) -> None:
    allowed_external_href = {"http", "https", "mailto"}
    forbidden_schemes = {"data", "file", "javascript", "vbscript"}

    for page, facts in facts_by_page.items():
        for tag, attribute, raw_value in facts.links:
            parsed = urlsplit(raw_value)
            scheme = parsed.scheme.lower()
            if scheme:
                if (
                    attribute == "href"
                    and tag == "a"
                    and scheme in allowed_external_href
                ):
                    continue
                if scheme in forbidden_schemes or attribute == "src":
                    errors.append(f"{page} has unsafe {attribute}: {raw_value}")
                else:
                    errors.append(f"{page} has unsupported {attribute}: {raw_value}")
                continue
            if parsed.netloc or parsed.path.startswith("/"):
                errors.append(f"{page} has an absolute local {attribute}: {raw_value}")
                continue

            relative_path = unquote(parsed.path)
            target = (
                facts.path if not relative_path else facts.path.parent / relative_path
            )
            target = target.resolve()
            if not inside(target, guide_dir):
                errors.append(f"{page} link escapes the guide root: {raw_value}")
                continue
            if not target.is_file():
                errors.append(f"{page} has a broken local link: {raw_value}")
                continue

            fragment = unquote(parsed.fragment)
            if fragment and target.suffix.lower() == ".html":
                try:
                    target_key = target.relative_to(guide_dir.resolve()).as_posix()
                except ValueError:
                    continue
                target_facts = facts_by_page.get(target_key)
                if target_facts and fragment not in target_facts.ids:
                    errors.append(f"{page} has a missing fragment target: {raw_value}")


def nul_paths(payload: bytes) -> list[str]:
    return [
        item.decode("utf-8", errors="replace") for item in payload.split(b"\0") if item
    ]


def validate_git(
    repo: Path,
    source: str | None,
    excluded_roots: list[str],
    errors: list[str],
) -> None:
    if not source or not excluded_roots:
        return

    commit_check = run_git(
        repo, ["cat-file", "-e", f"{source}^{{commit}}"], allowed_codes=(0, 1, 128)
    )
    if commit_check.returncode != 0:
        errors.append(f"manifest source commit does not exist: {source}")
        return

    ancestry = run_git(
        repo,
        ["merge-base", "--is-ancestor", source, "HEAD"],
        allowed_codes=(0, 1),
    )
    if ancestry.returncode != 0:
        errors.append(f"manifest source commit is not an ancestor of HEAD: {source}")
        return

    excludes = [f":(exclude,glob){root}/**" for root in excluded_roots]
    changed = run_git(
        repo,
        ["diff", "--name-only", "-z", f"{source}..HEAD", "--", ".", *excludes],
    )
    changed_paths = nul_paths(changed.stdout)
    if changed_paths:
        errors.append(
            "product files changed after the guide baseline: "
            + ", ".join(changed_paths)
        )

    status = run_git(
        repo,
        [
            "status",
            "--porcelain=v1",
            "-z",
            "--untracked-files=all",
            "--",
            ".",
            *excludes,
        ],
    )
    dirty_entries = nul_paths(status.stdout)
    if dirty_entries:
        display_paths = []
        for entry in dirty_entries:
            display_paths.append(entry[3:] if len(entry) > 3 else entry)
        errors.append("product worktree is dirty: " + ", ".join(display_paths))


def check(repo_argument: Path, guide_argument: Path | None) -> list[str]:
    errors: list[str] = []
    try:
        root_result = run_git(repo_argument, ["rev-parse", "--show-toplevel"])
    except CheckError as exc:
        return [f"repository check failed: {exc}"]

    repo = Path(root_result.stdout.decode("utf-8", errors="strict").strip()).resolve()
    if repo != repo_argument.resolve():
        errors.append(f"repository argument must be the Git root: {repo}")

    if guide_argument is None:
        initial_guide = repo / "docs/project-guide"
    else:
        initial_guide = (
            guide_argument if guide_argument.is_absolute() else repo / guide_argument
        )
    guide_dir = initial_guide.resolve()
    if not inside(guide_dir, repo):
        errors.append(f"guide directory must be inside the repository: {guide_dir}")
        return errors

    manifest = load_manifest(guide_dir, errors)
    if manifest is None:
        return errors

    source, guide_root, pages, files = validate_manifest(manifest, errors)
    if guide_root:
        intended = (repo / guide_root).resolve()
        if not inside(intended, repo):
            errors.append(f"manifest guideRoot escapes the repository: {guide_root}")
        if guide_argument is None and intended != guide_dir:
            errors.append(
                f"manifest guideRoot points to {guide_root}, but the checked guide is elsewhere"
            )

    validate_declared_files(guide_dir, files, errors)
    facts_by_page = parse_pages(guide_dir, pages, source, errors)
    validate_links(guide_dir, facts_by_page, errors)
    excluded_roots: list[str] = []
    if guide_root:
        excluded_roots.append(guide_root)
    try:
        physical_guide_root = guide_dir.relative_to(repo).as_posix()
        if physical_guide_root not in excluded_roots:
            excluded_roots.append(physical_guide_root)
    except ValueError:
        pass

    try:
        validate_git(repo, source, excluded_roots, errors)
    except CheckError as exc:
        errors.append(f"Git freshness check failed: {exc}")
    return errors


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Check Project Guide structure and Git freshness without writing files."
    )
    parser.add_argument("repository", type=Path, help="target Git repository root")
    parser.add_argument(
        "--guide-dir",
        type=Path,
        help="physical guide directory, used for a staged draft or custom check",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    arguments = build_parser().parse_args(argv)
    errors = check(arguments.repository, arguments.guide_dir)
    if errors:
        print(
            f"Project Guide check failed with {len(errors)} problem(s):",
            file=sys.stderr,
        )
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print("Project Guide check passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
