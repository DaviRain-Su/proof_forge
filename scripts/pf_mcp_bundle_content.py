#!/usr/bin/env python3
"""Regenerate clients/pf-mcp content index + src/bundled.ts from content/ + monorepo docs."""
from __future__ import annotations

import json
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTENT = ROOT / "clients" / "pf-mcp" / "content"
BUNDLED = ROOT / "clients" / "pf-mcp" / "src" / "bundled.ts"


def sync_from_monorepo() -> None:
    CONTENT.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / "docs/product/chain-client-catalog.v1.json", CONTENT / "chain-client-catalog.v1.json")
    # Product docs: 01-.. / 10-.. / 11-psy / 12-psy …
    for src in sorted((ROOT / "docs/product").glob("[0-9][0-9]-*.md")):
        shutil.copy2(src, CONTENT / src.name)
    for src in sorted((ROOT / "docs/demos").glob("*.md")):
        shutil.copy2(src, CONTENT / src.name)
    # Target dossiers agents often need (Psy DPN boundary)
    for name in ("10-psy.md", "10-psy-dpn-lowering.md"):
        src = ROOT / "docs" / "targets" / name
        if src.exists():
            shutil.copy2(src, CONTENT / src.name)
    mcp_readme = ROOT / "tools/mcp/README.md"
    if mcp_readme.exists():
        shutil.copy2(mcp_readme, CONTENT / "mcp-stdio-readme.md")


def write_docs_index() -> dict:
    docs: list[dict] = []
    files = sorted(CONTENT.glob("*.md")) + sorted(CONTENT.glob("*.json"))
    seen: set[str] = set()
    for f in files:
        if f.name in seen or f.name == "docs-index.json":
            continue
        seen.add(f.name)
        text = f.read_text(encoding="utf-8")
        title = f.name
        if f.suffix == ".md":
            m = re.search(r"^title:\s*(.+)$", text, re.M)
            if m:
                title = m.group(1).strip()
            else:
                m2 = re.search(r"^#\s+(.+)$", text, re.M)
                if m2:
                    title = m2.group(1).strip()
            kind = "markdown"
        else:
            kind = "catalog" if "catalog" in f.name else "markdown"
            if kind == "catalog":
                title = "Chain client catalog"
        docs.append(
            {
                "id": f.name,
                "title": title,
                "bytes": len(text.encode("utf-8")),
                "kind": kind,
            }
        )
    out = {"schema": "proof-forge.mcp.docs-index.v1", "docs": docs}
    (CONTENT / "docs-index.json").write_text(
        json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    return out


def write_bundled() -> None:
    catalog = json.loads((CONTENT / "chain-client-catalog.v1.json").read_text(encoding="utf-8"))
    index = json.loads((CONTENT / "docs-index.json").read_text(encoding="utf-8"))
    md = {
        f.name: f.read_text(encoding="utf-8")
        for f in sorted(CONTENT.glob("*.md"))
    }
    lines = [
        "// AUTO-GENERATED — do not edit by hand.",
        f"export const CATALOG_JSON = {json.dumps(catalog, indent=2, ensure_ascii=False)} as const;",
        "",
        f"export const DOCS_INDEX_JSON = {json.dumps(index, indent=2, ensure_ascii=False)} as const;",
        "",
        "export const MARKDOWN: Record<string, string> = {",
    ]
    for k in sorted(md):
        lines.append(f"  {json.dumps(k)}: {json.dumps(md[k], ensure_ascii=False)},")
    lines.append("};")
    lines.append("")
    BUNDLED.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    sync = "--no-sync" not in sys.argv
    if sync:
        sync_from_monorepo()
    write_docs_index()
    write_bundled()
    print(f"wrote {CONTENT / 'docs-index.json'}")
    print(f"wrote {BUNDLED} ({BUNDLED.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
