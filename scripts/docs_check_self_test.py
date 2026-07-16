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
EVIDENCE_HEADER = (
    "| ID | Task | Tests | Grade | Gate / command | Result | Scope and limitation |"
)
EVIDENCE_SEPARATOR = "|---|---|---|---|---|---|---|"
EVIDENCE_ROW = (
    "| EV-20260716-9001 | TASK-A0-91 | TST-DOC-901 | development | synthetic | passed | "
    "synthetic evidence |"
)
EVIDENCE_ROW_9002_DEVELOPMENT = (
    "| EV-20260716-9002 | TASK-D0-92 | TST-DOC-902 | development | synthetic | "
    "passed | synthetic development evidence |"
)
EVIDENCE_ROW_9003_FORMAL = (
    "| EV-20260716-9003 | — | — | formal | synthetic | passed | "
    "unverified formal evidence |"
)


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
        "docs/document-status.md": markdown("DOC-STATUS-901", """
| 文档族 | 当前文档 | 状态 | 权威范围 |
|---|---|---|---|
| 商业验证 | [00-business-validation.md](00-business-validation.md) | `proposed` | synthetic phase 0 |
| 产品 | [01-prd.md](01-prd.md) | `proposed` | synthetic phase 1 |
| 架构 | [02-architecture.md](02-architecture.md) | `proposed` | synthetic phase 2 |
| 技术规格 | [03-technical-spec.md](03-technical-spec.md) | `proposed` | synthetic phase 3 |
| 实施计划 | [04-task-breakdown.md](04-task-breakdown.md) | `proposed` | synthetic phase 4 |
| 测试 | [05-test-spec.md](05-test-spec.md) | `proposed` | synthetic phase 5 |
| 实现事实 | [06-implementation-log.md](06-implementation-log.md) | `proposed` | synthetic phase 6 |
| 最终评审 | [07-review-report.md](07-review-report.md) | `not_started` | synthetic phase 7 |
"""),
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
        "docs/02-architecture.md": markdown(
            "PHASE-2-901", "## 架构不变量\n\n- INV-901: Synthetic invariant."),
        "docs/03-technical-spec.md": markdown("PHASE-3-901"),
        "docs/04-task-breakdown.md": markdown("PHASE-4-901", """
| ID | Task | Dependencies | Prerequisites | Tests | Evidence | Status |
|---|---|---|---|---|---|---|
| TASK-A0-91 | Complete synthetic task | — | — | TST-DOC-901 | EV-20260716-9001 | done |
| TASK-D0-92 | Planned synthetic task | TASK-A0-91 | — | TST-DOC-902 | — | pending |
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
            "REL-0.1.0-alpha.1", normative=False),
        "docs/specs/synthetic.md": markdown("SPEC-DOC-901"),
        "docs/traceability/requirements-matrix.md": markdown("TRACE-MATRIX-901", """
| Goal | Requirement | ADR/INV | Spec/Module | Task | Test | Evidence |
|---|---|---|---|---|---|---|
| GOAL-901 | FR-901 | ADR-9001, INV-901 | SPEC-DOC-901 | TASK-D0-92 | TST-DOC-902 | specified |
"""),
        "docs/traceability/evidence-ledger.md": markdown(
            "TRACE-EV-LEDGER-901",
            f"\n{EVIDENCE_HEADER}\n{EVIDENCE_SEPARATOR}\n{EVIDENCE_ROW}\n",
            normative=False),
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
        timeout=15,
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


def drop_task_prerequisites(root: Path) -> None:
    path = root / "docs/04-task-breakdown.md"
    text = path.read_text(encoding="utf-8")
    text = text.replace(
        "| ID | Task | Dependencies | Prerequisites | Tests | Evidence | Status |",
        "| ID | Task | Dependencies | Tests | Evidence | Status |", 1)
    text = text.replace("|---|---|---|---|---|---|---|", "|---|---|---|---|---|---|", 1)
    text = text.replace("| TASK-A0-91 | Complete synthetic task | — | — | TST-DOC-901",
                        "| TASK-A0-91 | Complete synthetic task | — | TST-DOC-901", 1)
    text = text.replace("| TASK-D0-92 | Planned synthetic task | TASK-A0-91 | — | TST-DOC-902",
                        "| TASK-D0-92 | Planned synthetic task | TASK-A0-91 | TST-DOC-902", 1)
    path.write_text(text, encoding="utf-8")


def confuse_source_definition(root: Path) -> None:
    (root / "docs/research/source-register.json").write_text(
        json.dumps({"schemaVersion": 1, "sources": []}, indent=2) + "\n",
        encoding="utf-8")
    (root / "docs/not-a-source.md").write_text(
        markdown("SRC-DOC-901", normative=False), encoding="utf-8")


def confuse_test_definition(root: Path) -> None:
    replace(root / "docs/05-test-spec.md",
            "| TST-DOC-902 | Synthetic pending-task acceptance |\n", "")
    (root / "docs/not-a-test.md").write_text(
        markdown("TST-DOC-902", normative=False), encoding="utf-8")


def lowercase_task_id(root: Path) -> None:
    replace(root / "docs/04-task-breakdown.md", "TASK-D0-92", "task-D0-92")
    replace(root / "docs/traceability/requirements-matrix.md", "TASK-D0-92", "task-D0-92")


def add_long_forward_dependency_chain(root: Path) -> None:
    rows = []
    for index in range(1200):
        dependency = f"TASK-LONG-{index + 1:04d}" if index < 1199 else "—"
        rows.append(
            f"| TASK-LONG-{index:04d} | Long dependency task {index} | {dependency} | — | "
            "TST-DOC-901 | — | pending |"
        )
    anchor = (
        "| TASK-D0-92 | Planned synthetic task | TASK-A0-91 | — | "
        "TST-DOC-902 | — | pending |"
    )
    replace(root / "docs/04-task-breakdown.md", anchor, anchor + "\n" + "\n".join(rows))


def replace_root_with_symlink(root: Path) -> None:
    real = root.parent / "real-repo"
    root.rename(real)
    root.symlink_to(real, target_is_directory=True)


def expect_root_ancestor_failure() -> None:
    with tempfile.TemporaryDirectory(prefix="proof-forge-docs-root-ancestor-") as temporary:
        base = Path(temporary).resolve()
        real_parent = base / "real-parent"
        real_root = real_parent / "repo"
        write_corpus(real_root, base_files())
        alias_parent = base / "alias-parent"
        alias_parent.symlink_to(real_parent, target_is_directory=True)
        result = run_checker(alias_parent / "repo")
        if (result.returncode != 1 or result.stdout != ""
                or not result.stderr.startswith("docs-check: PF-DOC-PATH .:")
                or "alias-parent" not in result.stderr):
            raise AssertionError(
                "root-ancestor-symlink: expected stable PF-DOC-PATH; "
                f"exit={result.returncode}\nstdout={result.stdout!r}\nstderr={result.stderr!r}"
            )


def expect_failure(name: str, mutation: Mutation, code: str, marker: str) -> None:
    with tempfile.TemporaryDirectory(prefix=f"proof-forge-docs-{name}-") as temporary:
        root = Path(temporary).resolve() / "repo"
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
        root = Path(temporary).resolve() / "repo"
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
        root = Path(temporary).resolve() / "repo"
        write_corpus(root, base_files())
        result = run_checker(root)
        if result.returncode != 0 or result.stdout != "docs-check: ok\n" or result.stderr != "":
            raise AssertionError(
                f"baseline failed: exit={result.returncode}\n"
                f"stdout={result.stdout!r}\nstderr={result.stderr!r}")

    expect_success("superseded-approval-history", lambda root: (
        (root / "docs/glossary.md").write_text(
            accepted_then_superseded(
                (root / "docs/glossary.md").read_text(encoding="utf-8"),
                "DOC-STATUS-901"),
            encoding="utf-8"),
    ))
    expect_success("fenced-link-ignored", lambda root: (
        root / "docs/glossary.md").write_text(
            (root / "docs/glossary.md").read_text(encoding="utf-8") +
            "\n```markdown\n[example](missing-example.md)\n```\n",
            encoding="utf-8"))
    expect_success("multiline-inline-code-link-ignored", lambda root: (
        root / "docs/glossary.md").write_text(
            (root / "docs/glossary.md").read_text(encoding="utf-8") +
            "\n``example\n[example](missing-inline-example.md)\n``\n",
            encoding="utf-8"))
    expect_success("index-shortcut-reference-reachability", lambda root: replace(
        root / "docs/index.md",
        "- [docs/specs/synthetic.md](specs/synthetic.md)",
        "- [docs/specs/synthetic.md]\n\n"
        "[docs/specs/synthetic.md]: specs/synthetic.md"))
    expect_success("long-forward-dependency-chain", add_long_forward_dependency_chain)
    expect_success("uppercase-https-review-link", lambda root: (
        (root / "docs/glossary.md").write_text(
            accepted((root / "docs/glossary.md").read_text(encoding="utf-8")).replace(
                "reviewLink: https://", "reviewLink: HTTPS://", 1),
            encoding="utf-8"),
    ))
    expect_success("active-json-ignored", lambda root: (
        (root / "active").mkdir(parents=True),
        (root / "active/bad.json").write_text("{not-json}\n", encoding="utf-8"),
    ))
    expect_root_ancestor_failure()

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
        ("frontmatter-updated-date-shape", lambda root: replace(
            root / "docs/glossary.md", "updated: 2026-07-16", "updated: 20260716"),
         "PF-DOC-FRONTMATTER", "20260716"),
        ("frontmatter-encoding", lambda root: (root / "docs/glossary.md").write_bytes(b"\xff"),
         "PF-DOC-ENCODING", "docs/glossary.md"),
        ("json-frontmatter-order", lambda root: (
            replace(root / "docs/glossary.md", "status: proposed", "status: research"),
            (root / "docs/research/source-register.json").write_text(
                "{not-json}\n", encoding="utf-8"),
        ), "PF-DOC-JSON", "source-register.json"),
        ("frontmatter-before-status", lambda root: (
            replace(root / "docs/glossary.md", "status: proposed", "status: research"),
            replace(root / "docs/research/README.md", "---\n", ""),
        ), "PF-DOC-FRONTMATTER", "docs/research/README.md"),
        ("link-before-later-status", lambda root: (
            (root / "docs/glossary.md").write_text(
                (root / "docs/glossary.md").read_text(encoding="utf-8") +
                "\n[missing](missing-before-status.md)\n", encoding="utf-8"),
            replace(root / "docs/research/README.md", "status: proposed", "status: research"),
        ), "PF-DOC-LINK", "missing-before-status.md"),
        ("document-id", lambda root: replace(
            root / "docs/glossary.md", "DOC-GLOSSARY-901", "DOC-STATUS-901"),
         "PF-DOC-ID-DUPLICATE", "DOC-STATUS-901"),
        ("status", lambda root: replace(
            root / "docs/glossary.md", "status: proposed", "status: research"),
         "PF-DOC-STATUS", "docs/glossary.md"),
        ("document-status-index-mismatch", lambda root: replace(
            root / "docs/document-status.md",
            "| 产品 | [01-prd.md](01-prd.md) | `proposed` | synthetic phase 1 |",
            "| 产品 | [01-prd.md](01-prd.md) | `accepted` | synthetic phase 1 |"),
         "PF-DOC-STATUS", "PHASE-1-901"),
        ("document-status-missing-canonical", lambda root: replace(
            root / "docs/document-status.md",
            "| 技术规格 | [03-technical-spec.md](03-technical-spec.md) | `proposed` | "
            "synthetic phase 3 |\n", ""),
         "PF-DOC-STATUS", "docs/03-technical-spec.md"),
        ("document-status-duplicate-canonical", lambda root: replace(
            root / "docs/document-status.md",
            "| 架构 | [02-architecture.md](02-architecture.md) | `proposed` | "
            "synthetic phase 2 |",
            "| 架构 | [02-architecture.md](02-architecture.md) | `proposed` | "
            "synthetic phase 2 |\n"
            "| 架构重复 | [02-architecture.md](02-architecture.md) | `proposed` | "
            "synthetic duplicate phase 2 |"),
         "PF-DOC-STATUS", "docs/02-architecture.md"),
        ("document-status-extra-noncanonical", lambda root: replace(
            root / "docs/document-status.md",
            "| 最终评审 | [07-review-report.md](07-review-report.md) | `not_started` | "
            "synthetic phase 7 |",
            "| 最终评审 | [07-review-report.md](07-review-report.md) | `not_started` | "
            "synthetic phase 7 |\n"
            "| 术语 | [glossary](glossary.md) | `proposed` | synthetic glossary |"),
         "PF-DOC-STATUS", "glossary.md"),
        ("approval", lambda root: replace(
            root / "docs/glossary.md", "status: proposed", "status: accepted"),
         "PF-DOC-APPROVAL", "docs/glossary.md"),
        ("approval-date-shape", lambda root: (
            (root / "docs/glossary.md").write_text(
                accepted((root / "docs/glossary.md").read_text(encoding="utf-8")).replace(
                    "approvedAt: 2026-07-16", "approvedAt: 20260716", 1),
                encoding="utf-8"),
        ),
         "PF-DOC-APPROVAL", "approvedAt"),
        ("accepted-todo", lambda root: (
            (root / "docs/glossary.md").write_text(
                accepted((root / "docs/glossary.md").read_text(encoding="utf-8")) + "\nTODO\n",
                encoding="utf-8"),
        ),
         "PF-DOC-ACCEPTED-TODO", "docs/glossary.md"),
        ("accepted-earlier-link-before-later-todo", lambda root: (
            (root / "docs/glossary.md").write_text(
                accepted((root / "docs/glossary.md").read_text(encoding="utf-8")) +
                "\n[earlier](missing-before-todo.md)\n\nTODO\n",
                encoding="utf-8"),
        ),
         "PF-DOC-LINK", "missing-before-todo.md"),
        ("successor", lambda root: replace(
            root / "docs/glossary.md", "status: proposed", "status: superseded"),
         "PF-DOC-SUCCESSOR", "docs/glossary.md"),
        ("successor-unknown", lambda root: (
            (root / "docs/glossary.md").write_text(
                superseded((root / "docs/glossary.md").read_text(encoding="utf-8"),
                           "DOC-MISSING-901"),
                encoding="utf-8"),
        ),
         "PF-DOC-SUCCESSOR", "DOC-MISSING-901"),
        ("successor-cycle", lambda root: (
            (root / "docs/glossary.md").write_text(
                superseded((root / "docs/glossary.md").read_text(encoding="utf-8"),
                           "DOC-STATUS-901"), encoding="utf-8"),
            (root / "docs/document-status.md").write_text(
                superseded((root / "docs/document-status.md").read_text(encoding="utf-8"),
                           "DOC-GLOSSARY-901"), encoding="utf-8"),
        ), "PF-DOC-SUPERSESSION-CYCLE", "DOC-GLOSSARY-901"),
        ("earlier-supersession-before-later-link", lambda root: (
            (root / "docs/document-status.md").write_text(
                superseded(
                    (root / "docs/document-status.md").read_text(encoding="utf-8"),
                    "DOC-MISSING-901"),
                encoding="utf-8"),
            (root / "docs/glossary.md").write_text(
                (root / "docs/glossary.md").read_text(encoding="utf-8") +
                "\n[later](missing-after-successor.md)\n", encoding="utf-8"),
        ), "PF-DOC-SUCCESSOR", "DOC-MISSING-901"),
        ("accepted-release", lambda root: (root / "docs/releases/0.1.0-alpha.1.md").write_text(
            accepted((root / "docs/releases/0.1.0-alpha.1.md").read_text(encoding="utf-8")),
            encoding="utf-8"),
         "PF-DOC-RELEASE-EVIDENCE", "REL-0.1.0-alpha.1"),
        ("link", lambda root: (root / "docs/glossary.md").write_text(
            (root / "docs/glossary.md").read_text(encoding="utf-8") + "\n[missing](missing.md)\n",
            encoding="utf-8"),
         "PF-DOC-LINK", "missing.md"),
        ("long-link-single-diagnostic", lambda root: (
            root / "docs/glossary.md").write_text(
                (root / "docs/glossary.md").read_text(encoding="utf-8") +
                "\n[long](" + "x" * 5000 + ".md)\n", encoding="utf-8"),
         "PF-DOC-LINK", "exceeds 2048"),
        ("even-backslash-inline-link", lambda root: (root / "docs/glossary.md").write_text(
            (root / "docs/glossary.md").read_text(encoding="utf-8") +
            "\n\\\\[missing](missing-even-backslash.md)\n", encoding="utf-8"),
         "PF-DOC-LINK", "missing-even-backslash.md"),
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
        ("link-reference", lambda root: (root / "docs/glossary.md").write_text(
            (root / "docs/glossary.md").read_text(encoding="utf-8") +
            "\n[dead][missing-reference]\n", encoding="utf-8"),
         "PF-DOC-LINK", "missing-reference"),
        ("earlier-reference-before-later-inline", lambda root: (
            root / "docs/glossary.md").write_text(
                (root / "docs/glossary.md").read_text(encoding="utf-8") +
                "\n[earlier][missing-earlier-reference]\n"
                "\n[later](missing-later-inline.md)\n",
                encoding="utf-8"),
         "PF-DOC-LINK", "missing-earlier-reference"),
        ("link-reference-image", lambda root: (root / "docs/glossary.md").write_text(
            (root / "docs/glossary.md").read_text(encoding="utf-8") +
            "\n![missing image][no-image]\n", encoding="utf-8"),
         "PF-DOC-LINK", "no-image"),
        ("link-shortcut-reference", lambda root: (root / "docs/glossary.md").write_text(
            (root / "docs/glossary.md").read_text(encoding="utf-8") +
            "\n[broken-shortcut]\n\n[broken-shortcut]: missing-shortcut.md\n",
            encoding="utf-8"),
         "PF-DOC-LINK", "missing-shortcut.md"),
        ("fenced-comment-does-not-hide-later-link", lambda root: (
            root / "docs/glossary.md").write_text(
                (root / "docs/glossary.md").read_text(encoding="utf-8") +
                "\n```markdown\n<!--\n```\n"
                "[visible](missing-after-fenced-comment.md)\n",
                encoding="utf-8"),
         "PF-DOC-LINK", "missing-after-fenced-comment.md"),
        ("escaped-backtick-link", lambda root: (root / "docs/glossary.md").write_text(
            (root / "docs/glossary.md").read_text(encoding="utf-8") +
            "\n\\`[dead](missing-escaped.md)\\`\n", encoding="utf-8"),
         "PF-DOC-LINK", "missing-escaped.md"),
        ("unused-reference-reachability", lambda root: replace(
            root / "docs/index.md",
            "- [docs/specs/synthetic.md](specs/synthetic.md)",
            "[unused-spec]: specs/synthetic.md"),
         "PF-DOC-NORMATIVE-ORPHAN", "SPEC-DOC-901"),
        ("earlier-orphan-before-later-link", lambda root: (
            replace(root / "docs/index.md",
                    "- [docs/specs/synthetic.md](specs/synthetic.md)",
                    "[unused-spec]: specs/synthetic.md"),
            (root / "docs/targets/README.md").write_text(
                (root / "docs/targets/README.md").read_text(encoding="utf-8") +
                "\n[later](missing-after-earlier-orphan.md)\n", encoding="utf-8"),
        ), "PF-DOC-NORMATIVE-ORPHAN", "SPEC-DOC-901"),
        ("root-symlink", replace_root_with_symlink,
         "PF-DOC-PATH", "repository root"),
        ("ancestor-symlink", lambda root: (
            (root.parent / "outside-docs").mkdir(),
            (root / "docs/optional").symlink_to(
                root.parent / "outside-docs", target_is_directory=True),
        ), "PF-DOC-PATH", "docs/optional"),
        ("json", lambda root: (root / "docs/research/source-register.json").write_text(
            '{"schemaVersion": 1,}\n', encoding="utf-8"),
         "PF-DOC-JSON", "source-register.json"),
        ("json-duplicate", lambda root: (root / "docs/research/source-register.json").write_text(
            '{"schemaVersion":1,"schemaVersion":1,"sources":[]}\n', encoding="utf-8"),
         "PF-DOC-JSON-DUPLICATE", "schemaVersion"),
        ("json-non-finite", lambda root: (
            root / "docs/research/source-register.json").write_text(
                '{"schemaVersion":1,"sources":[{"id":"SRC-DOC-901",'
                '"status":"verified"}],"bad":NaN}\n', encoding="utf-8"),
         "PF-DOC-JSON", "source-register.json"),
        ("json-depth", lambda root: (root / "docs/deep.json").write_text(
            "[" * 10000 + "0" + "]" * 10000 + "\n", encoding="utf-8"),
         "PF-DOC-JSON", "docs/deep.json"),
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
        ("source-definition-type", confuse_source_definition,
         "PF-DOC-CLAIM-SOURCE", "SRC-DOC-901"),
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
        ("task-before-test-path-order", lambda root: (
            replace(root / "docs/04-task-breakdown.md", "TASK-D0-92", "TASK--BAD"),
            replace(root / "docs/05-test-spec.md", "TST-DOC-902", "TST--BAD"),
        ), "PF-DOC-ID-FORMAT", "TASK--BAD"),
        ("earlier-task-id-before-later-table-width", lambda root: (
            replace(root / "docs/04-task-breakdown.md", "TASK-A0-91", "TASK--BAD"),
            replace(root / "docs/04-task-breakdown.md",
                    "| TASK-D0-92 | Planned synthetic task | TASK-A0-91 | — | "
                    "TST-DOC-902 | — | pending |",
                    "| TASK-D0-92 | Planned synthetic task | TASK-A0-91 | — | "
                    "TST-DOC-902 | — | pending | extra |"),
        ), "PF-DOC-ID-FORMAT", "TASK--BAD"),
        ("test-definition-type", confuse_test_definition,
         "PF-DOC-ID-TYPE", "TST-DOC-902"),
        ("task-id-lowercase", lowercase_task_id,
         "PF-DOC-ID-FORMAT", "task-D0-92"),
        ("task-header", lambda root: replace(
            root / "docs/04-task-breakdown.md", "| Tests |", "| Checks |"),
         "PF-DOC-TASK-SCHEMA", "Tests"),
        ("evidence-id-format", lambda root: replace(
            root / "docs/traceability/evidence-ledger.md",
            "EV-20260716-9001", "EV--BAD"),
         "PF-DOC-ID-FORMAT", "EV--BAD"),
        ("table-width", lambda root: replace(
            root / "docs/04-task-breakdown.md",
            "| TASK-D0-92 | Planned synthetic task | TASK-A0-91 | — | TST-DOC-902 | — | pending |",
            "| TASK-D0-92 | Planned synthetic task | TASK-A0-91 | — | TST-DOC-902 | — | pending | extra |"),
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
            root / "docs/traceability/requirements-matrix.md", "TASK-D0-92", "—"),
         "PF-DOC-TRACE-INCOMPLETE", "FR-901"),
        ("trace-test", lambda root: replace(
            root / "docs/traceability/requirements-matrix.md", "TST-DOC-902", "—"),
         "PF-DOC-TRACE-INCOMPLETE", "FR-901"),
        ("trace-evidence-not-specified", lambda root: replace(
            root / "docs/traceability/requirements-matrix.md",
            "| TST-DOC-902 | specified |", "| TST-DOC-902 | passed |"),
         "PF-DOC-TRACE-INCOMPLETE", "FR-901"),
        ("trace-test-owner", lambda root: replace(
            root / "docs/traceability/requirements-matrix.md",
            "TST-DOC-902", "TST-DOC-901"),
         "PF-DOC-TRACE-OWNERSHIP", "TST-DOC-901"),
        ("task-dependency", lambda root: replace(
            root / "docs/04-task-breakdown.md", "TASK-A0-91 | — | TST-DOC-902 | — | pending",
            "TASK-D0-999 | — | TST-DOC-902 | — | pending"),
         "PF-DOC-ID-UNKNOWN", "TASK-D0-999"),
        ("task-prerequisite-column", drop_task_prerequisites,
         "PF-DOC-PREREQUISITE", "Prerequisites"),
        ("task-prerequisite-unknown", lambda root: replace(
            root / "docs/04-task-breakdown.md",
            "TASK-A0-91 | — | TST-DOC-902 | — | pending",
            "TASK-A0-91 | PHASE-MISSING@accepted | TST-DOC-902 | — | pending"),
         "PF-DOC-ID-UNKNOWN", "PHASE-MISSING"),
        ("task-prerequisite-unmet", lambda root: (
            replace(root / "docs/04-task-breakdown.md",
                    "| TASK-A0-91 | Complete synthetic task | — | — | "
                    "TST-DOC-901 | EV-20260716-9001 | done |",
                    "| TASK-A0-91 | Complete synthetic task | — | PHASE-3-901@accepted | "
                    "TST-DOC-901 | EV-20260716-9001 | done |"),
        ),
         "PF-DOC-TASK-DEPENDENCY", "PHASE-3-901"),
        ("task-dependency-cycle", lambda root: replace(
            root / "docs/04-task-breakdown.md", "Complete synthetic task | — | — |",
            "Complete synthetic task | TASK-D0-92 | — |"),
         "PF-DOC-TASK-CYCLE", "TASK-A0-91"),
        ("task-dependency-incomplete", lambda root: (
            replace(root / "docs/04-task-breakdown.md",
                    "| TASK-A0-91 | Complete synthetic task | — | — | TST-DOC-901 | EV-20260716-9001 | done |",
                    "| TASK-A0-91 | Complete synthetic task | — | — | TST-DOC-901 | — | pending |"),
            replace(root / "docs/04-task-breakdown.md",
                    "| TASK-D0-92 | Planned synthetic task | TASK-A0-91 | — | TST-DOC-902 | — | pending |",
                    "| TASK-D0-92 | Active synthetic task | TASK-A0-91 | — | TST-DOC-902 | — | in_progress |"),
        ),
         "PF-DOC-TASK-DEPENDENCY", "TASK-A0-91"),
        ("earlier-done-missing-ev-before-later-unknown-dependency", lambda root: (
            replace(root / "docs/04-task-breakdown.md",
                    "| TASK-A0-91 | Complete synthetic task | — | — | "
                    "TST-DOC-901 | EV-20260716-9001 | done |",
                    "| TASK-A0-91 | Complete synthetic task | — | — | "
                    "TST-DOC-901 | — | done |"),
            replace(root / "docs/04-task-breakdown.md",
                    "| TASK-D0-92 | Planned synthetic task | TASK-A0-91 | — | "
                    "TST-DOC-902 | — | pending |",
                    "| TASK-D0-92 | Planned synthetic task | TASK-D0-999 | — | "
                    "TST-DOC-902 | — | pending |"),
        ), "PF-DOC-DONE-EV", "TASK-A0-91"),
        ("done-test", lambda root: replace(
            root / "docs/04-task-breakdown.md", "| TST-DOC-901 | EV-20260716-9001 | done |",
            "| — | EV-20260716-9001 | done |"),
         "PF-DOC-DONE-TST", "TASK-A0-91"),
        ("done-evidence", lambda root: replace(
            root / "docs/04-task-breakdown.md", "| EV-20260716-9001 | done |", "| — | done |"),
         "PF-DOC-DONE-EV", "TASK-A0-91"),
        ("formal-task-reuses-unrelated-evidence", lambda root: replace(
            root / "docs/04-task-breakdown.md",
            "| TASK-D0-92 | Planned synthetic task | TASK-A0-91 | — | "
            "TST-DOC-902 | — | pending |",
            "| TASK-D0-92 | Planned synthetic task | TASK-A0-91 | — | "
            "TST-DOC-902 | EV-20260716-9001 | done |"),
         "PF-DOC-DONE-EV", "EV-20260716-9001"),
        ("formal-task-development-evidence", lambda root: (
            replace(root / "docs/04-task-breakdown.md",
                    "| TASK-D0-92 | Planned synthetic task | TASK-A0-91 | — | "
                    "TST-DOC-902 | — | pending |",
                    "| TASK-D0-92 | Planned synthetic task | TASK-A0-91 | — | "
                    "TST-DOC-902 | EV-20260716-9002 | done |"),
            replace(root / "docs/traceability/evidence-ledger.md",
                    EVIDENCE_ROW,
                    EVIDENCE_ROW + "\n" + EVIDENCE_ROW_9002_DEVELOPMENT),
        ),
         "PF-DOC-DONE-EV", "EV-20260716-9002"),
        ("formal-evidence-unverified", lambda root: replace(
            root / "docs/traceability/evidence-ledger.md",
            EVIDENCE_ROW, EVIDENCE_ROW + "\n" + EVIDENCE_ROW_9003_FORMAL),
         "PF-DOC-EVIDENCE-FORMAL-UNVERIFIED", "EV-20260716-9003"),
        ("bootstrap-grade-outside-d0-bootstrap", lambda root: replace(
            root / "docs/traceability/evidence-ledger.md",
            EVIDENCE_ROW, EVIDENCE_ROW.replace(
                "| development |", "| bootstrap |", 1)),
         "PF-DOC-DONE-EV", "EV-20260716-9001"),
        ("unknown-evidence", lambda root: replace(
            root / "docs/04-task-breakdown.md", "EV-20260716-9001", "EV-20260716-9999"),
         "PF-DOC-DONE-EV", "EV-20260716-9999"),
        ("failed-evidence", lambda root: replace(
            root / "docs/traceability/evidence-ledger.md",
            EVIDENCE_ROW, EVIDENCE_ROW.replace("| passed |", "| failed |", 1)),
         "PF-DOC-DONE-EV", "EV-20260716-9001"),
        ("evidence-result-prefix", lambda root: replace(
            root / "docs/traceability/evidence-ledger.md",
            EVIDENCE_ROW, EVIDENCE_ROW.replace("| passed |", "| passedly |", 1)),
         "PF-DOC-DONE-EV", "EV-20260716-9001"),
        ("evidence-header-extra-column", lambda root: (
            replace(root / "docs/traceability/evidence-ledger.md",
                    EVIDENCE_HEADER,
                    EVIDENCE_HEADER[:-1] + "| Extra |"),
            replace(root / "docs/traceability/evidence-ledger.md",
                    EVIDENCE_SEPARATOR,
                    EVIDENCE_SEPARATOR[:-1] + "|---|"),
            replace(root / "docs/traceability/evidence-ledger.md",
                    EVIDENCE_ROW,
                    EVIDENCE_ROW[:-1] + "| extra |"),
        ), "PF-DOC-EVIDENCE-SCHEMA", "exact columns"),
        ("evidence-header-reordered", lambda root: replace(
            root / "docs/traceability/evidence-ledger.md",
            EVIDENCE_HEADER,
            "| ID | Tests | Task | Grade | Gate / command | Result | "
            "Scope and limitation |"),
         "PF-DOC-EVIDENCE-SCHEMA", "exact columns"),
        ("evidence-id-shape", lambda root: (
            replace(root / "docs/04-task-breakdown.md", "EV-20260716-9001", "EV-FOO"),
            replace(root / "docs/traceability/evidence-ledger.md",
                    "EV-20260716-9001", "EV-FOO"),
        ), "PF-DOC-ID-FORMAT", "EV-FOO"),
        ("evidence-table-fenced", lambda root: (
            replace(root / "docs/traceability/evidence-ledger.md",
                    EVIDENCE_HEADER, "```markdown\n" + EVIDENCE_HEADER),
            replace(root / "docs/traceability/evidence-ledger.md",
                    EVIDENCE_ROW, EVIDENCE_ROW + "\n```"),
        ), "PF-DOC-DONE-EV", "EV-20260716-9001"),
        ("evidence-table-long-fence", lambda root: (
            replace(root / "docs/traceability/evidence-ledger.md",
                    EVIDENCE_HEADER, "````markdown\n```\n" + EVIDENCE_HEADER),
            replace(root / "docs/traceability/evidence-ledger.md",
                    EVIDENCE_ROW, EVIDENCE_ROW + "\n````"),
        ), "PF-DOC-DONE-EV", "EV-20260716-9001"),
        ("evidence-table-comment", lambda root: (
            replace(root / "docs/traceability/evidence-ledger.md",
                    EVIDENCE_HEADER, "<!--\n" + EVIDENCE_HEADER),
            replace(root / "docs/traceability/evidence-ledger.md",
                    EVIDENCE_ROW, EVIDENCE_ROW + "\n-->"),
        ), "PF-DOC-DONE-EV", "EV-20260716-9001"),
        ("evidence-table-multiline-inline-code", lambda root: (
            replace(root / "docs/traceability/evidence-ledger.md",
                    EVIDENCE_HEADER, "``\n" + EVIDENCE_HEADER),
            replace(root / "docs/traceability/evidence-ledger.md",
                    EVIDENCE_ROW, EVIDENCE_ROW + "\n``"),
        ), "PF-DOC-DONE-EV", "EV-20260716-9001"),
        ("evidence-table-indented-code", lambda root: (
            replace(root / "docs/traceability/evidence-ledger.md",
                    EVIDENCE_HEADER, "    " + EVIDENCE_HEADER),
            replace(root / "docs/traceability/evidence-ledger.md",
                    EVIDENCE_SEPARATOR, "    " + EVIDENCE_SEPARATOR),
            replace(root / "docs/traceability/evidence-ledger.md",
                    EVIDENCE_ROW, "    " + EVIDENCE_ROW),
        ), "PF-DOC-DONE-EV", "EV-20260716-9001"),
        ("invariant-fenced", lambda root: replace(
            root / "docs/02-architecture.md", "- INV-901: Synthetic invariant.",
            "```text\n- INV-901: Synthetic invariant.\n```"),
         "PF-DOC-ID-UNKNOWN", "INV-901"),
        ("invariant-id-lowercase", lambda root: replace(
            root / "docs/02-architecture.md", "INV-901", "inv-901"),
         "PF-DOC-ID-FORMAT", "inv-901"),
        ("active-task", lambda root: replace(
            root / "docs/04-task-breakdown.md",
            "| TASK-D0-92 | Planned synthetic task | TASK-A0-91 | — | TST-DOC-902 | — | pending |",
            "| TASK-D0-92 | Planned synthetic task | TASK-A0-91 | — | TST-DOC-902 | — | pending |\n"
            "| TASK-D0-93 | Active one | — | — | TST-DOC-901 | — | in_progress |\n"
            "| TASK-D0-94 | Active two | — | — | TST-DOC-901 | — | in_progress |"),
         "PF-DOC-TASK-ACTIVE", "TASK-D0-93"),
    ]
    for name, mutation, code, marker in cases:
        expect_failure(name, mutation, code, marker)
    print(f"docs-check-self-test: ok ({len(cases)} mutations)")


if __name__ == "__main__":
    main()
