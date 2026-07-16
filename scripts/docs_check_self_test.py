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
    "| EV-20260716-9001 | TASK-A0-20 | TST-A0-020 | development | synthetic | passed | "
    "synthetic evidence |"
)
FROZEN_A0_TASK_ROWS = "\n".join(
    f"| TASK-A0-{index:02d} | Complete frozen synthetic task | — | — | "
    f"TST-A0-{index:03d} | EV-20260716-{9100 + index:04d} | done |"
    for index in range(1, 20)
)
FROZEN_A0_TEST_ROWS = "\n".join(
    f"| TST-A0-{index:03d} | Frozen synthetic alpha acceptance |"
    for index in range(1, 20)
)
FROZEN_A0_EVIDENCE_ROWS = "\n".join(
    f"| EV-20260716-{9100 + index:04d} | TASK-A0-{index:02d} | "
    f"TST-A0-{index:03d} | development | synthetic | passed | synthetic evidence |"
    for index in range(1, 20)
)
EVIDENCE_ROW_9002_DEVELOPMENT = (
    "| EV-20260716-9002 | TASK-D0-92 | TST-DOC-902 | development | synthetic | "
    "passed | synthetic development evidence |"
)
EVIDENCE_ROW_9003_FORMAL = (
    "| EV-20260716-9003 | — | — | formal | synthetic | passed | "
    "unverified formal evidence |"
)
EVIDENCE_ROW_9004_BOOTSTRAP = (
    "| EV-20260716-9004 | TASK-D0-03 | TST-DOC-902 | bootstrap | synthetic | "
    "passed | synthetic D0 trust-root evidence |"
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
        "docs/04-task-breakdown.md": markdown("PHASE-4-901", f"""
| ID | Task | Dependencies | Prerequisites | Tests | Evidence | Status |
|---|---|---|---|---|---|---|
{FROZEN_A0_TASK_ROWS}
| TASK-A0-20 | Complete synthetic task | — | — | TST-A0-020 | EV-20260716-9001 | done |
| TASK-D0-92 | Planned synthetic task | TASK-A0-20 | — | TST-DOC-902 | — | pending |
"""),
        "docs/05-test-spec.md": markdown("PHASE-5-901", f"""
## 完整 Test ID Catalog

| ID | Test object |
|---|---|
{FROZEN_A0_TEST_ROWS}
| TST-A0-020 | Synthetic alpha acceptance exempt from Phase 1 trace closure |
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
            f"\n{EVIDENCE_HEADER}\n{EVIDENCE_SEPARATOR}\n"
            f"{FROZEN_A0_EVIDENCE_ROWS}\n{EVIDENCE_ROW}\n",
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
    files["AGENTS.md"] = """# AGENTS.md

## Current Checkpoint

| Field | Current value |
|---|---|
| Active task | 无 |
| Next task | TASK-D0-92 |
| Known blocker | 无 |
| Task authority | docs/04-task-breakdown.md |
| Document authority | docs/document-status.md |
"""
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
        "approvers: architecture-owner, product-owner\n"
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
    for index in range(1, 20):
        text = text.replace(
            f"| TASK-A0-{index:02d} | Complete frozen synthetic task | — | — | "
            f"TST-A0-{index:03d}",
            f"| TASK-A0-{index:02d} | Complete frozen synthetic task | — | "
            f"TST-A0-{index:03d}",
            1,
        )
    text = text.replace("| TASK-A0-20 | Complete synthetic task | — | — | TST-A0-020",
                        "| TASK-A0-20 | Complete synthetic task | — | TST-A0-020", 1)
    text = text.replace("| TASK-D0-92 | Planned synthetic task | TASK-A0-20 | — | TST-DOC-902",
                        "| TASK-D0-92 | Planned synthetic task | TASK-A0-20 | TST-DOC-902", 1)
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
            "TST-DOC-902 | — | pending |"
        )
    anchor = (
        "| TASK-D0-92 | Planned synthetic task | TASK-A0-20 | — | "
        "TST-DOC-902 | — | pending |"
    )
    replace(root / "docs/04-task-breakdown.md", anchor, anchor + "\n" + "\n".join(rows))
    task_ids = ", ".join(["TASK-D0-92"] + [f"TASK-LONG-{index:04d}" for index in range(1200)])
    replace(root / "docs/traceability/requirements-matrix.md",
            "| TASK-D0-92 | TST-DOC-902 | specified |",
            f"| {task_ids} | TST-DOC-902 | specified |")


def complete_bootstrap_trust_root_task(root: Path) -> None:
    replace(root / "docs/04-task-breakdown.md",
            "| TASK-D0-92 | Planned synthetic task | TASK-A0-20 | — | "
            "TST-DOC-902 | — | pending |",
            "| TASK-D0-03 | Completed bootstrap task | TASK-A0-20 | — | "
            "TST-DOC-902 | EV-20260716-9004 | done |")
    replace(root / "docs/traceability/requirements-matrix.md", "TASK-D0-92", "TASK-D0-03")
    replace(root / "docs/traceability/evidence-ledger.md", EVIDENCE_ROW,
            EVIDENCE_ROW + "\n" + EVIDENCE_ROW_9004_BOOTSTRAP)


def remove_joint_task_test_trace_edge(root: Path) -> None:
    replace(root / "docs/01-prd.md",
            "| FR-901 | Synthetic functional requirement |",
            "| FR-901 | Synthetic functional requirement |\n"
            "| FR-902 | Synthetic pair-level trace requirement |")
    replace(root / "docs/05-test-spec.md",
            "| TST-DOC-902 | Synthetic pending-task acceptance |",
            "| TST-DOC-902 | Synthetic pending-task acceptance |\n"
            "| TST-DOC-903 | Synthetic pair-level acceptance |")
    replace(root / "docs/04-task-breakdown.md",
            "| TASK-D0-92 | Planned synthetic task | TASK-A0-20 | — | "
            "TST-DOC-902 | — | pending |",
            "| TASK-D0-92 | Planned synthetic task | TASK-A0-20 | — | "
            "TST-DOC-902 | — | pending |\n"
            "| TASK-D0-93 | Pair-level synthetic task | TASK-A0-20 | — | "
            "TST-DOC-902, TST-DOC-903 | — | pending |")
    replace(root / "docs/traceability/requirements-matrix.md",
            "| GOAL-901 | FR-901 | ADR-9001, INV-901 | SPEC-DOC-901 | "
            "TASK-D0-92 | TST-DOC-902 | specified |",
            "| GOAL-901 | FR-901 | ADR-9001, INV-901 | SPEC-DOC-901 | "
            "TASK-D0-92 | TST-DOC-902 | specified |\n"
            "| GOAL-901 | FR-902 | ADR-9001, INV-901 | SPEC-DOC-901 | "
            "TASK-D0-93 | TST-DOC-903 | specified |")


def make_unfinished_dependency(root: Path) -> None:
    replace(root / "docs/01-prd.md",
            "| FR-901 | Synthetic functional requirement |",
            "| FR-901 | Synthetic functional requirement |\n"
            "| FR-902 | Synthetic dependency requirement |")
    replace(root / "docs/05-test-spec.md",
            "| TST-DOC-902 | Synthetic pending-task acceptance |",
            "| TST-DOC-902 | Synthetic pending-task acceptance |\n"
            "| TST-DOC-903 | Synthetic dependency acceptance |")
    replace(root / "docs/04-task-breakdown.md",
            "| TASK-D0-92 | Planned synthetic task | TASK-A0-20 | — | "
            "TST-DOC-902 | — | pending |",
            "| TASK-D0-92 | Active synthetic task | TASK-D0-93 | — | "
            "TST-DOC-902 | — | in_progress |\n"
            "| TASK-D0-93 | Unfinished synthetic dependency | TASK-A0-20 | — | "
            "TST-DOC-903 | — | pending |")
    replace(root / "docs/traceability/requirements-matrix.md",
            "| GOAL-901 | FR-901 | ADR-9001, INV-901 | SPEC-DOC-901 | "
            "TASK-D0-92 | TST-DOC-902 | specified |",
            "| GOAL-901 | FR-901 | ADR-9001, INV-901 | SPEC-DOC-901 | "
            "TASK-D0-92 | TST-DOC-902 | specified |\n"
            "| GOAL-901 | FR-902 | ADR-9001, INV-901 | SPEC-DOC-901 | "
            "TASK-D0-93 | TST-DOC-903 | specified |")


def add_evidence_extra_column(root: Path) -> None:
    path = root / "docs/traceability/evidence-ledger.md"
    text = path.read_text(encoding="utf-8")
    text = text.replace(EVIDENCE_HEADER, EVIDENCE_HEADER[:-1] + "| Extra |", 1)
    text = text.replace(EVIDENCE_SEPARATOR, EVIDENCE_SEPARATOR[:-1] + "|---|", 1)
    for row in [*FROZEN_A0_EVIDENCE_ROWS.splitlines(), EVIDENCE_ROW]:
        text = text.replace(row, row[:-1] + "| extra |", 1)
    path.write_text(text, encoding="utf-8")


def insert_checkpoint_decoy(root: Path) -> None:
    path = root / "AGENTS.md"
    original = path.read_text(encoding="utf-8").replace(
        "| Next task | TASK-D0-92 |", "| Next task | TASK-D0-99 |", 1)
    decoy = """| Field | Current value |
|---|---|
| Active task | 无 |
| Next task | TASK-D0-92 |
| Known blocker | 无 |
| Task authority | docs/04-task-breakdown.md |
| Document authority | docs/document-status.md |

"""
    path.write_text(
        original.replace("# AGENTS.md\n\n", "# AGENTS.md\n\n" + decoy, 1),
        encoding="utf-8",
    )


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
    expect_success("checkpoint-active-match", lambda root: (
        replace(
            root / "docs/04-task-breakdown.md",
            "| TASK-D0-92 | Planned synthetic task | TASK-A0-20 | — | "
            "TST-DOC-902 | — | pending |",
            "| TASK-D0-92 | Active synthetic task | TASK-A0-20 | — | "
            "TST-DOC-902 | — | in_progress |"),
        replace(root / "AGENTS.md", "| Active task | 无 |",
                "| Active task | TASK-D0-92 |"),
        replace(root / "AGENTS.md", "| Next task | TASK-D0-92 |",
                "| Next task | 无 |"),
    ))
    expect_success("checkpoint-blocked-match", lambda root: (
        replace(
            root / "docs/04-task-breakdown.md",
            "| TASK-D0-92 | Planned synthetic task | TASK-A0-20 | — | "
            "TST-DOC-902 | — | pending |",
            "| TASK-D0-92 | Blocked synthetic task | TASK-A0-20 | — | "
            "TST-DOC-902 | — | blocked |"),
        replace(root / "AGENTS.md", "| Known blocker | 无 |",
                "| Known blocker | TASK-D0-92 |"),
    ))
    expect_success("checkpoint-inline-authority-links", lambda root: (
        replace(root / "AGENTS.md", "| Task authority | docs/04-task-breakdown.md |",
                "| Task authority | [tasks](docs/04-task-breakdown.md); mirror only |"),
        replace(root / "AGENTS.md", "| Document authority | docs/document-status.md |",
                "| Document authority | [documents](docs/document-status.md) |"),
    ))
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
        ("checkpoint-required", lambda root: (root / "AGENTS.md").unlink(),
         "PF-DOC-CHECKPOINT", "required checkpoint file is missing"),
        ("checkpoint-header", lambda root: replace(
            root / "AGENTS.md", "| Field | Current value |",
            "| Checkpoint | Current value |"),
         "PF-DOC-CHECKPOINT", "requires exactly one rendered canonical"),
        ("checkpoint-duplicate-section", lambda root: replace(
            root / "AGENTS.md", "## Current Checkpoint",
            "## Current Checkpoint\n\n## Current Checkpoint"),
         "PF-DOC-CHECKPOINT", "requires exactly one rendered ## Current Checkpoint section"),
        ("checkpoint-decoy-table", insert_checkpoint_decoy,
         "PF-DOC-CHECKPOINT", "requires exactly one rendered canonical"),
        ("checkpoint-field-missing", lambda root: replace(
            root / "AGENTS.md", "| Document authority | docs/document-status.md |\n", ""),
         "PF-DOC-CHECKPOINT", "missing checkpoint field Document authority"),
        ("checkpoint-field-duplicate", lambda root: replace(
            root / "AGENTS.md", "| Active task | 无 |",
            "| Active task | 无 |\n| Active task | 无 |"),
         "PF-DOC-CHECKPOINT", "duplicate checkpoint field Active task"),
        ("checkpoint-task-authority", lambda root: replace(
            root / "AGENTS.md", "docs/04-task-breakdown.md", "docs/05-test-spec.md"),
         "PF-DOC-CHECKPOINT", "Task authority must point exactly to docs/04-task-breakdown.md"),
        ("checkpoint-task-authority-substring", lambda root: replace(
            root / "AGENTS.md", "docs/04-task-breakdown.md",
            "xdocs/04-task-breakdown.md.evil"),
         "PF-DOC-CHECKPOINT", "Task authority must point exactly to docs/04-task-breakdown.md"),
        ("checkpoint-document-authority", lambda root: replace(
            root / "AGENTS.md", "docs/document-status.md", "docs/index.md"),
         "PF-DOC-CHECKPOINT", "Document authority must point exactly to docs/document-status.md"),
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
        ("approval-approvers-malformed", lambda root: (
            (root / "docs/glossary.md").write_text(
                accepted((root / "docs/glossary.md").read_text(encoding="utf-8")).replace(
                    "architecture-owner, product-owner",
                    "architecture-owner,product-owner", 1),
                encoding="utf-8"),
        ), "PF-DOC-APPROVAL", "exact ', '-separated ASCII safe-id"),
        ("approval-approvers-duplicate", lambda root: (
            (root / "docs/glossary.md").write_text(
                accepted((root / "docs/glossary.md").read_text(encoding="utf-8")).replace(
                    "architecture-owner, product-owner",
                    "architecture-owner, architecture-owner", 1),
                encoding="utf-8"),
        ), "PF-DOC-APPROVAL", "approvers must be unique"),
        ("approval-approvers-unsorted", lambda root: (
            (root / "docs/glossary.md").write_text(
                accepted((root / "docs/glossary.md").read_text(encoding="utf-8")).replace(
                    "architecture-owner, product-owner",
                    "product-owner, architecture-owner", 1),
                encoding="utf-8"),
        ), "PF-DOC-APPROVAL", "ascending ASCII order"),
        ("approval-approvers-email", lambda root: (
            (root / "docs/glossary.md").write_text(
                accepted((root / "docs/glossary.md").read_text(encoding="utf-8")).replace(
                    "architecture-owner, product-owner",
                    "architecture@example.invalid, product-owner", 1),
                encoding="utf-8"),
        ), "PF-DOC-APPROVAL", "exact ', '-separated ASCII safe-id"),
        ("accepted-todo", lambda root: (
            (root / "docs/glossary.md").write_text(
                accepted((root / "docs/glossary.md").read_text(encoding="utf-8")) + "\nTODO\n",
                encoding="utf-8"),
        ),
         "PF-DOC-ACCEPTED-TODO", "docs/glossary.md"),
        ("accepted-tbd", lambda root: (
            (root / "docs/glossary.md").write_text(
                accepted((root / "docs/glossary.md").read_text(encoding="utf-8")) + "\nTBD\n",
                encoding="utf-8"),
        ),
         "PF-DOC-ACCEPTED-TODO", "docs/glossary.md"),
        ("accepted-unlocked-decision", lambda root: (
            (root / "docs/glossary.md").write_text(
                accepted((root / "docs/glossary.md").read_text(encoding="utf-8")) +
                "\n基准机器待锁。\n",
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
        ("a0-task-outside-frozen-range", lambda root: replace(
            root / "docs/04-task-breakdown.md",
            "| TASK-D0-92 | Planned synthetic task | TASK-A0-20 | — | "
            "TST-DOC-902 | — | pending |",
            "| TASK-D0-92 | Planned synthetic task | TASK-A0-20 | — | "
            "TST-DOC-902 | — | pending |\n"
            "| TASK-A0-21 | Out-of-range frozen task | — | — | "
            "TST-A0-020 | — | pending |"),
         "PF-DOC-ID-FORMAT", "TASK-A0-21"),
        ("a0-test-outside-frozen-range", lambda root: replace(
            root / "docs/05-test-spec.md",
            "| TST-DOC-902 | Synthetic pending-task acceptance |",
            "| TST-DOC-902 | Synthetic pending-task acceptance |\n"
            "| TST-A0-021 | Out-of-range frozen test |"),
         "PF-DOC-ID-FORMAT", "TST-A0-021"),
        ("a0-complete-slice-removed", lambda root: (
            replace(
                root / "docs/04-task-breakdown.md",
                "| TASK-A0-01 | Complete frozen synthetic task | — | — | "
                "TST-A0-001 | EV-20260716-9101 | done |\n", ""),
            replace(
                root / "docs/05-test-spec.md",
                "| TST-A0-001 | Frozen synthetic alpha acceptance |\n", ""),
            replace(
                root / "docs/traceability/evidence-ledger.md",
                "| EV-20260716-9101 | TASK-A0-01 | TST-A0-001 | development | "
                "synthetic | passed | synthetic evidence |\n", ""),
        ), "PF-DOC-TASK-SCHEMA", "missing=['TASK-A0-01']"),
        ("a0-completed-task-reopened", lambda root: replace(
            root / "docs/04-task-breakdown.md",
            "| TASK-A0-01 | Complete frozen synthetic task | — | — | "
            "TST-A0-001 | EV-20260716-9101 | done |",
            "| TASK-A0-01 | Complete frozen synthetic task | — | — | "
            "TST-A0-001 | EV-20260716-9101 | pending |"),
         "PF-DOC-TASK-SCHEMA", "TASK-A0-01 must remain done"),
        ("a0-task-owns-formal-test", lambda root: replace(
            root / "docs/04-task-breakdown.md",
            "| TASK-A0-20 | Complete synthetic task | — | — | "
            "TST-A0-020 | EV-20260716-9001 | done |",
            "| TASK-A0-20 | Complete synthetic task | — | — | "
            "TST-DOC-902 | EV-20260716-9001 | done |"),
         "PF-DOC-TASK-SCHEMA", "TASK-A0-20 must own only TST-A0-020"),
        ("a0-task-test-suffix-mismatch", lambda root: replace(
            root / "docs/04-task-breakdown.md",
            "| TASK-A0-20 | Complete synthetic task | — | — | "
            "TST-A0-020 | EV-20260716-9001 | done |",
            "| TASK-A0-20 | Complete synthetic task | — | — | "
            "TST-A0-019 | EV-20260716-9001 | done |"),
         "PF-DOC-TASK-SCHEMA", "TASK-A0-20 must own only TST-A0-020"),
        ("formal-task-owns-frozen-a0-test", lambda root: replace(
            root / "docs/04-task-breakdown.md",
            "| TASK-D0-92 | Planned synthetic task | TASK-A0-20 | — | "
            "TST-DOC-902 | — | pending |",
            "| TASK-D0-92 | Planned synthetic task | TASK-A0-20 | — | "
            "TST-A0-020 | — | pending |"),
         "PF-DOC-TASK-SCHEMA", "TST-A0-020 may only be owned by TASK-A0-20"),
        ("task-before-test-path-order", lambda root: (
            replace(root / "docs/04-task-breakdown.md", "TASK-D0-92", "TASK--BAD"),
            replace(root / "docs/05-test-spec.md", "TST-DOC-902", "TST--BAD"),
        ), "PF-DOC-ID-FORMAT", "TASK--BAD"),
        ("earlier-task-id-before-later-table-width", lambda root: (
            replace(root / "docs/04-task-breakdown.md", "TASK-A0-20", "TASK--BAD"),
            replace(root / "docs/04-task-breakdown.md",
                    "| TASK-D0-92 | Planned synthetic task | TASK-A0-20 | — | "
                    "TST-DOC-902 | — | pending |",
                    "| TASK-D0-92 | Planned synthetic task | TASK-A0-20 | — | "
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
            "| TASK-D0-92 | Planned synthetic task | TASK-A0-20 | — | TST-DOC-902 | — | pending |",
            "| TASK-D0-92 | Planned synthetic task | TASK-A0-20 | — | TST-DOC-902 | — | pending | extra |"),
         "PF-DOC-TABLE-SHAPE", "TASK-D0-92"),
        ("trace-reference", lambda root: replace(
            root / "docs/traceability/requirements-matrix.md", "SPEC-DOC-901", "SPEC-DOC-999"),
         "PF-DOC-ID-UNKNOWN", "SPEC-DOC-999"),
        ("trace-orphan", lambda root: replace(
            root / "docs/01-prd.md", "| FR-901 | Synthetic functional requirement |",
            "| FR-901 | Synthetic functional requirement |\n| FR-902 | Orphan requirement |"),
         "PF-DOC-TRACE-ORPHAN", "FR-902"),
        ("required-test-orphan", lambda root: replace(
            root / "docs/05-test-spec.md", "| TST-DOC-902 | Synthetic pending-task acceptance |",
            "| TST-DOC-902 | Synthetic pending-task acceptance |\n"
            "| TST-ORPHAN-901 | Required test without task or requirement edge |"),
         "PF-DOC-TRACE-ORPHAN", "required test TST-ORPHAN-901 has no task owner"),
        ("task-owned-test-without-requirement-edge", lambda root: (
            replace(
                root / "docs/05-test-spec.md",
                "| TST-DOC-902 | Synthetic pending-task acceptance |",
                "| TST-DOC-902 | Synthetic pending-task acceptance |\n"
                "| TST-ORPHAN-902 | Task-owned test without requirement edge |"),
            replace(
                root / "docs/04-task-breakdown.md",
                "| TASK-D0-92 | Planned synthetic task | TASK-A0-20 | — | TST-DOC-902 | — | pending |",
                "| TASK-D0-92 | Planned synthetic task | TASK-A0-20 | — | "
                "TST-DOC-902, TST-ORPHAN-902 | — | pending |"),
        ), "PF-DOC-TRACE-ORPHAN",
         "formal task TASK-D0-92 test TST-ORPHAN-902 has no joint requirement trace edge"),
        ("a0-nondigit-prefix-not-exempt", lambda root: replace(
            root / "docs/05-test-spec.md", "| TST-DOC-902 | Synthetic pending-task acceptance |",
            "| TST-DOC-902 | Synthetic pending-task acceptance |\n"
            "| TST-A0-FOO | Noncanonical A0-like required test |"),
         "PF-DOC-ID-FORMAT", "TST-A0-FOO"),
        ("a0-short-prefix-not-exempt", lambda root: replace(
            root / "docs/05-test-spec.md", "| TST-DOC-902 | Synthetic pending-task acceptance |",
            "| TST-DOC-902 | Synthetic pending-task acceptance |\n"
            "| TST-A0-90 | Short A0-like required test |"),
         "PF-DOC-ID-FORMAT", "TST-A0-90"),
        ("a0-suffixed-prefix-not-exempt", lambda root: replace(
            root / "docs/05-test-spec.md", "| TST-DOC-902 | Synthetic pending-task acceptance |",
            "| TST-DOC-902 | Synthetic pending-task acceptance |\n"
            "| TST-A0-020-EXTRA | Suffixed A0-like required test |"),
         "PF-DOC-ID-FORMAT", "TST-A0-020-EXTRA"),
        ("required-test-orphan-source-order", lambda root: replace(
            root / "docs/05-test-spec.md", "| TST-DOC-902 | Synthetic pending-task acceptance |",
            "| TST-DOC-902 | Synthetic pending-task acceptance |\n"
            "| TST-ORPHAN-903 | First required orphan |\n"
            "| TST-ORPHAN-904 | Second required orphan |"),
         "PF-DOC-TRACE-ORPHAN", "required test TST-ORPHAN-903 has no task owner"),
        ("formal-task-orphan", lambda root: replace(
            root / "docs/04-task-breakdown.md",
            "| TASK-D0-92 | Planned synthetic task | TASK-A0-20 | — | TST-DOC-902 | — | pending |",
            "| TASK-D0-92 | Planned synthetic task | TASK-A0-20 | — | TST-DOC-902 | — | pending |\n"
            "| TASK-D9-99 | Untraced formal task | — | — | TST-DOC-902 | — | pending |"),
         "PF-DOC-TRACE-ORPHAN", "formal task TASK-D9-99 has no requirement trace edge"),
        ("a0-like-task-not-exempt", lambda root: replace(
            root / "docs/04-task-breakdown.md",
            "| TASK-D0-92 | Planned synthetic task | TASK-A0-20 | — | TST-DOC-902 | — | pending |",
            "| TASK-D0-92 | Planned synthetic task | TASK-A0-20 | — | TST-DOC-902 | — | pending |\n"
            "| TASK-A0-FOO | Noncanonical A0-like task | — | — | TST-DOC-902 | — | pending |"),
         "PF-DOC-ID-FORMAT", "TASK-A0-FOO"),
        ("joint-task-test-edge", remove_joint_task_test_trace_edge,
         "PF-DOC-TRACE-ORPHAN",
         "formal task TASK-D0-93 test TST-DOC-902 has no joint requirement trace edge"),
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
            "TST-DOC-902", "TST-A0-020"),
         "PF-DOC-TRACE-OWNERSHIP", "TST-A0-020"),
        ("task-dependency", lambda root: replace(
            root / "docs/04-task-breakdown.md", "TASK-A0-20 | — | TST-DOC-902 | — | pending",
            "TASK-D0-999 | — | TST-DOC-902 | — | pending"),
         "PF-DOC-ID-UNKNOWN", "TASK-D0-999"),
        ("task-prerequisite-column", drop_task_prerequisites,
         "PF-DOC-PREREQUISITE", "Prerequisites"),
        ("task-prerequisite-unknown", lambda root: replace(
            root / "docs/04-task-breakdown.md",
            "TASK-A0-20 | — | TST-DOC-902 | — | pending",
            "TASK-A0-20 | PHASE-MISSING@accepted | TST-DOC-902 | — | pending"),
         "PF-DOC-ID-UNKNOWN", "PHASE-MISSING"),
        ("task-prerequisite-unmet", lambda root: (
            replace(root / "docs/04-task-breakdown.md",
                    "| TASK-A0-20 | Complete synthetic task | — | — | "
                    "TST-A0-020 | EV-20260716-9001 | done |",
                    "| TASK-A0-20 | Complete synthetic task | — | PHASE-3-901@accepted | "
                    "TST-A0-020 | EV-20260716-9001 | done |"),
        ),
         "PF-DOC-TASK-DEPENDENCY", "PHASE-3-901"),
        ("task-dependency-cycle", lambda root: replace(
            root / "docs/04-task-breakdown.md", "Complete synthetic task | — | — |",
            "Complete synthetic task | TASK-D0-92 | — |"),
         "PF-DOC-TASK-CYCLE", "TASK-A0-20"),
        ("task-dependency-incomplete", make_unfinished_dependency,
         "PF-DOC-TASK-DEPENDENCY", "TASK-D0-93"),
        ("earlier-done-missing-ev-before-later-unknown-dependency", lambda root: (
            replace(root / "docs/04-task-breakdown.md",
                    "| TASK-A0-20 | Complete synthetic task | — | — | "
                    "TST-A0-020 | EV-20260716-9001 | done |",
                    "| TASK-A0-20 | Complete synthetic task | — | — | "
                    "TST-A0-020 | — | done |"),
            replace(root / "docs/04-task-breakdown.md",
                    "| TASK-D0-92 | Planned synthetic task | TASK-A0-20 | — | "
                    "TST-DOC-902 | — | pending |",
                    "| TASK-D0-92 | Planned synthetic task | TASK-D0-999 | — | "
                    "TST-DOC-902 | — | pending |"),
        ), "PF-DOC-DONE-EV", "TASK-A0-20"),
        ("done-test", lambda root: replace(
            root / "docs/04-task-breakdown.md", "| TST-A0-020 | EV-20260716-9001 | done |",
            "| — | EV-20260716-9001 | done |"),
         "PF-DOC-TASK-SCHEMA", "TASK-A0-20 must own only TST-A0-020"),
        ("done-evidence", lambda root: replace(
            root / "docs/04-task-breakdown.md", "| EV-20260716-9001 | done |", "| — | done |"),
         "PF-DOC-DONE-EV", "TASK-A0-20"),
        ("formal-task-reuses-unrelated-evidence", lambda root: replace(
            root / "docs/04-task-breakdown.md",
            "| TASK-D0-92 | Planned synthetic task | TASK-A0-20 | — | "
            "TST-DOC-902 | — | pending |",
            "| TASK-D0-92 | Planned synthetic task | TASK-A0-20 | — | "
            "TST-DOC-902 | EV-20260716-9001 | done |"),
         "PF-DOC-DONE-EV", "EV-20260716-9001"),
        ("formal-task-development-evidence", lambda root: (
            replace(root / "docs/04-task-breakdown.md",
                    "| TASK-D0-92 | Planned synthetic task | TASK-A0-20 | — | "
                    "TST-DOC-902 | — | pending |",
                    "| TASK-D0-92 | Planned synthetic task | TASK-A0-20 | — | "
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
        ("bootstrap-evidence-unverified", complete_bootstrap_trust_root_task,
         "PF-DOC-EVIDENCE-BOOTSTRAP-UNVERIFIED", "EV-20260716-9004"),
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
        ("evidence-header-extra-column", add_evidence_extra_column,
         "PF-DOC-EVIDENCE-SCHEMA", "exact columns"),
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
        ), "PF-DOC-DONE-EV", "EV-20260716-9101"),
        ("evidence-table-long-fence", lambda root: (
            replace(root / "docs/traceability/evidence-ledger.md",
                    EVIDENCE_HEADER, "````markdown\n```\n" + EVIDENCE_HEADER),
            replace(root / "docs/traceability/evidence-ledger.md",
                    EVIDENCE_ROW, EVIDENCE_ROW + "\n````"),
        ), "PF-DOC-DONE-EV", "EV-20260716-9101"),
        ("evidence-table-comment", lambda root: (
            replace(root / "docs/traceability/evidence-ledger.md",
                    EVIDENCE_HEADER, "<!--\n" + EVIDENCE_HEADER),
            replace(root / "docs/traceability/evidence-ledger.md",
                    EVIDENCE_ROW, EVIDENCE_ROW + "\n-->"),
        ), "PF-DOC-DONE-EV", "EV-20260716-9101"),
        ("evidence-table-multiline-inline-code", lambda root: (
            replace(root / "docs/traceability/evidence-ledger.md",
                    EVIDENCE_HEADER, "``\n" + EVIDENCE_HEADER),
            replace(root / "docs/traceability/evidence-ledger.md",
                    EVIDENCE_ROW, EVIDENCE_ROW + "\n``"),
        ), "PF-DOC-DONE-EV", "EV-20260716-9101"),
        ("evidence-table-indented-code", lambda root: (
            replace(root / "docs/traceability/evidence-ledger.md",
                    EVIDENCE_HEADER, "    " + EVIDENCE_HEADER),
            replace(root / "docs/traceability/evidence-ledger.md",
                    EVIDENCE_SEPARATOR, "    " + EVIDENCE_SEPARATOR),
            replace(root / "docs/traceability/evidence-ledger.md",
                    EVIDENCE_ROW, "    " + EVIDENCE_ROW),
        ), "PF-DOC-DONE-EV", "EV-20260716-9101"),
        ("invariant-fenced", lambda root: replace(
            root / "docs/02-architecture.md", "- INV-901: Synthetic invariant.",
            "```text\n- INV-901: Synthetic invariant.\n```"),
         "PF-DOC-ID-UNKNOWN", "INV-901"),
        ("invariant-id-lowercase", lambda root: replace(
            root / "docs/02-architecture.md", "INV-901", "inv-901"),
         "PF-DOC-ID-FORMAT", "inv-901"),
        ("checkpoint-active-drift", lambda root: replace(
            root / "AGENTS.md", "| Active task | 无 |",
            "| Active task | TASK-D0-92 |"),
         "PF-DOC-CHECKPOINT", "Active task mirrors ['TASK-D0-92'], expected []"),
        ("checkpoint-next-drift", lambda root: replace(
            root / "AGENTS.md", "| Next task | TASK-D0-92 |",
            "| Next task | TASK-D0-99 |"),
         "PF-DOC-CHECKPOINT", "Next task mirrors ['TASK-D0-99'], expected ['TASK-D0-92']"),
        ("checkpoint-next-invalid-token-suffix", lambda root: replace(
            root / "AGENTS.md", "| Next task | TASK-D0-92 |",
            "| Next task | TASK-D0-92evil |"),
         "PF-DOC-CHECKPOINT", "Next task mirrors [], expected ['TASK-D0-92']"),
        ("checkpoint-blocker-drift", lambda root: replace(
            root / "AGENTS.md", "| Known blocker | 无 |",
            "| Known blocker | TASK-D0-92 |"),
         "PF-DOC-CHECKPOINT", "Known blocker mirrors ['TASK-D0-92'], expected []"),
        ("active-task", lambda root: (
            replace(
                root / "docs/04-task-breakdown.md",
                "| TASK-D0-92 | Planned synthetic task | TASK-A0-20 | — | "
                "TST-DOC-902 | — | pending |",
                "| TASK-D0-92 | Planned synthetic task | TASK-A0-20 | — | "
                "TST-DOC-902 | — | pending |\n"
                "| TASK-D0-93 | Active one | — | — | TST-DOC-902 | — | in_progress |\n"
                "| TASK-D0-94 | Active two | — | — | TST-DOC-902 | — | in_progress |"),
            replace(
                root / "docs/traceability/requirements-matrix.md",
                "| TASK-D0-92 | TST-DOC-902 | specified |",
                "| TASK-D0-92, TASK-D0-93, TASK-D0-94 | TST-DOC-902 | specified |"),
        ),
         "PF-DOC-TASK-ACTIVE", "TASK-D0-93"),
    ]
    for name, mutation, code, marker in cases:
        expect_failure(name, mutation, code, marker)
    print(f"docs-check-self-test: ok ({len(cases)} mutations)")


if __name__ == "__main__":
    main()
