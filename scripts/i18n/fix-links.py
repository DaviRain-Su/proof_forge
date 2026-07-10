#!/usr/bin/env python3
"""Repair internal Markdown links in docs/zh/ translations.

For translated files, links are paired by occurrence order with the English
source and recomputed relative to the Chinese file. For native Chinese docs,
simple sibling .zh.md / docs-root English fallbacks are applied.
"""
import importlib.util
import os
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
DOCS_ZH = REPO_ROOT / 'docs/zh'
LINK_RE = re.compile(r'\[([^\]]+)\]\(([^)]+)\)')

spec = importlib.util.spec_from_file_location(
    'translate_docs', REPO_ROOT / 'scripts' / 'translate-docs.py'
)
translate_docs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(translate_docs)
ZH_TO_EN = {zh: en for en, zh in translate_docs.DOC_MAP.items()}
EN_TO_ZH = {en: zh for en, zh in translate_docs.DOC_MAP.items()}


def is_external(link: str) -> bool:
    return not link or link.startswith(('http://', 'https://', 'mailto:', 'javascript:', '//', '#', '/'))


def split_link(link: str) -> tuple[str, str]:
    if '#' in link:
        parts = link.split('#', 1)
        return parts[0], parts[1]
    return link, ''


def choose_target(en_target: Path) -> Path:
    rel = str(en_target.relative_to(REPO_ROOT))
    if rel in EN_TO_ZH:
        zh = REPO_ROOT / EN_TO_ZH[rel]
        if zh.exists():
            return zh
    if en_target.suffix == '.md':
        zh = en_target.with_name(en_target.name[:-3] + '.zh.md')
        if zh.exists():
            return zh
    return en_target


def rewrite_translated(zh_path: Path, en_path: Path) -> str | None:
    zh_text = zh_path.read_text(encoding='utf-8')
    en_text = en_path.read_text(encoding='utf-8')
    en_links = list(LINK_RE.finditer(en_text))
    zh_links = list(LINK_RE.finditer(zh_text))
    if len(en_links) != len(zh_links):
        print(
            f'fix-links: link count mismatch in {zh_path}; skipping automatic repair',
            file=sys.stderr,
        )
        return None
    it = iter(en_links)
    changed = False

    def repl(m: re.Match) -> str:
        nonlocal changed
        em = next(it)
        label, link = m.group(1), m.group(2)
        bare, fragment = split_link(link)
        if not bare or is_external(bare):
            return m.group(0)
        en_bare, _ = split_link(em.group(2))
        if not en_bare or is_external(en_bare):
            return m.group(0)
        intended = (en_path.parent / en_bare).resolve()
        if not intended.exists():
            return m.group(0)
        target = choose_target(intended)
        suffix = f'#{fragment}' if fragment else ''
        new_link = os.path.relpath(target, zh_path.parent).replace('\\', '/') + suffix
        if new_link != link:
            changed = True
            return f'[{label}]({new_link})'
        return m.group(0)

    new_text = LINK_RE.sub(repl, zh_text)
    return new_text if changed else None


def rewrite_native(zh_path: Path) -> str | None:
    zh_text = zh_path.read_text(encoding='utf-8')
    changed = False

    def repl(m: re.Match) -> str:
        nonlocal changed
        label, link = m.group(1), m.group(2)
        bare, fragment = split_link(link)
        if not bare or is_external(bare):
            return m.group(0)
        cur = (zh_path.parent / bare).resolve()
        if cur.exists():
            return m.group(0)
        target = None
        if cur.suffix == '.md':
            zh_sib = cur.with_name(cur.name[:-3] + '.zh.md')
            if zh_sib.exists():
                target = zh_sib
        if target is None:
            candidates = [REPO_ROOT / 'docs' / bare]
            if bare.endswith('.md'):
                candidates.append(REPO_ROOT / 'docs' / (bare[:-3] + '.zh.md'))
            for cand in candidates:
                if cand.exists():
                    target = cand
                    break
        if target is None:
            return m.group(0)
        suffix = f'#{fragment}' if fragment else ''
        new_link = os.path.relpath(target, zh_path.parent).replace('\\', '/') + suffix
        if new_link != link:
            changed = True
            return f'[{label}]({new_link})'
        return m.group(0)

    new_text = LINK_RE.sub(repl, zh_text)
    return new_text if changed else None


def main() -> int:
    modified = 0
    skipped = 0
    for zh_path in sorted(DOCS_ZH.rglob('*.md')):
        zh_rel = str(zh_path.relative_to(REPO_ROOT))
        en_rel = ZH_TO_EN.get(zh_rel)
        if en_rel:
            en_path = REPO_ROOT / en_rel
            if not en_path.exists():
                skipped += 1
                continue
            new_text = rewrite_translated(zh_path, en_path)
        else:
            new_text = rewrite_native(zh_path)
        if new_text is not None:
            zh_path.write_text(new_text, encoding='utf-8')
            print(f'fix-links: {zh_rel}')
            modified += 1
    print(f'fix-links: {modified} file(s) modified, {skipped} skipped')
    return 0


if __name__ == '__main__':
    sys.exit(main())
