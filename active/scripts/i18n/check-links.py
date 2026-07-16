#!/usr/bin/env python3
"""Validate internal Markdown links in docs/zh/."""
import re
import sys
from pathlib import Path

DOCS_ZH = Path('docs/zh')
LINK_RE = re.compile(r'\[([^\]]+)\]\(([^)]+)\)')


def is_external(link: str) -> bool:
    return not link or link.startswith(('http://', 'https://', 'mailto:', 'javascript:', '//', '#', '/'))


def resolve(link: str, src: Path) -> Path | None:
    if '#' in link:
        link = link.split('#', 1)[0]
    if not link or is_external(link):
        return None
    return (src.parent / link).resolve()


def check_file(src: Path, broken: list[tuple[Path, str, Path]]) -> None:
    for _label, link in LINK_RE.findall(src.read_text(encoding='utf-8')):
        target = resolve(link, src)
        if target is None:
            continue
        if target.exists():
            continue
        if link.endswith('.md') and not link.endswith('.zh.md'):
            zh = target.with_name(target.name[:-3] + '.zh.md')
            if zh.exists():
                continue
        broken.append((src, link, target))


def main() -> int:
    if not DOCS_ZH.is_dir():
        print(f'check-links: {DOCS_ZH} not found', file=sys.stderr)
        return 1
    broken: list[tuple[Path, str, Path]] = []
    for src in sorted(DOCS_ZH.rglob('*.md')):
        check_file(src, broken)
    if broken:
        print(f'check-links: {len(broken)} broken link(s):', file=sys.stderr)
        for src, link, target in broken:
            print(f'  {src}: [{link}] -> {target}', file=sys.stderr)
        return 1
    print('check-links: ok')
    return 0


if __name__ == '__main__':
    sys.exit(main())
