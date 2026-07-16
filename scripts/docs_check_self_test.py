#!/usr/bin/env python3
"""Mutation tests for the dependency-free documentation control-plane checker."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from collections.abc import Callable
from pathlib import Path


CHECKER = Path(__file__).with_name("docs_check.py")
TARGETS = [
    "01-evm.md", "02-solana.md", "03-near.md", "04-cosmwasm.md", "05-soroban.md",
    "06-icp.md", "07-noir.md", "08-openvm.md", "09-aleo.md", "10-psy.md",
]


def markdown(doc_id: str, body: str = "", *, status: str = "proposed",
             normative: bool = True) -> str:
    return (
        "---\n"
        f"id: {doc_id}\n"
        f"title: Synthetic {doc_id}\n"
        f"status: {status}\n"
        "owner: quality\n"
        "updated: 2026-07-16\n"
        f"normative: {'true' if normative else 'false'}\n"
        "---\n\n"
        f"# {doc_id}\n\n{body}\n"
    )


def base_files() -> dict[str, str]:
    files = {
        "docs/document-status.md": markdown("DOC-STATUS-901"),
        "docs/glossary.md": markdown("DOC-GLOSSARY-901"),
        "docs/00-business-validation.md": markdown("PHASE-0-901", """
| ID | Hypothesis |
|---|---|
| BV-901 | Synthetic business hypothesis |
""", normative=False),
        "docs/01-prd.md": markdown("PHASE-1-901", """
| ID | Requirement |
|---|---|
| GOAL-901 | Synthetic product goal |
| FR-901 | Synthetic functional requirement |
"""),
        "docs/02-architecture.md": markdown("PHASE-2-901", "- INV-901: Synthetic invariant."),
        "docs/03-technical-spec.md": markdown("PHASE-3-901"),
        "docs/04-task-breakdown.md": markdown("PHASE-4-901", """
| ID | Task | Dependencies | Tests | Evidence | Status |
|---|---|---|---|---|---|
| TASK-D0-91 | Complete synthetic task | — | TST-DOC-901 | EV-20260716-9001 | done |
| TASK-D0-92 | Planned synthetic task | TASK-D0-91 | TST-DOC-901 | — | pending |
"""),
        "docs/05-test-spec.md": markdown("PHASE-5-901", """
## 完整 Test ID Catalog

| ID | Test object |
|---|---|
| TST-DOC-901 | Synthetic docs acceptance |
| TST-DOC-902 | Synthetic pending-task acceptance |
"""),
        "docs/06-implementation-log.md": markdown("PHASE-6-901", normative=False),
        "docs/07-review-report.md": markdown(
            "PHASE-7-901", status="not_started", normative=False),
        "docs/research/README.md": markdown("RESEARCH-INDEX-901", normative=False),
        "docs/targets/README.md": markdown("TARGET-INDEX-901"),
        "docs/adr/README.md": markdown("ADR-INDEX-901"),
        "docs/adr/9001-synthetic.md": markdown("ADR-9001"),
        "docs/releases/0.1.0-alpha.1.md": markdown(
            "REL-0.1.0-alpha.1", status="draft", normative=False),
        "docs/specs/synthetic.md": markdown("SPEC-DOC-901"),
        "docs/traceability/requirements-matrix.md": markdown("TRACE-MATRIX-901", """
| Goal | Requirement | ADR/INV | Spec/Module | Task | Test | Evidence |
|---|---|---|---|---|---|---|
| GOAL-901 | FR-901 | ADR-9001, INV-901 | SPEC-DOC-901 | TASK-D0-91 | TST-DOC-901 | specified |
"""),
        "docs/traceability/evidence-ledger.md": markdown(
            "TRACE-EV-LEDGER-901", """
