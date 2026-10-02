#!/usr/bin/env python3
"""Check relative Markdown links and heading anchors in repository Markdown."""

from __future__ import annotations

import re
import subprocess
import sys
import unicodedata
from pathlib import Path
from urllib.parse import unquote, urlsplit


EXCLUDED_PARTS = {
    "build",
    ".tooling",
    ".dart_tool",
    "node_modules",
    ".gitnexus",
}
INLINE_LINK = re.compile(r"!?\[[^\]]*\]\(\s*(?:<([^>]+)>|([^\s)]+))(?:\s+[^)]*)?\)")
REFERENCE_DEF = re.compile(r"^\s{0,3}\[[^\]]+\]:\s*<?([^\s>]+)>?")
HEADING = re.compile(r"^#{1,6}\s+(.+?)\s*#*\s*$")
HTML_ID = re.compile(r"\bid\s*=\s*['\"]([^'\"]+)['\"]", re.IGNORECASE)


def tracked_markdown() -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "*.md", "**/*.md"],
        check=True,
        stdout=subprocess.PIPE,
    )
    files = []
    for item in result.stdout.decode().split("\0"):
        if not item:
            continue
        path = Path(item)
        if not path.is_file():
            continue
        parts = path.parts
        if any(part in EXCLUDED_PARTS for part in parts):
            continue
        if len(parts) >= 3 and parts[0] == ".claude" and parts[1] == "skills" and parts[2].startswith("gitnexus"):
            continue
        if len(parts) >= 3 and parts[0] == "packages" and parts[-2] == "build":
            continue
        files.append(path)
    return files


def slug(text: str) -> str:
    text = re.sub(r"<[^>]*>", "", text)
    text = re.sub(r"!?\[([^\]]+)\]\([^)]*\)", r"\1", text)
    text = text.strip().lower()
    text = "".join(
        char for char in text
        if char == "-" or char == "_" or char.isspace()
        or unicodedata.category(char)[0] in {"L", "N"}
    )
    return re.sub(r"\s+", "-", text)


def anchors(path: Path) -> set[str]:
    result: set[str] = set()
    counts: dict[str, int] = {}
    fenced = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if re.match(r"^\s{0,3}(```|~~~)", line):
            fenced = not fenced
            continue
        if fenced:
            continue
        for html_id in HTML_ID.findall(line):
            result.add(html_id)
        match = HEADING.match(line)
        if match:
            base = slug(match.group(1))
            count = counts.get(base, 0)
            counts[base] = count + 1
            result.add(base if count == 0 else f"{base}-{count}")
    return result


def markdown_lines(path: Path) -> list[tuple[int, str]]:
    lines = []
    fenced = False
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if re.match(r"^\s{0,3}(```|~~~)", line):
            fenced = not fenced
            continue
        if not fenced:
            lines.append((number, line))
    return lines


def links(path: Path) -> list[tuple[int, str]]:
    definitions: dict[str, str] = {}
    extracted: list[tuple[int, str]] = []
    lines = markdown_lines(path)
    for number, line in lines:
        definition = REFERENCE_DEF.match(line)
        if definition:
            definitions[definition.group(1).lower()] = definition.group(1)
        for match in INLINE_LINK.finditer(line):
            extracted.append((number, match.group(1) or match.group(2)))

    for number, line in lines:
        for match in re.finditer(r"!?\[([^\]]+)\]\[([^\]]*)\]", line):
            label = (match.group(2) or match.group(1)).lower()
            target = definitions.get(label)
            if target:
                extracted.append((number, target))
    return extracted


def main() -> int:
    files = tracked_markdown()
    file_set = {path.as_posix() for path in files}
    anchor_cache: dict[str, set[str]] = {}
    errors: list[tuple[str, int, str]] = []

    for source in files:
        source_name = source.as_posix()
        for line, raw_target in links(source):
            target = unquote(raw_target.strip())
            parsed = urlsplit(target)
            if parsed.scheme.lower() in {"http", "https", "mailto"} or target.startswith("//"):
                continue
            target_path = Path(parsed.path) if parsed.path else source
            if parsed.path and not target_path.is_absolute():
                target_path = source.parent / target_path
            target_path = Path(re.sub(r"/{2,}", "/", str(target_path)))
            try:
                normalized = target_path.resolve().relative_to(Path.cwd().resolve()).as_posix()
            except ValueError:
                errors.append((source_name, line, raw_target))
                continue
            if not target_path.exists():
                errors.append((source_name, line, raw_target))
                continue
            if parsed.fragment:
                if target_path.is_dir():
                    candidates = (target_path / "README.md", target_path / "index.md")
                    target_md = next((candidate for candidate in candidates if candidate.exists()), None)
                    normalized = target_md.relative_to(Path.cwd()).as_posix() if target_md else normalized
                elif target_path.suffix.lower() == ".md":
                    target_md = target_path
                else:
                    target_md = None
                if target_md is not None:
                    key = target_md.as_posix()
                    if key not in anchor_cache:
                        anchor_cache[key] = anchors(target_md)
                    if unquote(parsed.fragment) not in anchor_cache[key]:
                        errors.append((source_name, line, raw_target))
            if normalized not in file_set and target_path.suffix.lower() == ".md":
                # Untracked target files are not valid documentation links.
                errors.append((source_name, line, raw_target))

    if errors:
        for source, line, target in sorted(set(errors)):
            print(f"{source}:{line}: {target}")
        return 1
    print(f"Checked {len(files)} indexed/worktree Markdown files; no broken relative links or anchors.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
