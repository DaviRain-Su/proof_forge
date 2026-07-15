#!/usr/bin/env python3
"""Dependency-free validation for the ProofForge V2 documentation control plane."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
ALLOWED_STATUS = {
    "planned",
    "draft",
    "proposed",
    "in_review",
    "accepted",
    "not_started",
    "blocked",
    "superseded",
    "archived",
    "research",
}
REQUIRED = [
    "index.md",
    "document-status.md",
    "glossary.md",
    "00-business-validation.md",
    "01-prd.md",
    "02-architecture.md",
    "03-technical-spec.md",
    "04-task-breakdown.md",
    "05-test-spec.md",
    "06-implementation-log.md",
    "07-review-report.md",
    "research/source-register.json",
    "research/claim-register.json",
    "targets/README.md",
    "adr/README.md",
]
TARGETS = {
    "01-evm.md",
    "02-solana.md",
    "03-near.md",
    "04-cosmwasm.md",
    "05-soroban.md",
    "06-icp.md",
    "07-noir.md",
    "08-openvm.md",
    "09-aleo.md",
    "10-psy.md",
}


def fail(message: str) -> None:
    print(f"docs-check: {message}", file=sys.stderr)
    raise SystemExit(1)


def frontmatter(path: Path, text: str) -> dict[str, str]:
    if not text.startswith("---\n"):
        fail(f"missing frontmatter: {path.relative_to(ROOT)}")
    end = text.find("\n---\n", 4)
    if end < 0:
        fail(f"unterminated frontmatter: {path.relative_to(ROOT)}")
    result: dict[str, str] = {}
    for line in text[4:end].splitlines():
        if ":" in line:
            key, value = line.split(":", 1)
            result[key.strip()] = value.strip().strip("'\"")
    return result


def check_json() -> None:
    for path in ROOT.rglob("*.json"):
        if any(part in {".lake", "build"} for part in path.parts):
            continue
        try:
            json.loads(path.read_text(encoding="utf-8"))
        except Exception as exc:  # noqa: BLE001 - validation boundary
            fail(f"invalid JSON {path.relative_to(ROOT)}: {exc}")


def check_markdown() -> None:
    ids: dict[str, Path] = {}
    link_re = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
    for path in sorted(DOCS.rglob("*.md")):
        text = path.read_text(encoding="utf-8")
        meta = frontmatter(path, text)
        doc_id = meta.get("id")
        status = meta.get("status")
        if not doc_id:
            fail(f"missing frontmatter id: {path.relative_to(ROOT)}")
        if doc_id in ids:
            fail(f"duplicate document id {doc_id}: {ids[doc_id]} and {path}")
        ids[doc_id] = path
        if status not in ALLOWED_STATUS:
            fail(f"invalid status '{status}' in {path.relative_to(ROOT)}")
        if status == "accepted" and re.search(r"\bTODO\b|待补充|待决定", text, re.IGNORECASE):
            fail(f"accepted document contains unresolved marker: {path.relative_to(ROOT)}")
        for raw_target in link_re.findall(text):
            target = raw_target.split("#", 1)[0].strip()
            if not target or target.startswith(("http://", "https://", "mailto:")):
                continue
            linked = (path.parent / target).resolve()
            if not linked.exists():
                fail(f"broken link {target} in {path.relative_to(ROOT)}")


def main() -> None:
    if not DOCS.is_dir():
        fail("docs/ does not exist")
    for relative in REQUIRED:
        if not (DOCS / relative).is_file():
            fail(f"missing required document: docs/{relative}")
    present_targets = {path.name for path in (DOCS / "targets").glob("*.md")}
    missing_targets = TARGETS - present_targets
    if missing_targets:
        fail(f"missing target dossiers: {sorted(missing_targets)}")
    check_json()
    check_markdown()
    print("docs-check: ok")


if __name__ == "__main__":
    main()