| ID | Gate | Result | Scope |
|---|---|---|---|
| EV-20260716-9001 | synthetic | passed | synthetic evidence |
""", normative=False),
        "docs/research/source-register.json": json.dumps({
            "schemaVersion": 1,
            "sources": [{"id": "SRC-DOC-901", "status": "verified"}],
        }, indent=2) + "\n",
        "docs/research/claim-register.json": json.dumps({
            "schemaVersion": 1,
            "claims": [{
                "id": "CLM-DOC-901",
                "kind": "fact",
                "status": "verified",
                "sources": ["SRC-DOC-901"],
            }],
        }, indent=2) + "\n",
    }
    for index, target in enumerate(TARGETS, start=1):
        files[f"docs/targets/{target}"] = markdown(f"TARGET-SYNTH-{index:03d}")
    links = []
    for relative in sorted(files):
        if relative.endswith(".md") and relative != "docs/index.md":
            links.append(f"- [{relative}]({relative.removeprefix('docs/')})")
    files["docs/index.md"] = markdown("DOC-INDEX-901", "\n".join(links))
    return files


def write_corpus(root: Path, files: dict[str, str]) -> None:
    for relative, content in files.items():
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")


def run_checker(root: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, "-I", "-S", str(CHECKER), "--root", str(root)],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
    )


def accepted(text: str) -> str:
    return text.replace(
        "status: proposed\n",
        "status: accepted\n"
        "approvers: product@example.invalid, architecture@example.invalid\n"
        "approvedAt: 2026-07-16\n"
        "reviewCommit: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        "reviewLink: https://example.invalid/review/1\n"
        "openFindings: none\n",
        1,
    )


def superseded(text: str, successor: str) -> str:
    return text.replace(
        "status: proposed\n",
        f"status: superseded\nsuccessor: {successor}\n",
        1,
    )


def accepted_then_superseded(text: str, successor: str) -> str:
    return accepted(text).replace(
        "status: accepted\n",
        f"status: superseded\nsuccessor: {successor}\n",
        1,
    )


Mutation = Callable[[Path], None]


def replace(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise AssertionError(f"mutation anchor missing in {path}: {old!r}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def expect_failure(name: str, mutation: Mutation, code: str, marker: str) -> None:
    with tempfile.TemporaryDirectory(prefix=f"proof-forge-docs-{name}-") as temporary:
        root = Path(temporary) / "repo"
        write_corpus(root, base_files())
        mutation(root)
        first = run_checker(root)
        second = run_checker(root)
        lines = first.stderr.splitlines()
        if (first.returncode != 1 or first.stdout != "" or len(lines) != 1
                or not lines[0].startswith(f"docs-check: {code} ")
                or marker not in lines[0] or "Traceback" in first.stderr
                or (first.returncode, first.stdout, first.stderr)
                != (second.returncode, second.stdout, second.stderr)):
            raise AssertionError(
                f"{name}: expected deterministic single diagnostic containing "
                f"{code!r} and {marker!r}; exit={first.returncode}\n"
                f"stdout={first.stdout!r}\nstderr={first.stderr!r}\n"
                f"second={second.returncode, second.stdout, second.stderr!r}"
            )


def expect_success(name: str, mutation: Mutation) -> None:
    with tempfile.TemporaryDirectory(prefix=f"proof-forge-docs-{name}-") as temporary:
        root = Path(temporary) / "repo"
        write_corpus(root, base_files())
        mutation(root)
        result = run_checker(root)
        if result.returncode != 0 or result.stderr != "" or result.stdout != "docs-check: ok\n":
            raise AssertionError(
                f"{name}: expected success; exit={result.returncode}\n"
                f"stdout={result.stdout!r}\nstderr={result.stderr!r}"
            )


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="proof-forge-docs-baseline-") as temporary:
        root = Path(temporary) / "repo"
        write_corpus(root, base_files())
        result = run_checker(root)
        if result.returncode != 0:
            raise AssertionError(f"baseline failed:\n{result.stdout}{result.stderr}")

    expect_success("superseded-approval-history", lambda root: (
        root / "docs/glossary.md").write_text(
            accepted_then_superseded(
                (root / "docs/glossary.md").read_text(encoding="utf-8"),
                "DOC-STATUS-901"),
            encoding="utf-8"))

    cases: list[tuple[str, Mutation, str, str]] = [
        ("required", lambda root: (root / "docs/index.md").unlink(),
         "PF-DOC-REQUIRED", "docs/index.md"),
        ("required-order", lambda root: (
            (root / "docs/index.md").unlink(),
            (root / "docs/00-business-validation.md").unlink(),
        ), "PF-DOC-REQUIRED", "docs/00-business-validation.md"),
        ("frontmatter", lambda root: replace(root / "docs/glossary.md", "---\n", "",),
         "PF-DOC-FRONTMATTER", "docs/glossary.md"),
        ("frontmatter-duplicate", lambda root: replace(
            root / "docs/glossary.md", "owner: quality\n", "owner: quality\nowner: duplicate\n"),
         "PF-DOC-FRONTMATTER", "owner"),
        ("frontmatter-unknown", lambda root: replace(
            root / "docs/glossary.md", "owner: quality\n", "owner: quality\nunknownField: value\n"),
         "PF-DOC-FRONTMATTER", "unknownField"),
        ("document-id", lambda root: replace(
            root / "docs/glossary.md", "DOC-GLOSSARY-901", "DOC-STATUS-901"),
         "PF-DOC-ID-DUPLICATE", "DOC-STATUS-901"),
        ("status", lambda root: replace(
            root / "docs/glossary.md", "status: proposed", "status: research"),
         "PF-DOC-STATUS", "docs/glossary.md"),
        ("approval", lambda root: replace(
            root / "docs/glossary.md", "status: proposed", "status: accepted"),
         "PF-DOC-APPROVAL", "docs/glossary.md"),
        ("accepted-todo", lambda root: (root / "docs/glossary.md").write_text(
            accepted((root / "docs/glossary.md").read_text(encoding="utf-8")) + "\nTODO\n",
            encoding="utf-8"),
         "PF-DOC-ACCEPTED-TODO", "docs/glossary.md"),
        ("successor", lambda root: replace(
            root / "docs/glossary.md", "status: proposed", "status: superseded"),
         "PF-DOC-SUCCESSOR", "docs/glossary.md"),
        ("successor-unknown", lambda root: (root / "docs/glossary.md").write_text(
            superseded((root / "docs/glossary.md").read_text(encoding="utf-8"), "DOC-MISSING-901"),
            encoding="utf-8"),
         "PF-DOC-SUCCESSOR", "DOC-MISSING-901"),
        ("successor-cycle", lambda root: (
            (root / "docs/glossary.md").write_text(
                superseded((root / "docs/glossary.md").read_text(encoding="utf-8"),
                           "DOC-STATUS-901"), encoding="utf-8"),
            (root / "docs/document-status.md").write_text(
                superseded((root / "docs/document-status.md").read_text(encoding="utf-8"),
                           "DOC-GLOSSARY-901"), encoding="utf-8"),
        ), "PF-DOC-SUPERSESSION-CYCLE", "DOC-GLOSSARY-901"),
        ("accepted-release", lambda root: (root / "docs/releases/0.1.0-alpha.1.md").write_text(
            accepted((root / "docs/releases/0.1.0-alpha.1.md").read_text(encoding="utf-8")),
            encoding="utf-8"),
         "PF-DOC-RELEASE-EVIDENCE", "REL-0.1.0-alpha.1"),
        ("link", lambda root: (root / "docs/glossary.md").write_text(
            (root / "docs/glossary.md").read_text(encoding="utf-8") + "\n[missing](missing.md)\n",
            encoding="utf-8"),
         "PF-DOC-LINK", "missing.md"),
        ("link-escape", lambda root: (
            (root.parent / "outside.md").write_text("outside\n", encoding="utf-8"),
            (root / "docs/glossary.md").write_text(
                (root / "docs/glossary.md").read_text(encoding="utf-8") +
                "\n[escape](../../outside.md)\n", encoding="utf-8"),
        ), "PF-DOC-LINK-ESCAPE", "../../outside.md"),
        ("link-fragment", lambda root: (root / "docs/glossary.md").write_text(
            (root / "docs/glossary.md").read_text(encoding="utf-8") +
            "\n[dead anchor](document-status.md#does-not-exist)\n", encoding="utf-8"),
         "PF-DOC-LINK-FRAGMENT", "does-not-exist"),
        ("json", lambda root: (root / "docs/research/source-register.json").write_text(
            '{"schemaVersion": 1,}\n', encoding="utf-8"),
         "PF-DOC-JSON", "source-register.json"),
        ("json-duplicate", lambda root: (root / "docs/research/source-register.json").write_text(
            '{"schemaVersion":1,"schemaVersion":1,"sources":[]}\n', encoding="utf-8"),
         "PF-DOC-JSON-DUPLICATE", "schemaVersion"),
        ("registry-symlink", lambda root: (
            (root.parent / "outside-source-register.json").write_text(
                (root / "docs/research/source-register.json").read_text(encoding="utf-8"),
                encoding="utf-8"),
            (root / "docs/research/source-register.json").unlink(),
            (root / "docs/research/source-register.json").symlink_to(
                root.parent / "outside-source-register.json"),
        ), "PF-DOC-PATH", "source-register.json"),
        ("source-id-format", lambda root: replace(
            root / "docs/research/source-register.json", "SRC-DOC-901", "SRC--BAD"),
         "PF-DOC-ID-FORMAT", "SRC--BAD"),
        ("claim-id-format", lambda root: replace(
            root / "docs/research/claim-register.json", "CLM-DOC-901", "CLM--BAD"),
         "PF-DOC-ID-FORMAT", "CLM--BAD"),
        ("claim-source", lambda root: replace(
            root / "docs/research/claim-register.json", "SRC-DOC-901", "SRC-DOC-999"),
         "PF-DOC-CLAIM-SOURCE", "SRC-DOC-999"),
        ("claim-source-empty", lambda root: replace(
            root / "docs/research/claim-register.json", '"sources": [\n        "SRC-DOC-901"\n      ]',
            '"sources": []'),
         "PF-DOC-CLAIM-SOURCE", "CLM-DOC-901"),
        ("embedded-id-duplicate", lambda root: replace(
            root / "docs/01-prd.md", "| FR-901 | Synthetic functional requirement |",
            "| FR-901 | Synthetic functional requirement |\n| FR-901 | Duplicate requirement |"),
         "PF-DOC-ID-DUPLICATE", "FR-901"),
        ("business-id-duplicate", lambda root: replace(
            root / "docs/00-business-validation.md", "| BV-901 | Synthetic business hypothesis |",
            "| BV-901 | Synthetic business hypothesis |\n| BV-901 | Duplicate hypothesis |"),
         "PF-DOC-ID-DUPLICATE", "BV-901"),
        ("task-id-format", lambda root: replace(
            root / "docs/04-task-breakdown.md", "TASK-D0-92", "TASK--BAD"),
         "PF-DOC-ID-FORMAT", "TASK--BAD"),
        ("test-id-format", lambda root: replace(
            root / "docs/05-test-spec.md", "TST-DOC-902", "TST--BAD"),
         "PF-DOC-ID-FORMAT", "TST--BAD"),
        ("evidence-id-format", lambda root: replace(
            root / "docs/traceability/evidence-ledger.md",
            "EV-20260716-9001", "EV--BAD"),
         "PF-DOC-ID-FORMAT", "EV--BAD"),
        ("table-width", lambda root: replace(
            root / "docs/04-task-breakdown.md",
            "| TASK-D0-92 | Planned synthetic task | TASK-D0-91 | TST-DOC-901 | — | pending |",
            "| TASK-D0-92 | Planned synthetic task | TASK-D0-91 | TST-DOC-901 | — | pending | extra |"),
         "PF-DOC-TABLE-SHAPE", "TASK-D0-92"),
        ("trace-reference", lambda root: replace(
            root / "docs/traceability/requirements-matrix.md", "SPEC-DOC-901", "SPEC-DOC-999"),
         "PF-DOC-ID-UNKNOWN", "SPEC-DOC-999"),
        ("trace-orphan", lambda root: replace(
            root / "docs/01-prd.md", "| FR-901 | Synthetic functional requirement |",
            "| FR-901 | Synthetic functional requirement |\n| FR-902 | Orphan requirement |"),
         "PF-DOC-TRACE-ORPHAN", "FR-902"),
        ("goal-orphan", lambda root: replace(
            root / "docs/01-prd.md", "| GOAL-901 | Synthetic product goal |",
            "| GOAL-901 | Synthetic product goal |\n| GOAL-902 | Orphan goal |"),
         "PF-DOC-TRACE-ORPHAN", "GOAL-902"),
        ("trace-adr", lambda root: replace(
            root / "docs/traceability/requirements-matrix.md", "ADR-9001, INV-901", "—"),
         "PF-DOC-TRACE-INCOMPLETE", "FR-901"),
        ("trace-spec", lambda root: replace(
            root / "docs/traceability/requirements-matrix.md", "SPEC-DOC-901", "—"),
         "PF-DOC-TRACE-INCOMPLETE", "FR-901"),
        ("trace-task", lambda root: replace(
            root / "docs/traceability/requirements-matrix.md", "TASK-D0-91", "—"),
         "PF-DOC-TRACE-INCOMPLETE", "FR-901"),
        ("trace-test", lambda root: replace(
            root / "docs/traceability/requirements-matrix.md", "TST-DOC-901", "—"),
         "PF-DOC-TRACE-INCOMPLETE", "FR-901"),
        ("trace-test-owner", lambda root: (
            replace(root / "docs/04-task-breakdown.md",
                    "| TASK-D0-92 | Planned synthetic task | TASK-D0-91 | TST-DOC-901 | — | pending |",
                    "| TASK-D0-92 | Planned synthetic task | TASK-D0-91 | TST-DOC-902 | — | pending |"),
            replace(root / "docs/traceability/requirements-matrix.md",
                    "TST-DOC-901", "TST-DOC-902"),
        ), "PF-DOC-TRACE-OWNERSHIP", "TST-DOC-902"),
        ("task-dependency", lambda root: replace(
            root / "docs/04-task-breakdown.md", "TASK-D0-91 | TST-DOC-901 | — | pending",
            "TASK-D0-999 | TST-DOC-901 | — | pending"),
         "PF-DOC-ID-UNKNOWN", "TASK-D0-999"),
        ("task-dependency-cycle", lambda root: replace(
            root / "docs/04-task-breakdown.md", "Complete synthetic task | — |",
            "Complete synthetic task | TASK-D0-92 |"),
         "PF-DOC-TASK-CYCLE", "TASK-D0-91"),
        ("task-dependency-incomplete", lambda root: (
            replace(root / "docs/04-task-breakdown.md",
                    "| TASK-D0-91 | Complete synthetic task | — | TST-DOC-901 | EV-20260716-9001 | done |",
                    "| TASK-D0-91 | Complete synthetic task | — | TST-DOC-901 | — | pending |"),
            replace(root / "docs/04-task-breakdown.md",
                    "| TASK-D0-92 | Planned synthetic task | TASK-D0-91 | TST-DOC-901 | — | pending |",
                    "| TASK-D0-92 | Active synthetic task | TASK-D0-91 | TST-DOC-901 | — | in_progress |"),
        ),
         "PF-DOC-TASK-DEPENDENCY", "TASK-D0-91"),
        ("done-test", lambda root: replace(
            root / "docs/04-task-breakdown.md", "| TST-DOC-901 | EV-20260716-9001 | done |",
            "| — | EV-20260716-9001 | done |"),
         "PF-DOC-DONE-TST", "TASK-D0-91"),
        ("done-evidence", lambda root: replace(
            root / "docs/04-task-breakdown.md", "| EV-20260716-9001 | done |", "| — | done |"),
         "PF-DOC-DONE-EV", "TASK-D0-91"),
        ("unknown-evidence", lambda root: replace(
            root / "docs/04-task-breakdown.md", "EV-20260716-9001", "EV-20260716-9999"),
         "PF-DOC-DONE-EV", "EV-20260716-9999"),
        ("failed-evidence", lambda root: replace(
            root / "docs/traceability/evidence-ledger.md", "| passed |", "| failed |"),
         "PF-DOC-DONE-EV", "EV-20260716-9001"),
        ("evidence-result-prefix", lambda root: replace(
            root / "docs/traceability/evidence-ledger.md", "| passed |", "| passedly |"),
         "PF-DOC-DONE-EV", "EV-20260716-9001"),
        ("active-task", lambda root: replace(
            root / "docs/04-task-breakdown.md",
            "| TASK-D0-92 | Planned synthetic task | TASK-D0-91 | TST-DOC-901 | — | pending |",
            "| TASK-D0-92 | Planned synthetic task | TASK-D0-91 | TST-DOC-901 | — | pending |\n"
            "| TASK-D0-93 | Active one | — | TST-DOC-901 | — | in_progress |\n"
            "| TASK-D0-94 | Active two | — | TST-DOC-901 | — | in_progress |"),
         "PF-DOC-TASK-ACTIVE", "TASK-D0-93"),
    ]
    for name, mutation, code, marker in cases:
        expect_failure(name, mutation, code, marker)
    print(f"docs-check-self-test: ok ({len(cases)} mutations)")


if __name__ == "__main__":
    main()
