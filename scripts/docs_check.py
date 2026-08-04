#!/usr/bin/env python3
"""Dependency-free development or governance validation for ProofForge V2 docs."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import re
import stat
import sys
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Any, Callable, Iterable
from urllib.parse import unquote


DEFAULT_ROOT = Path(__file__).absolute().parents[1]
ALLOWED_STATUS = {
    "draft",
    "proposed",
    "in_review",
    "accepted",
    "not_started",
    "superseded",
    "archived",
}
ACTIVE_NORMATIVE_STATUS = {"draft", "proposed", "in_review", "accepted"}
TASK_STATUS = {"pending", "in_progress", "blocked", "done"}
BASE_FRONTMATTER = {"id", "title", "status", "owner", "updated", "normative"}
ACCEPTED_FRONTMATTER = {
    "approvers", "approvedAt", "reviewCommit", "reviewLink", "openFindings",
}
SUPERSEDED_FRONTMATTER = {"successor"}
DOCUMENT_KINDS = {"document", "adr", "spec", "module", "trace", "target", "release"}
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
    "governance/task-set.lock.json",
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
PRIMARY_ID_RE = re.compile(r"^[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+$")
RELEASE_ID_RE = re.compile(
    r"^REL-(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
    r"(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?$"
)
TRACE_ID_RE = re.compile(
    r"^(?:BV|GOAL|FR|NFR|OOS|INV|ADR|SRC|CLM|SPEC|CAP|MOD|TASK|TST|EV|TRACE|TARGET)-"
    r"[A-Z0-9]+(?:-[A-Z0-9]+)*$"
)
INLINE_LINK_RE = re.compile(r"(!?)\[[^\]]*\]\(([^)]+)\)")
MAX_JSON_NESTING = 256
MAX_LINK_TARGET_LENGTH = 2048
MAX_DOCUMENT_BYTES = 4 * 1024 * 1024
SOLANA_CPI_ADR_ID = "ADR-0028"
# Historical #114–#124 preactivation freeze (unchanged pins).
SOLANA_CPI_FROZEN_PAYLOADS = (
    (
        "docs/specs/solana-cpi-extension-v1.json",
        b"pf.extension-semantics.v1\x00",
    ),
    (
        "docs/specs/solana-cpi-callee-catalog-v1.json",
        b"pf.solana.callee-catalog.v1\x00",
    ),
    (
        "docs/specs/solana-cpi-profile-v1.json",
        b"pf.solana.cpi-profile.v1\x00",
    ),
)
# #125 active product payloads (separate domain freeze; extension digest unchanged).
SOLANA_CPI_ACTIVE_PAYLOADS = (
    (
        "docs/specs/solana-cpi-callee-catalog-active-v1.json",
        b"pf.solana.callee-catalog.v1\x00",
    ),
    (
        "docs/specs/solana-cpi-profile-active-v1.json",
        b"pf.solana.cpi-profile.v1\x00",
    ),
)
SOLANA_CPI_ACTIVE_PROFILE_DIGEST = (
    "b0f3f5bc7f3973daf176c308cc4ca310f8ad5b51ea33a33c9d1bd3e4d3e91b04"
)
SOLANA_CPI_ACTIVE_CATALOG_DIGEST = (
    "e2c2ebac5e690b99ad50fb7f8a5f6ecfdb8295bb43f3913229c2fd48d2820419"
)
SOLANA_CPI_EXTENSION_DOMAIN_DIGEST = (
    "df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020"
)
SOLANA_CPI_ACTIVE_PRODUCT_QNS = (
    "solana.system.transfer",
    "solana.system.createPdaAccount",
    "solana.token.transferChecked",
    "solana.token.transferCheckedPda",
    "solana.ata.createIdempotent",
)
SOLANA_CPI_COMPANION_TEST_ONLY_QNS = (
    "solana.companion.invoke",
    "solana.companion.fail",
    "solana.companion.invokeSigned",
)
SOLANA_CPI_CONTRACT_LEAN = "ProofForgeV2/Targets/Solana/CpiContractV1.lean"
SOLANA_CPI_ASSETS_MANIFEST = "supply-chain/solana-cpi-assets/v1/manifest.json"
# ADR-0029 Phase A: frozen L1 portable extension payload (chain-agnostic).
# Domain formula matches ADR-0028 extension semantics:
#   SHA-256("pf.extension-semantics.v1" || NUL || JCS bytes)
PF_ASSETS_EXTENSION_REL = "docs/specs/pf-assets-extension-v1.json"
PF_ASSETS_EXTENSION_DOMAIN = b"pf.extension-semantics.v1\x00"
PF_ASSETS_EXTENSION_RAW_SHA256 = (
    "fe12c5667bc4e30541fe16d201a02afbf0a00da0333777369e38ddb74a02d4fc"
)
PF_ASSETS_EXTENSION_DOMAIN_DIGEST = (
    "97dfde7f7df228230828db4273086224bc28a4bc88c2f25457eaf0aee22aeeed"
)
UNRESOLVED_MARKER_RE = re.compile(
    r"\b(?:TODO|TBD)\b|待补充|待决定|待锁",
    re.IGNORECASE,
)
STATUS_INDEX_TARGETS = (
    "docs/00-business-validation.md",
    "docs/01-prd.md",
    "docs/02-architecture.md",
    "docs/03-technical-spec.md",
    "docs/04-task-breakdown.md",
    "docs/05-test-spec.md",
    "docs/06-implementation-log.md",
    "docs/07-review-report.md",
)
FROZEN_A0_TASK_TEST_PAIRS = tuple(
    (f"TASK-A0-{index:02d}", f"TST-A0-{index:03d}")
    for index in range(1, 21)
)
FROZEN_A0_TASK_TO_TEST = dict(FROZEN_A0_TASK_TEST_PAIRS)
FROZEN_A0_TEST_TO_TASK = {
    test: task for task, test in FROZEN_A0_TASK_TEST_PAIRS
}
TASK_SET_LOCK_RELATIVE = "docs/governance/task-set.lock.json"
TASK_FREEZE_PACKAGES_RELATIVE = "docs/governance/task-freeze-packages"
GENESIS_SET_LOCK_RELATIVE = "docs/governance/genesis-set.lock.json"
GENESIS_ROOT_POLICY_RELATIVE = "docs/governance/genesis-root-policy.json"
D0_01_PURE_CONSUMER_ATTEST_RELATIVE = (
    "docs/governance/bootstrap-closure/TASK-D0-01.attest.json"
)
D0_02_PACKAGE_BOUNDARY_ATTEST_RELATIVE = (
    "docs/governance/bootstrap-closure/TASK-D0-02.attest.json"
)
D0_03_DEVELOPMENT_TRIAD_ATTEST_RELATIVE = (
    "docs/governance/bootstrap-closure/TASK-D0-03.attest.json"
)
D0_05_SBOM_INVENTORY_ATTEST_RELATIVE = (
    "docs/governance/bootstrap-closure/TASK-D0-05.attest.json"
)
D0_06_COMMON_PRIMITIVES_ATTEST_RELATIVE = (
    "docs/governance/bootstrap-closure/TASK-D0-06.attest.json"
)
D0_08_SBOM_CLOSURE_ATTEST_RELATIVE = (
    "docs/governance/bootstrap-closure/TASK-D0-08.attest.json"
)
D0_09_LINUX_HOST_ATTEST_RELATIVE = (
    "docs/governance/bootstrap-closure/TASK-D0-09.attest.json"
)
D0_10_TASK_QUALIFICATION_ATTEST_RELATIVE = (
    "docs/governance/bootstrap-closure/TASK-D0-10.attest.json"
)
D0_10_TASK_QUALIFICATION_SUBPROFILE = "TST-DOC-001/task-qualification-v1"
D0_04_BOOTSTRAP_ACTIVATION_ATTEST_RELATIVE = (
    "docs/governance/bootstrap-closure/TASK-D0-04.attest.json"
)
D0_04_BOOTSTRAP_ACTIVATION_BUNDLE_RELATIVE = (
    "docs/governance/bootstrap-closure/TASK-D0-04"
)
D0_04_BOOTSTRAP_TASK_IDS = tuple(f"TASK-D0-{index:02d}" for index in range(1, 7))
D0_04_TOPOLOGICAL_TASK_IDS = (
    "TASK-D0-01",
    "TASK-D0-02",
    "TASK-D0-03",
    "TASK-D0-05",
    "TASK-D0-06",
    "TASK-D0-04",
)
D0_07_FIXTURE_ACCEPTANCE_ATTEST_RELATIVE = (
    "docs/governance/bootstrap-closure/TASK-D0-07.attest.json"
)
D0_07_GENESIS_REPLAY_REPORT_RELATIVE = (
    "docs/governance/bootstrap-closure/TASK-D0-07-genesis-replay-report.json"
)
D0_07_GENESIS_TST_IDS = (
    "TST-DOC-001",
    "TST-ISO-001",
    "TST-EVIDENCE-001",
    "TST-HOST-001",
    "TST-TOOL-001",
    "TST-SBOM-001",
    "TST-COMMON-001",
    "TST-HOST-002",
    "TST-SBOM-002",
)
D0_07_GENESIS_REPORT_SCHEMA = "proof-forge.genesis-replay-report.v1"
MILESTONE_TASK_RE = re.compile(r"^TASK-(A0|D[0-9]+)-[A-Z0-9]+(?:-[A-Z0-9]+)*$")
TASK_FREEZE_PACKAGE_NAME_RE = re.compile(
    r"^TASK-[A-Z0-9]+(?:-[A-Z0-9]+)*\.json$"
)


def is_frozen_a0_task(identifier: str) -> bool:
    return identifier in FROZEN_A0_TASK_TO_TEST


def is_frozen_a0_test(identifier: str) -> bool:
    return identifier in FROZEN_A0_TEST_TO_TASK


def milestone_for_task(identifier: str) -> str | None:
    match = MILESTONE_TASK_RE.fullmatch(identifier)
    return match.group(1) if match else None


class DocsCheckError(Exception):
    def __init__(self, code: str, path: str, detail: str):
        super().__init__(detail)
        self.code = code
        self.path = path
        self.detail = detail

    def render(self) -> str:
        return f"{self.code} {self.path}: {self.detail}"


class DuplicateJsonKey(ValueError):
    def __init__(self, key: str):
        super().__init__(key)
        self.key = key


class NonStandardJsonConstant(ValueError):
    pass


@dataclass(frozen=True)
class Document:
    path: Path
    relative: str
    text: str
    meta: dict[str, str]


@dataclass(frozen=True)
class Definition:
    identifier: str
    relative: str
    line: int
    kind: str


@dataclass(frozen=True)
class TableRow:
    relative: str
    line: int
    headers: tuple[str, ...]
    cells: tuple[str, ...]

    def value(self, names: set[str]) -> str | None:
        for index, header in enumerate(self.headers):
            if header in names and index < len(self.cells):
                return self.cells[index]
        return None


@dataclass(frozen=True)
class TaskRecord:
    identifier: str
    dependencies: tuple[str, ...]
    prerequisites: tuple[tuple[str, str], ...]
    tests: tuple[str, ...]
    evidence: tuple[str, ...]
    status: str
    relative: str
    line: int


@dataclass(frozen=True)
class EvidenceRecord:
    identifier: str
    task: str | None
    tests: tuple[str, ...]
    grade: str
    result: str
    relative: str
    line: int


@dataclass(frozen=True)
class OrderedDiagnostic:
    relative: str
    line: int
    column: int
    identifier: str
    error: DocsCheckError

    def key(self) -> tuple[str, int, int, str, str]:
        return (self.relative, self.line, self.column, self.identifier, self.error.code)


def genesis_set_lock_valid(root: Path) -> bool:
    path = root / GENESIS_SET_LOCK_RELATIVE
    try:
        ensure_repository_path(root, path, GENESIS_SET_LOCK_RELATIVE)
        payload = load_json(root, path)
    except DocsCheckError:
        return False
    expected_description = (
        "Exact genesis task set for GOV-GENESIS-001. Silent addition requires "
        "Architecture+Quality approval and a lock update in the same change."
    )
    return (
        isinstance(payload, dict)
        and set(payload) == {"schemaVersion", "description", "genesisTasks"}
        and type(payload.get("schemaVersion")) is int
        and payload.get("schemaVersion") == 1
        and payload.get("description") == expected_description
        and payload.get("genesisTasks") == [
            "TASK-D0-01",
            "TASK-D0-02",
            "TASK-D0-03",
            "TASK-D0-05",
            "TASK-D0-06",
        ]
    )


def genesis_root_policy_valid(root: Path) -> bool:
    """Validate the exact public-key-only pre-cutover root policy."""
    policy_path = root / GENESIS_ROOT_POLICY_RELATIVE
    try:
        ensure_repository_path(root, policy_path, GENESIS_ROOT_POLICY_RELATIVE)
        if not policy_path.is_file() or policy_path.is_symlink():
            return False
        checker_path = Path(__file__).resolve(strict=True)
        tool_path = checker_path.with_name("genesis_root_policy.py")
        if tool_path.is_symlink() or not tool_path.is_file():
            return False
        exact_tool_path = tool_path.resolve(strict=True)
        if exact_tool_path != tool_path:
            return False
        spec = importlib.util.spec_from_file_location(
            "proof_forge_genesis_root_policy_for_docs_check",
            exact_tool_path,
        )
        if spec is None or spec.loader is None or spec.origin is None:
            return False
        if Path(spec.origin).resolve(strict=True) != exact_tool_path:
            return False
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        reader = module.__dict__.get("read_genesis_root_policy")
        if not callable(reader):
            return False
        data = reader(policy_path)
        return type(data) is bytes
    except Exception:
        return False


def genesis_authority_state(
        root: Path, by_relative: dict[str, Document]) -> tuple[bool, str]:
    """Resolve the exact human authority required by GOV-GENESIS-001."""
    required = (
        ("docs/governance/genesis-authority.md", "GOV-GENESIS-001"),
        ("docs/governance/maintainers.md", "GOV-MAINTAINERS-001"),
        ("docs/governance/authority.md", "GOV-AUTH-001"),
        ("docs/governance/change-control.md", "GOV-CHANGE-001"),
        ("docs/governance/task-freeze.md", "GOV-TASK-FREEZE-001"),
    )
    approval_action: tuple[str, str, str, str, str] | None = None
    for relative_path, expected_id in required:
        document = by_relative.get(relative_path)
        if (document is None
                or document.meta.get("id") != expected_id
                or document.meta.get("status") != "accepted"
                or document.meta.get("normative") != "true"
                or document.meta.get("approvers")
                != "architecture-owner, davirain, quality-owner"):
            return False, expected_id
        current_action = tuple(
            document.meta.get(field, "")
            for field in (
                "approvers", "approvedAt", "reviewCommit", "reviewLink",
                "openFindings",
            )
        )
        if approval_action is None:
            approval_action = current_action
        elif current_action != approval_action:
            return False, expected_id
    if not genesis_set_lock_valid(root):
        return False, GENESIS_SET_LOCK_RELATIVE
    if not genesis_root_policy_valid(root):
        return False, GENESIS_ROOT_POLICY_RELATIVE
    return True, ""


def raise_error(code: str, path: str, detail: str) -> None:
    raise DocsCheckError(code, path, detail)


def raise_first(diagnostics: list[OrderedDiagnostic]) -> None:
    if diagnostics:
        raise min(diagnostics, key=OrderedDiagnostic.key).error


def source_position(text: str, offset: int) -> tuple[int, int]:
    line = text.count("\n", 0, offset) + 1
    line_start = text.rfind("\n", 0, offset) + 1
    return line, offset - line_start + 1


def frontmatter_field_line(document: Document, field: str) -> int:
    for line_number, line in enumerate(document.text.splitlines(), start=1):
        if line.startswith(f"{field}:"):
            return line_number
        if line_number > 1 and line == "---":
            break
    return 1


def parse_exact_date(value: str, *, code: str, path: str, field: str) -> None:
    if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", value):
        raise_error(code, path, f"{field} {value} must be YYYY-MM-DD")
    try:
        date.fromisoformat(value)
    except ValueError:
        raise_error(code, path, f"{field} {value} must be YYYY-MM-DD")


def relative(root: Path, path: Path) -> str:
    return path.relative_to(root).as_posix()


def validate_approval(rel: str, result: dict[str, str], text: str, *, check_todo: bool) -> None:
    missing_approval = ACCEPTED_FRONTMATTER - result.keys()
    if missing_approval:
        raise_error("PF-DOC-APPROVAL", rel, f"missing fields {sorted(missing_approval)}")
    parse_exact_date(result["approvedAt"], code="PF-DOC-APPROVAL", path=rel,
                     field="approvedAt")
    if not re.fullmatch(r"[0-9a-f]{40}", result["reviewCommit"]):
        raise_error("PF-DOC-APPROVAL", rel, "reviewCommit must be a full lowercase SHA-1")
    if not result["reviewLink"].lower().startswith("https://"):
        raise_error("PF-DOC-APPROVAL", rel, "reviewLink must use https")
    approvers = result["approvers"]
    approver_ids = approvers.split(", ")
    safe_id = re.compile(
        r"[A-Za-z0-9](?:[A-Za-z0-9._:+-]{0,254}[A-Za-z0-9])?")
    if (not approvers or ", ".join(approver_ids) != approvers
            or any(safe_id.fullmatch(identifier) is None for identifier in approver_ids)):
        raise_error(
            "PF-DOC-APPROVAL", rel,
            "approvers must be exact ', '-separated ASCII safe-id values")
    if len(set(approver_ids)) != len(approver_ids):
        raise_error("PF-DOC-APPROVAL", rel, "approvers must be unique")
    if approver_ids != sorted(approver_ids, key=lambda item: item.encode("ascii")):
        raise_error("PF-DOC-APPROVAL", rel, "approvers must be in ascending ASCII order")
    if result["openFindings"] != "none":
        raise_error("PF-DOC-APPROVAL", rel, "openFindings must be none")
    if check_todo and UNRESOLVED_MARKER_RE.search(text):
        raise_error("PF-DOC-ACCEPTED-TODO", rel, "accepted document has unresolved marker")


def parse_frontmatter(root: Path, path: Path, text: str) -> dict[str, str]:
    rel = relative(root, path)
    if not text.startswith("---\n"):
        raise_error("PF-DOC-FRONTMATTER", rel, "missing opening frontmatter delimiter")
    end = text.find("\n---\n", 4)
    if end < 0:
        raise_error("PF-DOC-FRONTMATTER", rel, "unterminated frontmatter")
    result: dict[str, str] = {}
    for offset, line in enumerate(text[4:end].splitlines(), start=2):
        if ":" not in line:
            raise_error("PF-DOC-FRONTMATTER", rel, f"line {offset} is not key: value")
        key, value = line.split(":", 1)
        key = key.strip()
        value = value.strip().strip("'\"")
        if not key or not value:
            raise_error("PF-DOC-FRONTMATTER", rel, f"empty key/value at line {offset}")
        if key in result:
            raise_error("PF-DOC-FRONTMATTER", rel, f"duplicate frontmatter key {key}")
        result[key] = value
    missing = BASE_FRONTMATTER - result.keys()
    if missing:
        raise_error("PF-DOC-FRONTMATTER", rel, f"missing fields {sorted(missing)}")
    known_fields = BASE_FRONTMATTER | ACCEPTED_FRONTMATTER | SUPERSEDED_FRONTMATTER
    unknown = result.keys() - known_fields
    if unknown:
        raise_error("PF-DOC-FRONTMATTER", rel, f"unknown fields {sorted(unknown)}")
    primary_id = result["id"]
    valid_primary = (RELEASE_ID_RE.fullmatch(primary_id) if primary_id.startswith("REL-")
                     else PRIMARY_ID_RE.fullmatch(primary_id))
    if not valid_primary:
        raise_error("PF-DOC-FRONTMATTER", rel, f"invalid primary id {result['id']}")
    parse_exact_date(result["updated"], code="PF-DOC-FRONTMATTER", path=rel,
                     field="updated")
    if result["normative"] not in {"true", "false"}:
        raise_error("PF-DOC-FRONTMATTER", rel, "normative must be true or false")
    return result


def validate_document_lifecycle(document: Document, by_id: dict[str, Document]) -> None:
    result = document.meta
    status = result["status"]
    if status not in ALLOWED_STATUS:
        raise_error("PF-DOC-STATUS", document.relative, f"invalid lifecycle status {status}")
    allowed_fields = set(BASE_FRONTMATTER)
    if status == "accepted":
        allowed_fields.update(ACCEPTED_FRONTMATTER)
    elif status == "superseded":
        allowed_fields.update(SUPERSEDED_FRONTMATTER | ACCEPTED_FRONTMATTER)
    conditional_unknown = result.keys() - allowed_fields
    if conditional_unknown:
        raise_error("PF-DOC-FRONTMATTER", document.relative,
                    f"fields not allowed for {status}: {sorted(conditional_unknown)}")
    if status == "accepted":
        validate_approval(document.relative, result, document.text, check_todo=False)
        if RELEASE_ID_RE.fullmatch(result["id"]):
            raise_error("PF-DOC-RELEASE-EVIDENCE", document.relative,
                        f"{result['id']} cannot be accepted before the formal evidence-set binder")
    elif status == "superseded":
        if "successor" not in result:
            raise_error("PF-DOC-SUCCESSOR", document.relative,
                        "superseded document lacks successor")
        retained_approval = ACCEPTED_FRONTMATTER & result.keys()
        if retained_approval:
            validate_approval(document.relative, result, document.text, check_todo=False)
        if result["successor"] not in by_id:
            raise_error("PF-DOC-SUCCESSOR", document.relative,
                        f"unknown successor {result['successor']}")


def reject_duplicate_json_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateJsonKey(key)
        result[key] = value
    return result


def reject_nonstandard_json_constant(value: str) -> None:
    raise NonStandardJsonConstant(value)


def validate_json_nesting(rel: str, text: str) -> None:
    depth = 0
    in_string = False
    escaped = False
    for character in text:
        if in_string:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                in_string = False
            continue
        if character == '"':
            in_string = True
        elif character in "[{":
            depth += 1
            if depth > MAX_JSON_NESTING:
                raise_error("PF-DOC-JSON", rel,
                            f"JSON nesting exceeds {MAX_JSON_NESTING}")
        elif character in "]}":
            depth = max(0, depth - 1)


def _same_inode(left: os.stat_result, right: os.stat_result) -> bool:
    return left.st_dev == right.st_dev and left.st_ino == right.st_ino


def read_repository_regular_bytes(
        root: Path,
        path: Path,
        display: str,
        *,
        maximum: int = MAX_DOCUMENT_BYTES,
) -> bytes:
    """Read one stable, bounded, single-link regular file below root."""
    ensure_repository_path(root, path, display)
    try:
        parts = path.relative_to(root).parts
    except ValueError:
        raise_error("PF-DOC-PATH", display, "path is outside repository root")
    if not parts or maximum < 0:
        raise_error("PF-DOC-PATH", display, "path must name one bounded file")
    if not hasattr(os, "O_NOFOLLOW") or not hasattr(os, "O_DIRECTORY"):
        raise_error("PF-DOC-PATH", display, "host lacks no-follow file opens")

    directory_flags = (
        os.O_RDONLY
        | os.O_DIRECTORY
        | getattr(os, "O_CLOEXEC", 0)
        | os.O_NOFOLLOW
    )
    file_flags = (
        os.O_RDONLY
        | getattr(os, "O_CLOEXEC", 0)
        | getattr(os, "O_NONBLOCK", 0)
        | os.O_NOFOLLOW
    )
    directory_fd: int | None = None
    file_fd: int | None = None
    try:
        directory_fd = os.open(root, directory_flags)
        for component in parts[:-1]:
            next_fd: int | None = None
            try:
                next_fd = os.open(
                    component, directory_flags, dir_fd=directory_fd)
                opened = os.fstat(next_fd)
                named = os.stat(
                    component,
                    dir_fd=directory_fd,
                    follow_symlinks=False,
                )
            except Exception:
                if next_fd is not None:
                    os.close(next_fd)
                raise
            assert next_fd is not None
            if not stat.S_ISDIR(opened.st_mode) or not _same_inode(opened, named):
                os.close(next_fd)
                raise_error(
                    "PF-DOC-PATH", display,
                    f"directory component {component} changed during open")
            os.close(directory_fd)
            directory_fd = next_fd

        file_fd = os.open(parts[-1], file_flags, dir_fd=directory_fd)
        before = os.fstat(file_fd)
        named_before = os.stat(
            parts[-1],
            dir_fd=directory_fd,
            follow_symlinks=False,
        )
        stable_fields = (
            "st_dev", "st_ino", "st_mode", "st_nlink", "st_size",
            "st_mtime_ns", "st_ctime_ns",
        )
        if (
            not stat.S_ISREG(before.st_mode)
            or before.st_nlink != 1
            or before.st_size < 0
            or before.st_size > maximum
            or any(
                getattr(before, field) != getattr(named_before, field)
                for field in stable_fields
            )
        ):
            raise_error(
                "PF-DOC-PATH", display,
                f"must be one stable single-link regular file <= {maximum} bytes")

        chunks: list[bytes] = []
        remaining = maximum + 1
        while remaining > 0:
            chunk = os.read(file_fd, min(remaining, 128 * 1024))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        data = b"".join(chunks)
        after = os.fstat(file_fd)
        named_after = os.stat(
            parts[-1],
            dir_fd=directory_fd,
            follow_symlinks=False,
        )
        if (
            len(data) > maximum
            or len(data) != before.st_size
            or any(
                getattr(before, field) != getattr(after, field)
                for field in stable_fields
            )
            or any(
                getattr(after, field) != getattr(named_after, field)
                for field in stable_fields
            )
        ):
            raise_error("PF-DOC-PATH", display, "file changed during bounded read")
        return data
    except DocsCheckError:
        raise
    except OSError as error:
        raise_error("PF-DOC-PATH", display, f"cannot open stable file: {error}")
    finally:
        if file_fd is not None:
            os.close(file_fd)
        if directory_fd is not None:
            os.close(directory_fd)


def read_repository_text(
        root: Path,
        path: Path,
        display: str,
        *,
        encoding_code: str = "PF-DOC-ENCODING",
) -> str:
    data = read_repository_regular_bytes(root, path, display)
    try:
        return data.decode("utf-8", errors="strict")
    except UnicodeError as error:
        raise_error(encoding_code, display, str(error))


def load_json(root: Path, path: Path) -> Any:
    rel = relative(root, path)
    try:
        text = read_repository_regular_bytes(root, path, rel).decode(
            "utf-8", errors="strict")
        validate_json_nesting(rel, text)
        return json.loads(
            text,
            object_pairs_hook=reject_duplicate_json_keys,
            parse_constant=reject_nonstandard_json_constant,
        )
    except DuplicateJsonKey as error:
        raise_error("PF-DOC-JSON-DUPLICATE", rel, f"duplicate JSON key {error.key}")
    except (OSError, UnicodeError, json.JSONDecodeError, NonStandardJsonConstant,
            RecursionError, MemoryError, OverflowError) as error:
        raise_error("PF-DOC-JSON", rel, str(error))


def _validate_sol_cpi_jcs_value(value: Any, path: str) -> None:
    """Restrict frozen contract payloads to deterministic I-JSON scalars."""
    if value is None or type(value) is bool or type(value) is str:
        return
    if type(value) is int:
        if value < -(2**53 - 1) or value > 2**53 - 1:
            raise_error(
                "PF-DOC-SOLANA-CPI-CONTRACT", path,
                "integer is outside the interoperable JCS range")
        return
    if type(value) is list:
        for item in value:
            _validate_sol_cpi_jcs_value(item, path)
        return
    if type(value) is dict:
        for key, item in value.items():
            if type(key) is not str:
                raise_error(
                    "PF-DOC-SOLANA-CPI-CONTRACT", path,
                    "object key is not a string")
            _validate_sol_cpi_jcs_value(item, path)
        return
    raise_error(
        "PF-DOC-SOLANA-CPI-CONTRACT", path,
        f"non-I-JSON scalar {type(value).__name__} is not permitted")


def _sol_cpi_canonical_jcs(value: Any, path: str) -> bytes:
    _validate_sol_cpi_jcs_value(value, path)
    try:
        return json.dumps(
            value,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
            allow_nan=False,
        ).encode("utf-8", errors="strict")
    except (UnicodeError, ValueError, TypeError, RecursionError, MemoryError) as error:
        raise_error("PF-DOC-SOLANA-CPI-CONTRACT", path, str(error))


def _expect_sol_cpi(condition: bool, path: str, detail: str) -> None:
    if not condition:
        raise_error("PF-DOC-SOLANA-CPI-CONTRACT", path, detail)


def _expect_pf_assets(condition: bool, path: str, detail: str) -> None:
    if not condition:
        raise_error("PF-DOC-PF-ASSETS-CONTRACT", path, detail)


def validate_pf_assets_extension_contract(
        root: Path,
        json_values: dict[str, Any],
) -> None:
    """Recompute raw SHA-256 + domain digest for ADR-0029 pf.assets payload.

    Mirrors the SOLANA_CPI frozen-payload recompute pattern: exact canonical JCS
    (UTF-8, no BOM, no trailing newline, object keys UTF-8 ascending, I-JSON
    scalars only) and domain SHA-256("pf.extension-semantics.v1" || NUL || JCS).
    Expected digests are package-pinned constants (ADR body update is separate).
    """
    relative_path = PF_ASSETS_EXTENSION_REL
    value = json_values.get(relative_path)
    _expect_pf_assets(value is not None, relative_path, "frozen payload is missing")
    raw = read_repository_regular_bytes(root, root / relative_path, relative_path)
    # Reuse the same JCS encoder discipline as SOLANA_CPI payloads; route I-JSON
    # / encode failures through the pf.assets error code via local re-encode.
    try:
        # Validate I-JSON shape first (bool/str/int/list/dict/None only).
        def _ijson(node: Any) -> None:
            if node is None or type(node) is bool or type(node) is str:
                return
            if type(node) is int:
                if node < -(2**53 - 1) or node > 2**53 - 1:
                    raise ValueError("integer is outside the interoperable JCS range")
                return
            if type(node) is list:
                for item in node:
                    _ijson(item)
                return
            if type(node) is dict:
                for key, item in node.items():
                    if type(key) is not str:
                        raise ValueError("object key is not a string")
                    _ijson(item)
                return
            raise ValueError(
                f"non-I-JSON scalar {type(node).__name__} is not permitted")

        _ijson(value)
        canonical = json.dumps(
            value,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
            allow_nan=False,
        ).encode("utf-8", errors="strict")
    except (UnicodeError, ValueError, TypeError, RecursionError, MemoryError) as error:
        raise_error("PF-DOC-PF-ASSETS-CONTRACT", relative_path, str(error))
    _expect_pf_assets(
        raw == canonical, relative_path,
        "payload is not exact canonical JCS or has a BOM/trailing newline")
    raw_digest = hashlib.sha256(raw).hexdigest()
    domain_digest = hashlib.sha256(PF_ASSETS_EXTENSION_DOMAIN + raw).hexdigest()
    _expect_pf_assets(
        raw_digest == PF_ASSETS_EXTENSION_RAW_SHA256, relative_path,
        f"raw SHA-256 {raw_digest} does not match pinned constant")
    _expect_pf_assets(
        domain_digest == PF_ASSETS_EXTENSION_DOMAIN_DIGEST, relative_path,
        f"domain digest {domain_digest} does not match pinned constant")

    _expect_pf_assets(type(value) is dict, relative_path, "root must be an object")
    _expect_pf_assets(
        value.get("schema") == "proof-forge.pf-assets-extension.v1"
        and value.get("extensionId") == "pf.assets"
        and value.get("version") == "1.0.0",
        relative_path, "extension root identity is not exact")
    requirement = value.get("requirementContract")
    _expect_pf_assets(
        type(requirement) is dict
        and requirement.get("id") == "extension.pf-assets"
        and requirement.get("version") == "1.0.0"
        and requirement.get("predicates") == []
        and requirement.get("digestDomain") == "pf.extension-semantics.v1",
        relative_path, "extension requirement contract is not exact")
    apis = value.get("apis")
    _expect_pf_assets(
        type(apis) is list and len(apis) == 5, relative_path,
        "apis must be exactly five portable L1 rows")
    expected_qns = [
        "pf.assets.native.deposit",
        "pf.assets.native.transfer",
        "pf.assets.native.transferAsync",
        "pf.assets.token.transfer",
        "pf.assets.token.transferAsync",
    ]
    for index, api in enumerate(apis):
        _expect_pf_assets(type(api) is dict, relative_path, f"api[{index}] must be an object")
        _expect_pf_assets(
            api.get("qn") == expected_qns[index] and api.get("result") == "Unit",
            relative_path, f"api[{index}] qn/result is not exact")
        for arg in api.get("args") or []:
            _expect_pf_assets(
                type(arg) is dict
                and arg.get("source") == "typed-expression"
                and arg.get("type") in ("UInt64", "Principal"),
                relative_path, f"api[{index}] arg source/type is not portable")
    restrictions = value.get("sourceRestrictions")
    _expect_pf_assets(
        type(restrictions) is dict
        and restrictions.get("typedCallReturn") is False
        and restrictions.get("schedule") is False
        and restrictions.get("targetImportsInFrontendOrSemantic") is False,
        relative_path, "sourceRestrictions are not exact")


def _sol_cpi_adr_digest_pair(
        adr: Document, filename: str) -> tuple[str, str]:
    pattern = re.compile(
        rf"^\|\s*\[[^]]+\]\([^)]*{re.escape(filename)}\)\s*\|\s*"
        rf"`([0-9a-f]{{64}})`\s*\|\s*`sha256:([0-9a-f]{{64}})`\s*\|$",
        re.MULTILINE,
    )
    matches = pattern.findall(adr.text)
    _expect_sol_cpi(
        len(matches) == 1, adr.relative,
        f"expected exactly one digest-table row for {filename}")
    return matches[0]



def _lean_string_def(text: str, name: str) -> str | None:
    """Extract a single-line or next-line Lean `def name : String := \"...\"`."""
    m = re.search(
        rf"^def\s+{re.escape(name)}\s*:\s*String\s*:=\s*\n?\s*\"([^\"]+)\"",
        text,
        re.MULTILINE,
    )
    return m.group(1) if m else None


def _lean_string_array_def(text: str, name: str) -> list[str] | None:
    """Extract `def name : Array String := #[ \"a\", ... ]` string elements."""
    m = re.search(
        rf"^def\s+{re.escape(name)}\s*:\s*Array\s+String\s*:=\s*#\[(.*?)\]",
        text,
        re.MULTILINE | re.DOTALL,
    )
    if m is None:
        return None
    return re.findall(r"\"([^\"]+)\"", m.group(1))


def validate_solana_cpi_active_contract(root: Path, by_id: dict[str, Document]) -> None:
    """Freeze #125 active profile/catalog domain digests against ADR + Lean constants.

    Triangle: active JCS domain digest == ADR digest-table row == CpiContractV1
    `activeProfileDigestV1` / `activeCatalogDigestV1`. Extension digest stays
    historical df7d…. Historical #124 profile/catalog 0b306/41ace remain in
    SOLANA_CPI_FROZEN_PAYLOADS and are not replaced here.
    """
    adr = by_id.get(SOLANA_CPI_ADR_ID)
    _expect_sol_cpi(adr is not None, "docs/adr", "ADR-0028 is missing")
    assert adr is not None

    active_domain: dict[str, str] = {}
    active_payloads: dict[str, Any] = {}
    for relative_path, domain in SOLANA_CPI_ACTIVE_PAYLOADS:
        path = root / relative_path
        ensure_repository_path(root, path, relative_path)
        if not path.is_file():
            raise_error(
                "PF-DOC-SOLANA-CPI-CONTRACT", relative_path,
                "active payload is missing")
        raw = read_repository_regular_bytes(root, path, relative_path)
        value = load_json(root, path)
        canonical = _sol_cpi_canonical_jcs(value, relative_path)
        _expect_sol_cpi(
            raw == canonical, relative_path,
            "active payload is not exact canonical JCS or has a BOM/trailing newline")
        raw_digest = hashlib.sha256(raw).hexdigest()
        domain_digest = hashlib.sha256(domain + raw).hexdigest()
        expected_raw, expected_domain = _sol_cpi_adr_digest_pair(
            adr, Path(relative_path).name)
        _expect_sol_cpi(
            raw_digest == expected_raw, relative_path,
            f"active raw SHA-256 {raw_digest} does not match ADR-0028")
        _expect_sol_cpi(
            domain_digest == expected_domain, relative_path,
            f"active domain digest {domain_digest} does not match ADR-0028")
        active_domain[relative_path] = domain_digest
        active_payloads[relative_path] = value

    profile_path = "docs/specs/solana-cpi-profile-active-v1.json"
    catalog_path = "docs/specs/solana-cpi-callee-catalog-active-v1.json"
    profile = active_payloads[profile_path]
    catalog = active_payloads[catalog_path]
    profile_domain = active_domain[profile_path]
    catalog_domain = active_domain[catalog_path]

    _expect_sol_cpi(
        profile_domain == SOLANA_CPI_ACTIVE_PROFILE_DIGEST, profile_path,
        "active profile domain digest constant mismatch")
    _expect_sol_cpi(
        catalog_domain == SOLANA_CPI_ACTIVE_CATALOG_DIGEST, catalog_path,
        "active catalog domain digest constant mismatch")

    lean_rel = SOLANA_CPI_CONTRACT_LEAN
    lean_path = root / lean_rel
    ensure_repository_path(root, lean_path, lean_rel)
    lean_text = read_repository_text(
        root, lean_path, lean_rel, encoding_code="PF-DOC-SOLANA-CPI-CONTRACT")
    lean_profile = _lean_string_def(lean_text, "activeProfileDigestV1")
    lean_catalog = _lean_string_def(lean_text, "activeCatalogDigestV1")
    lean_impl = _lean_string_def(lean_text, "activeProfileImplementationStateV1")
    lean_catalog_ver = _lean_string_def(lean_text, "activeCatalogVersionV1")
    lean_product_qns = _lean_string_array_def(lean_text, "activeProductApiQnsV1")
    _expect_sol_cpi(
        lean_profile == f"sha256:{SOLANA_CPI_ACTIVE_PROFILE_DIGEST}",
        lean_rel, "activeProfileDigestV1 must triangle with active profile domain digest")
    _expect_sol_cpi(
        lean_catalog == f"sha256:{SOLANA_CPI_ACTIVE_CATALOG_DIGEST}",
        lean_rel, "activeCatalogDigestV1 must triangle with active catalog domain digest")
    _expect_sol_cpi(
        lean_impl == "product-exact-synchronous-call-active-v1",
        lean_rel, "activeProfileImplementationStateV1 must be product-exact-synchronous-call-active-v1")
    _expect_sol_cpi(
        lean_catalog_ver == "1.1.0",
        lean_rel, "activeCatalogVersionV1 must be 1.1.0")
    _expect_sol_cpi(
        lean_product_qns == list(SOLANA_CPI_ACTIVE_PRODUCT_QNS),
        lean_rel, "activeProductApiQnsV1 must be the five approved product APIs")

    # Active profile product state / irSchema / catalog binding.
    _expect_sol_cpi(type(profile) is dict, profile_path, "active profile root must be object")
    _expect_sol_cpi(
        profile.get("schema") == "proof-forge.solana.cpi-profile.v1"
        and profile.get("profileId") == "solana-sbpf-cpi-elf-v1"
        and profile.get("irSchema") == "proof-forge.solana.cpi-product-ir.v1"
        and profile.get("planSchema") == "proof-forge.solana.cpi-plan.v1"
        and profile.get("implementationState")
        == "product-exact-synchronous-call-active-v1"
        and profile.get("scheduleSupported") is False
        and profile.get("synchronousCallSupportRule")
        == "advertise-exact-effect.synchronous-call-on-this-profile-only-excluding-async",
        profile_path, "active profile product state / irSchema is not exact")
    profile_ext = profile.get("extensionRequirement")
    _expect_sol_cpi(
        type(profile_ext) is dict
        and profile_ext.get("digest")
        == f"sha256:{SOLANA_CPI_EXTENSION_DOMAIN_DIGEST}"
        and profile_ext.get("id") == "extension.solana-cpi-accounts"
        and profile_ext.get("version") == "1.0.0"
        and profile_ext.get("predicates") == [],
        profile_path, "active profile must bind unchanged extension digest df7d…")
    profile_catalog = profile.get("calleeCatalog")
    _expect_sol_cpi(
        type(profile_catalog) is dict
        and profile_catalog.get("digest")
        == f"sha256:{SOLANA_CPI_ACTIVE_CATALOG_DIGEST}"
        and profile_catalog.get("version") == "1.1.0"
        and profile_catalog.get("schema") == "proof-forge.solana.callee-catalog.v1"
        and profile_catalog.get("digestDomain") == "pf.solana.callee-catalog.v1",
        profile_path, "active profile must bind active catalog domain digest e2c2…")
    _expect_sol_cpi(
        profile.get("runtimeCompatibility") == catalog.get("runtime"),
        profile_path, "active profile runtimeCompatibility differs from active catalog runtime")
    _expect_sol_cpi(
        catalog.get("version") == "1.1.0"
        and catalog.get("schema") == "proof-forge.solana.callee-catalog.v1",
        catalog_path, "active catalog version/schema is not exact")

    packages = catalog.get("packages")
    _expect_sol_cpi(type(packages) is list, catalog_path, "active packages must be an array")
    package_by_id: dict[str, dict[str, Any]] = {}
    for package in packages:
        _expect_sol_cpi(type(package) is dict, catalog_path, "package row must be object")
        package_id = package.get("packageId")
        _expect_sol_cpi(
            type(package_id) is str and package_id not in package_by_id,
            catalog_path, "active package IDs must be unique strings")
        package_by_id[package_id] = package
    _expect_sol_cpi(
        set(package_by_id) == {
            "companion-v1", "system-v1", "token-classic-v1", "ata-classic-v1"
        },
        catalog_path, "active callee package set is not the frozen four-package set")

    companion = package_by_id["companion-v1"]
    _expect_sol_cpi(
        companion.get("admittedForMaterialization") is False
        and isinstance(companion.get("artifactBinding"), dict)
        and companion["artifactBinding"].get("kind") == "absent",
        catalog_path, "companion-v1 must remain test-only / not product-admitted")
    system = package_by_id["system-v1"]
    system_binding = system.get("artifactBinding")
    _expect_sol_cpi(
        system.get("admittedForMaterialization") is True
        and type(system_binding) is dict
        and system_binding.get("kind") == "runtime-native"
        and system_binding.get("agaveCommit")
        == "2a165e7a90af75c76426d1e031ed0284211d5d1e",
        catalog_path, "system-v1 must be admitted runtime-native with Agave commit pin")

    assets_rel = SOLANA_CPI_ASSETS_MANIFEST
    assets_path = root / assets_rel
    ensure_repository_path(root, assets_path, assets_rel)
    assets_manifest = load_json(root, assets_path)
    _expect_sol_cpi(
        type(assets_manifest) is dict
        and assets_manifest.get("schema") == "proof-forge.solana.cpi-assets.v1"
        and assets_manifest.get("catalogVersion") == "1.1.0",
        assets_rel, "package-owned CPI assets manifest schema/version mismatch")
    asset_rows = assets_manifest.get("assets")
    _expect_sol_cpi(
        type(asset_rows) is list and len(asset_rows) == 2,
        assets_rel, "assets manifest must list exactly Token+ATA package-owned ELFs")
    assets_by_id = {
        row["packageId"]: row
        for row in asset_rows
        if isinstance(row, dict) and type(row.get("packageId")) is str
    }
    _expect_sol_cpi(
        set(assets_by_id) == {"token-classic-v1", "ata-classic-v1"},
        assets_rel, "assets manifest package IDs must be token-classic-v1 and ata-classic-v1")

    # Full package-owned provenance freeze: assets manifest row ≡ active catalog
    # artifactBinding for every field in the closed tuple (not path/size/sha only).
    provenance_keys = (
        "relativePath",
        "size",
        "sha256",
        "buildRecipeDigest",
        "tagObject",
        "peeledCommit",
        "sourceRepo",
        "sourceTag",
    )
    expected_package_owned = {
        "token-classic-v1": {
            "kind": "loader-v3-elf",
            "relativePath": "supply-chain/solana-cpi-assets/v1/token_classic_v1.so",
            "size": 94960,
            "sha256": (
                "a19be3a2d4778533652da23b8fe31c4a341802f8e8c0c7b941b88581fc92d9d9"
            ),
            "buildRecipeDigest": (
                "4af75b0a74ba14daa90a2d3913c71311609b3f3465728e733537dd0e34d8d063"
            ),
            "tagObject": "5c37ac99c248567bd7d50b965af8cbd45b6ced96",
            "peeledCommit": "dfb260231c761be7d9c8b63728e770a102b86495",
            "sourceRepo": "https://github.com/solana-program/token",
            "sourceTag": "program@v9.0.0",
            "runtimeCopy": "runtime-tests/solana/token/token_classic_v1.so",
        },
        "ata-classic-v1": {
            "kind": "loader-v3-elf",
            "relativePath": "supply-chain/solana-cpi-assets/v1/ata_classic_v1.so",
            "size": 111136,
            "sha256": (
                "d3f6df6f95f8b81c482478cc8c44b67ac3de2ca03162eaaf6c587ee8db646519"
            ),
            "buildRecipeDigest": (
                "f7ebe5236730d66ad730df6348b74332eb95e2abfda3377f389a13022e4528e2"
            ),
            "tagObject": "de77f367fdc0341879b1b9f0224c6b86107e1769",
            "peeledCommit": "0b867b5340cd001e5980d8ca7928effc4e10015c",
            "sourceRepo": (
                "https://github.com/solana-program/associated-token-account"
            ),
            "sourceTag": "program@v8.0.0",
            "runtimeCopy": "runtime-tests/solana/ata/ata_classic_v1.so",
        },
    }
    for package_id, expected in expected_package_owned.items():
        package = package_by_id[package_id]
        binding = package.get("artifactBinding")
        asset = assets_by_id[package_id]
        _expect_sol_cpi(
            package.get("admittedForMaterialization") is True
            and type(binding) is dict
            and binding.get("kind") == expected["kind"],
            catalog_path,
            f"{package_id} must be admitted loader-v3-elf in active catalog")
        _expect_sol_cpi(type(asset) is dict, assets_rel, f"{package_id} assets row missing")
        for key in provenance_keys:
            expected_value = expected[key]
            _expect_sol_cpi(
                binding.get(key) == expected_value,
                catalog_path,
                f"{package_id} active artifactBinding.{key} is not exact "
                f"(got {binding.get(key)!r}, expected {expected_value!r})")
            _expect_sol_cpi(
                asset.get(key) == expected_value,
                assets_rel,
                f"{package_id} assets manifest.{key} is not exact "
                f"(got {asset.get(key)!r}, expected {expected_value!r})")
            _expect_sol_cpi(
                binding.get(key) == asset.get(key),
                assets_rel,
                f"{package_id} assets manifest.{key} must equal active "
                f"catalog artifactBinding.{key}")
        # Assets row must not invent extra provenance identity fields that
        # diverge from the frozen package-owned tuple (packageId is row-only).
        for key in provenance_keys:
            _expect_sol_cpi(
                key in asset and key in binding,
                assets_rel,
                f"{package_id} provenance key {key} must be present on both sides")

        rel_elf = expected["relativePath"]
        elf_path = root / rel_elf
        ensure_repository_path(root, elf_path, rel_elf)
        if not elf_path.is_file():
            raise_error(
                "PF-DOC-SOLANA-CPI-CONTRACT", rel_elf,
                f"{package_id} package-owned ELF missing")
        elf_bytes = read_repository_regular_bytes(root, elf_path, rel_elf)
        elf_sha = hashlib.sha256(elf_bytes).hexdigest()
        _expect_sol_cpi(
            len(elf_bytes) == expected["size"] and elf_sha == expected["sha256"],
            rel_elf,
            f"{package_id} package-owned ELF size/sha must match frozen pins")

        # Exact byte equality with the tracked runtime-tests copy (same-host
        # package-owned pin source). Not mainnet/hermetic/cross-host claims.
        runtime_rel = expected["runtimeCopy"]
        runtime_path = root / runtime_rel
        ensure_repository_path(root, runtime_path, runtime_rel)
        if not runtime_path.is_file():
            raise_error(
                "PF-DOC-SOLANA-CPI-CONTRACT", runtime_rel,
                f"{package_id} runtime-tests ELF copy missing")
        runtime_bytes = read_repository_regular_bytes(
            root, runtime_path, runtime_rel)
        _expect_sol_cpi(
            runtime_bytes == elf_bytes,
            runtime_rel,
            f"{package_id} package-owned ELF must be exact-byte equal to "
            f"runtime-tests copy {runtime_rel}")

    # Tool Lock: locked sbpf must list both product ELF profiles.
    for lock_rel in ("toolchains.lock.json", "toolchains-linux-x86_64.lock.json"):
        lock_path = root / lock_rel
        ensure_repository_path(root, lock_path, lock_rel)
        lock = load_json(root, lock_path)
        tools = lock.get("tools") if isinstance(lock, dict) else None
        _expect_sol_cpi(type(tools) is list, lock_rel, "tools must be an array")
        sbpf = next(
            (t for t in tools
             if isinstance(t, dict) and t.get("id") == "sbpf"),
            None,
        )
        _expect_sol_cpi(sbpf is not None, lock_rel, "sbpf tool row missing")
        required = sbpf.get("requiredByProfiles") if isinstance(sbpf, dict) else None
        _expect_sol_cpi(
            type(required) is list
            and "solana-sbpf-cpi-elf-v1" in required
            and "solana-sbpf-elf-v1" in required,
            lock_rel,
            "sbpf requiredByProfiles must include solana-sbpf-cpi-elf-v1 and solana-sbpf-elf-v1")


def validate_solana_cpi_epic_checkpoint(root: Path) -> None:
    """Minimal stable anchors for Solana CPI epic #111–#125 engineering status.

    Avoids fragile full-paragraph duplication: issue-range / epic-complete pointers,
    historical #124 escrow pin SHAs, solana-runtime inventory shape, and bans on
    stale “Active #125 / ordinary resolver does not advertise” current-state claims.
    Does not claim formal TASK or GitHub issue state. Does not pre-claim
    ordinary `just dev-check` / `just ci` results.
    """
    agents_path = root / "AGENTS.md"
    ensure_repository_path(root, agents_path, "AGENTS.md")
    agents = read_repository_text(
        root, agents_path, "AGENTS.md", encoding_code="PF-DOC-CHECKPOINT")

    if not re.search(r"#111[–-]#125", agents):
        raise_error(
            "PF-DOC-CHECKPOINT", "AGENTS.md",
            "must record engineering closed range #111–#125")
    if not re.search(
            r"#110[^\n]{0,200}(engineering epic complete|工程 epic (已)?完成|工程 epic complete)",
            agents,
            re.IGNORECASE,
    ) and "engineering epic complete" not in agents.lower():
        # Accept compact Chinese/English epic-complete phrasing near #110.
        if not re.search(
                r"(#110[^\n]{0,120}(工程)?epic.{0,40}(complete|闭合|完成)"
                r"|(engineering )?epic #110.{0,40}(complete|闭合|完成)"
                r"|#110 engineering epic complete)",
                agents,
                re.IGNORECASE,
        ):
            raise_error(
                "PF-DOC-CHECKPOINT", "AGENTS.md",
                "must record #110 engineering epic complete")

    active_row = None
    program_row = None
    for line in agents.splitlines():
        if line.startswith("| Active task |"):
            active_row = line
        if line.startswith("| Program |"):
            program_row = line
    if active_row is None:
        raise_error("PF-DOC-CHECKPOINT", "AGENTS.md", "missing Active task checkpoint row")
    # Stale current-state: must not present #125 as still-pending Active activation.
    if re.search(
            r"(Active\s*(明确(为|\s)?)?\s*#125\b|"
            r"\*\*Active\s*(明确(为|\s)?)?\s*#125\*\*|"
            r"#125\s+activation\s+(仍\s*)?pending|"
            r"#125\s+前.{0,40}(不\s*advertise|ordinary resolver))",
            active_row,
            re.IGNORECASE,
    ):
        raise_error(
            "PF-DOC-CHECKPOINT", "AGENTS.md",
            "Active task must not still present #125 as pending Active / pre-advertise state")
    if re.search(r"ordinary resolver.{0,40}不\s*advertise|#125 前不 advertise", active_row):
        raise_error(
            "PF-DOC-CHECKPOINT", "AGENTS.md",
            "Active task must not claim ordinary resolver still does not advertise (post-#125)")
    if not re.search(r"#111[–-]#125", active_row):
        raise_error(
            "PF-DOC-CHECKPOINT", "AGENTS.md",
            "Active task row must name closed range #111–#125")
    if "CpiEscrowIRV1" not in agents and "composite escrow" not in agents.lower():
        raise_error(
            "PF-DOC-CHECKPOINT", "AGENTS.md",
            "must name CpiEscrowIRV1 or composite escrow for #124 history")
    if program_row is not None:
        # Only ban current-state claims that the ordinary CPI product path is still FC.
        # Historical #118–#124 test-preactivation "activationDenied" mentions may remain.
        if re.search(
                r"(ordinary product path仍在 legacy Plan前 FC|"
                r"solana-sbpf-cpi-elf-v1.{0,40}ordinary product path仍在|"
                r"新 `solana-sbpf-cpi-elf-v1` ordinary product path|"
                r"#125 前.{0,40}(fail closed|FC|不 advertise))",
                program_row,
        ):
            raise_error(
                "PF-DOC-CHECKPOINT", "AGENTS.md",
                "Program row must not describe CPI profile product path as still pre-#125 FC")
        if not re.search(
                r"(advertise sync\+extension|advertise exact.*synchronous-call|"
                r"product-only private capability|cpi-product-ir|b0f3f5bc)",
                program_row,
        ):
            raise_error(
                "PF-DOC-CHECKPOINT", "AGENTS.md",
                "Program row must state #125 CPI product advertise/sync or active product-ir pins")
    # Positive product activation anchors (stable, non-fragile).
    if "b0f3f5bc7f3973daf176c308cc4ca310f8ad5b51ea33a33c9d1bd3e4d3e91b04" not in agents:
        raise_error(
            "PF-DOC-CHECKPOINT", "AGENTS.md",
            "must pin active profile domain digest b0f3f5bc…")
    if "e2c2ebac5e690b99ad50fb7f8a5f6ecfdb8295bb43f3913229c2fd48d2820419" not in agents:
        raise_error(
            "PF-DOC-CHECKPOINT", "AGENTS.md",
            "must pin active catalog domain digest e2c2ebac…")
    if "cpi-product-ir" not in agents and "product-ir" not in agents:
        raise_error(
            "PF-DOC-CHECKPOINT", "AGENTS.md",
            "must name product-ir / cpi-product-ir for #125 active irSchema")
    # Integrated package-file pin is the current authority (refreshed after
    # #111–#125 + main merge). Historical feature-worktree close-out may still
    # mention 194 only when explicitly historical.
    if not re.search(r"SBOM[^\n]{0,40}\b233\b|\b233\b[^\n]{0,40}SBOM", agents):
        raise_error(
            "PF-DOC-CHECKPOINT", "AGENTS.md",
            "must record current SBOM package-file pin 233")
    if not re.search(
            r"\*\*13\*\* test binaries / \*\*304\*\* active tests",
            agents,
    ):
        raise_error(
            "PF-DOC-CHECKPOINT", "AGENTS.md",
            "must record current integrated Solana runtime inventory 13/304")

    # Historical #124 escrow pins remain immutable (test-preactivation lane retained).
    manifest_rel = "runtime-tests/solana/escrow/manifest.json"
    manifest_path = root / manifest_rel
    ensure_repository_path(root, manifest_path, manifest_rel)
    if not manifest_path.is_file():
        raise_error("PF-DOC-CHECKPOINT", manifest_rel, "escrow runtime manifest missing")
    payload = load_json(root, manifest_path)
    if not isinstance(payload, dict):
        raise_error("PF-DOC-CHECKPOINT", manifest_rel, "manifest root must be object")
    if payload.get("issue") != 124:
        raise_error("PF-DOC-CHECKPOINT", manifest_rel, "issue must be 124")
    boundary = payload.get("boundary")
    if not isinstance(boundary, dict):
        raise_error("PF-DOC-CHECKPOINT", manifest_rel, "boundary must be object")
    for key, expected in (
        ("productArtifact", False),
        ("testPreactivation", True),
        ("activationDenied", True),
    ):
        if boundary.get(key) is not expected:
            raise_error(
                "PF-DOC-CHECKPOINT", manifest_rel,
                f"boundary.{key} must be {expected!r}")
    fixture = payload.get("fixture")
    if not isinstance(fixture, dict):
        raise_error("PF-DOC-CHECKPOINT", manifest_rel, "fixture must be object")
    if fixture.get("sourceSize") != 5378:
        raise_error("PF-DOC-CHECKPOINT", manifest_rel, "fixture.sourceSize must be 5378")
    if fixture.get("sourceSha256") != (
        "0424045e7cdc7e3c57b79d95c144e6047819db91b46c39607e42bf256b7c33bf"
    ):
        raise_error("PF-DOC-CHECKPOINT", manifest_rel, "fixture.sourceSha256 pin mismatch")
    expected_asm = payload.get("expectedAssembly")
    expected_elf = payload.get("expectedElf")
    if not isinstance(expected_asm, dict) or not isinstance(expected_elf, dict):
        raise_error("PF-DOC-CHECKPOINT", manifest_rel, "expectedAssembly/expectedElf required")
    if expected_asm.get("size") != 366006 or expected_asm.get("sha256") != (
        "577f40646abb0a355bedebb76dd6b208ff39ae802bea1dab21ce4795ba5d102b"
    ):
        raise_error("PF-DOC-CHECKPOINT", manifest_rel, "expectedAssembly pin mismatch")
    if expected_elf.get("size") != 158536 or expected_elf.get("sha256") != (
        "28744d799b9a58208a54066d730a97a45e4363ae4f407132cf49c0bc7782b5f9"
    ):
        raise_error("PF-DOC-CHECKPOINT", manifest_rel, "expectedElf pin mismatch")
    calls = payload.get("expectedFinalElfCalls")
    if not isinstance(calls, list) or len(calls) != 37:
        raise_error(
            "PF-DOC-CHECKPOINT", manifest_rel,
            "expectedFinalElfCalls must be length 37")
    allowed = {
        "sol_try_find_program_address",
        "sol_invoke_signed_c",
        "sol_set_return_data",
    }
    if any(not isinstance(c, str) or c not in allowed for c in calls):
        raise_error(
            "PF-DOC-CHECKPOINT", manifest_rel,
            "expectedFinalElfCalls must only use find/invoke/set_return syscalls")
    non_claims = payload.get("nonClaims")
    if (not isinstance(non_claims, list)
            or "not multi-top-level transaction atomicity" not in non_claims):
        raise_error(
            "PF-DOC-CHECKPOINT", manifest_rel,
            "nonClaims must include not multi-top-level transaction atomicity")

    tests_dir = root / "runtime-tests" / "solana" / "tests"
    ensure_repository_path(root, tests_dir, "runtime-tests/solana/tests")
    binaries = sorted(
        path.stem for path in tests_dir.iterdir()
        if path.is_file() and path.suffix == ".rs"
    )
    if len(binaries) != 15:
        raise_error(
            "PF-DOC-CHECKPOINT", "runtime-tests/solana/tests",
            f"expected 15 integration test binaries, found {len(binaries)}: {binaries}")
    for required_binary in ("cpi_escrow", "transfer_sol_product", "tipjar_assets"):
        if required_binary not in binaries:
            raise_error(
                "PF-DOC-CHECKPOINT", "runtime-tests/solana/tests",
                f"missing {required_binary} integration binary")
    escrow_rs = tests_dir / "cpi_escrow.rs"
    ensure_repository_path(root, escrow_rs, "runtime-tests/solana/tests/cpi_escrow.rs")
    escrow_text = read_repository_text(
        root, escrow_rs, "runtime-tests/solana/tests/cpi_escrow.rs",
        encoding_code="PF-DOC-CHECKPOINT")
    test_fns = re.findall(
        r"#\[test\]\s*(?:\n\s*#\[[^\]]+\]\s*)*\n\s*fn\s+(\w+)",
        escrow_text,
    )
    if len(test_fns) != 36:
        raise_error(
            "PF-DOC-CHECKPOINT", "runtime-tests/solana/tests/cpi_escrow.rs",
            f"expected 36 #[test] functions, found {len(test_fns)}")

    transfer_rs = tests_dir / "transfer_sol_product.rs"
    ensure_repository_path(
        root, transfer_rs, "runtime-tests/solana/tests/transfer_sol_product.rs")
    transfer_text = read_repository_text(
        root, transfer_rs, "runtime-tests/solana/tests/transfer_sol_product.rs",
        encoding_code="PF-DOC-CHECKPOINT")
    transfer_tests = re.findall(
        r"#\[test\]\s*(?:\n\s*#\[[^\]]+\]\s*)*\n\s*fn\s+(\w+)",
        transfer_text,
    )
    if len(transfer_tests) != 8:
        raise_error(
            "PF-DOC-CHECKPOINT", "runtime-tests/solana/tests/transfer_sol_product.rs",
            f"expected 8 #[test] functions, found {len(transfer_tests)}")

    stale_current_state = re.compile(
        r"("
        r"\*\*Active\s*(明确(为|\s)?)?\s*#125\*\*"
        r"|Active\s*明确为\s*#125"
        r"|#125\s+activation\s+(仍\s*)?pending"
        r"|#125\s+前.{0,60}(ordinary resolver|不\s*advertise|不 advertise)"
        r"|ordinary resolver.{0,40}#125\s*前"
        r"|ordinary resolver 在 #125 前不 advertise"
        r")",
        re.IGNORECASE,
    )
    for rel in (
        "MIGRATION_MATRIX.md",
        "docs/engineering-backlog.md",
        "docs/adr/0028-solana-explicit-accounts-pda-cpi.md",
        "docs/targets/02-solana.md",
        "docs/research/12-target-coverage-matrix.md",
    ):
        doc_path = root / rel
        ensure_repository_path(root, doc_path, rel)
        body = read_repository_text(
            root, doc_path, rel, encoding_code="PF-DOC-CHECKPOINT")
        if not re.search(r"#111[–-]#125", body):
            # ADR/dossier may state epic complete without repeating full range if
            # they still name #125 closed; require either closed range or explicit
            # #125 engineering closed / product activation wording.
            if not re.search(
                    r"#125.{0,80}(工程(切片)?已闭合|engineering (slice )?closed|"
                    r"product activation|产品 (activation|同步|sync))",
                    body,
            ):
                raise_error(
                    "PF-DOC-CHECKPOINT", rel,
                    "must record #111–#125 engineering closed or #125 product activation closed")
        if rel in (
            "MIGRATION_MATRIX.md",
            "docs/engineering-backlog.md",
            "docs/adr/0028-solana-explicit-accounts-pda-cpi.md",
        ):
            if "CpiEscrowIRV1" not in body and "composite escrow" not in body.lower():
                raise_error(
                    "PF-DOC-CHECKPOINT", rel,
                    "must name CpiEscrowIRV1 or composite escrow for #124 history")
        if stale_current_state.search(body):
            raise_error(
                "PF-DOC-CHECKPOINT", rel,
                "must not retain Active #125 / pre-advertise current-state claims after #125 closed")
        if re.search(r"\*\*Active\s*(明确)?\s*#124\*\*", body):
            raise_error(
                "PF-DOC-CHECKPOINT", rel,
                "must not still bold-mark #124 as Active")



def validate_sol_cpi_contract(
        root: Path,
        json_values: dict[str, Any],
        by_id: dict[str, Document],
) -> None:
    """Validate ADR-0028's canonical payloads and critical closed joins."""
    adr = by_id.get(SOLANA_CPI_ADR_ID)
    _expect_sol_cpi(adr is not None, "docs/adr", "ADR-0028 is missing")
    assert adr is not None

    payloads: dict[str, Any] = {}
    domain_digests: dict[str, str] = {}
    for relative_path, domain in SOLANA_CPI_FROZEN_PAYLOADS:
        value = json_values.get(relative_path)
        _expect_sol_cpi(value is not None, relative_path, "frozen payload is missing")
        raw = read_repository_regular_bytes(root, root / relative_path, relative_path)
        canonical = _sol_cpi_canonical_jcs(value, relative_path)
        _expect_sol_cpi(
            raw == canonical, relative_path,
            "payload is not exact canonical JCS or has a BOM/trailing newline")
        raw_digest = hashlib.sha256(raw).hexdigest()
        domain_digest = hashlib.sha256(domain + raw).hexdigest()
        expected_raw, expected_domain = _sol_cpi_adr_digest_pair(
            adr, Path(relative_path).name)
        _expect_sol_cpi(
            raw_digest == expected_raw, relative_path,
            f"raw SHA-256 {raw_digest} does not match ADR-0028")
        _expect_sol_cpi(
            domain_digest == expected_domain, relative_path,
            f"domain digest {domain_digest} does not match ADR-0028")
        payloads[relative_path] = value
        domain_digests[relative_path] = f"sha256:{domain_digest}"

    extension_path = "docs/specs/solana-cpi-extension-v1.json"
    catalog_path = "docs/specs/solana-cpi-callee-catalog-v1.json"
    profile_path = "docs/specs/solana-cpi-profile-v1.json"
    extension = payloads[extension_path]
    catalog = payloads[catalog_path]
    profile = payloads[profile_path]
    _expect_sol_cpi(type(extension) is dict, extension_path, "root must be an object")
    _expect_sol_cpi(type(catalog) is dict, catalog_path, "root must be an object")
    _expect_sol_cpi(type(profile) is dict, profile_path, "root must be an object")

    extension_digest = domain_digests[extension_path]
    _expect_sol_cpi(
        extension.get("schema") == "proof-forge.solana.cpi-extension.v1"
        and extension.get("extensionId") == "solana.cpi.accounts"
        and extension.get("profileId") == "solana-sbpf-cpi-elf-v1"
        and extension.get("version") == "1.0.0",
        extension_path, "extension root identity is not exact")
    requirement = extension.get("requirementContract")
    _expect_sol_cpi(
        type(requirement) is dict
        and requirement.get("id") == "extension.solana-cpi-accounts"
        and requirement.get("version") == "1.0.0"
        and requirement.get("predicates") == []
        and requirement.get("digestDomain") == "pf.extension-semantics.v1",
        extension_path, "extension requirement contract is not exact")

    profile_requirement = profile.get("extensionRequirement")
    _expect_sol_cpi(
        profile.get("schema") == "proof-forge.solana.cpi-profile.v1"
        and profile.get("profileId") == "solana-sbpf-cpi-elf-v1"
        and type(profile_requirement) is dict
        and profile_requirement == {
            "digest": extension_digest,
            "id": "extension.solana-cpi-accounts",
            "predicates": [],
            "version": "1.0.0",
        },
        profile_path, "profile does not bind the exact extension requirement")
    catalog_ref = profile.get("calleeCatalog")
    _expect_sol_cpi(
        type(catalog_ref) is dict
        and catalog_ref.get("schema") == "proof-forge.solana.callee-catalog.v1"
        and catalog_ref.get("version") == "1.0.0"
        and catalog_ref.get("digestDomain") == "pf.solana.callee-catalog.v1",
        profile_path, "profile callee-catalog contract is not exact")
    _expect_sol_cpi(
        profile.get("runtimeCompatibility") == catalog.get("runtime"),
        profile_path, "profile runtimeCompatibility differs from the catalog runtime")

    packages = catalog.get("packages")
    _expect_sol_cpi(type(packages) is list, catalog_path, "packages must be an array")
    package_by_id: dict[str, dict[str, Any]] = {}
    for package in packages:
        _expect_sol_cpi(type(package) is dict, catalog_path, "package row must be an object")
        package_id = package.get("packageId")
        _expect_sol_cpi(
            type(package_id) is str and package_id not in package_by_id,
            catalog_path, "package IDs must be unique strings")
        program_id = package.get("programIdHex")
        _expect_sol_cpi(
            type(program_id) is str
            and re.fullmatch(r"[0-9a-f]{64}", program_id) is not None,
            catalog_path, f"package {package_id} has an invalid raw program ID")
        binding = package.get("artifactBinding")
        admitted = package.get("admittedForMaterialization")
        _expect_sol_cpi(
            type(admitted) is bool and type(binding) is dict,
            catalog_path, f"package {package_id} has an invalid admission row")
        _expect_sol_cpi(
            not admitted or binding.get("kind") != "absent",
            catalog_path, f"package {package_id} admits an absent artifact")
        _expect_sol_cpi(
            binding.get("kind") != "absent" or admitted is False,
            catalog_path, f"package {package_id} leaves an absent artifact admitted")
        package_by_id[package_id] = package

    _expect_sol_cpi(
        set(package_by_id) == {
            "companion-v1", "system-v1", "token-classic-v1", "ata-classic-v1"
        },
        catalog_path, "callee package set is not the frozen v1 set")
    companion_interface = package_by_id["companion-v1"].get("interfaceBinding")
    _expect_sol_cpi(
        type(companion_interface) is dict
        and companion_interface.get("extensionDigest") == extension_digest,
        catalog_path, "companion package does not bind the extension digest")
    token_interface = package_by_id["token-classic-v1"].get("interfaceBinding")
    _expect_sol_cpi(
        token_interface == {
            "commit": "dfb260231c761be7d9c8b63728e770a102b86495",
            "interfaceVersion": "2.0.0",
            "programVersion": "9.0.0",
            "repo": "https://github.com/solana-program/token",
            "tag": "program@v9.0.0",
            "tagObject": "5c37ac99c248567bd7d50b965af8cbd45b6ced96",
        },
        catalog_path,
        "classic Token interface must distinguish annotated tag object from peeled commit",
    )
    ata_interface = package_by_id["ata-classic-v1"].get("interfaceBinding")
    _expect_sol_cpi(
        ata_interface == {
            "commit": "0b867b5340cd001e5980d8ca7928effc4e10015c",
            "interfaceVersion": "2.0.0",
            "programVersion": "8.0.0",
            "repo": "https://github.com/solana-program/associated-token-account",
            "tag": "program@v8.0.0",
            "tagObject": "de77f367fdc0341879b1b9f0224c6b86107e1769",
        },
        catalog_path,
        "classic ATA interface must distinguish annotated tag object from peeled commit",
    )

    account_abi = extension.get("accountAbi")
    cpi_contract = extension.get("cpiContract")
    _expect_sol_cpi(
        type(account_abi) is dict
        and account_abi.get("accountDataDirectMapping") is True
        and account_abi.get("directAccountPointersInProgramInput") is True
        and account_abi.get("virtualAddressSpaceAdjustments") is True,
        extension_path, "ABIv1 direct-mapping feature triple is not exact")
    syscall = cpi_contract.get("syscall") if type(cpi_contract) is dict else None
    layouts = syscall.get("layouts") if type(syscall) is dict else None
    _expect_sol_cpi(
        type(syscall) is dict
        and syscall.get("symbol") == "sol_invoke_signed_c"
        and type(layouts) is dict
        and layouts.get("SolInstruction", {}).get("size") == 40
        and layouts.get("SolAccountMeta", {}).get("size") == 16
        and layouts.get("SolAccountInfo", {}).get("size") == 56
        and layouts.get("SolSignerSeed", {}).get("size") == 16
        and layouts.get("SolSignerSeeds", {}).get("size") == 16,
        extension_path, "C CPI ABI layouts are not exact")

    bump = extension.get("bumpContract")
    canonical_search = bump.get("canonicalSearch") if type(bump) is dict else None
    _expect_sol_cpi(
        type(canonical_search) is dict
        and canonical_search.get("first") == 255
        and canonical_search.get("last") == 1
        and canonical_search.get("attempts") == 255
        and bump.get("explicitNonCanonicalBump") == "unsupported-including-bump-zero",
        extension_path, "canonical bump contract is not exact 255 through 1")

    apis = extension.get("apis")
    _expect_sol_cpi(type(apis) is list, extension_path, "apis must be an array")
    expected_qns = [
        "solana.companion.invoke",
        "solana.companion.fail",
        "solana.companion.invokeSigned",
        "solana.system.transfer",
        "solana.system.createPdaAccount",
        "solana.token.transferChecked",
        "solana.token.transferCheckedPda",
        "solana.ata.createIdempotent",
    ]
    _expect_sol_cpi(
        [api.get("qn") for api in apis if type(api) is dict] == expected_qns,
        extension_path, "API QN order/set is not the frozen v1 surface")

    for api in apis:
        qn = api.get("qn")
        args = api.get("args")
        metas = api.get("metas")
        outer_only = api.get("outerOnlyAccounts")
        groups = api.get("signerGroups")
        codec = api.get("instructionCodec")
        _expect_sol_cpi(
            type(args) is list and type(metas) is list
            and type(outer_only) is list and type(groups) is list
            and all(type(item) is dict for item in args)
            and all(type(item) is dict for item in metas)
            and all(type(item) is dict for item in outer_only)
            and all(type(item) is dict for item in groups)
            and len(metas) <= 16 and len(groups) <= 4
            and type(codec) is dict and type(codec.get("length")) is int
            and type(codec.get("segments")) is list,
            extension_path, f"API {qn} has an incomplete digest-bound contract")
        arg_names = [item.get("name") for item in args if type(item) is dict]
        _expect_sol_cpi(
            len(arg_names) == len(args) and len(set(arg_names)) == len(arg_names),
            extension_path, f"API {qn} has duplicate or malformed args")
        account_args = {
            item["name"] for item in args
            if item.get("source") == "bare-direct-public-principal-parameter"
        }
        bound_arg_list = (
            [item.get("arg") for item in metas if "arg" in item]
            + [item.get("arg") for item in outer_only]
        )
        bound_args = set(bound_arg_list)
        _expect_sol_cpi(
            account_args == bound_args
            and len(bound_arg_list) == len(account_args),
            extension_path, f"API {qn} does not bind every account Principal exactly once")
        fixed_program = api.get("fixedProgram")
        callee_role = api.get("calleeRole")
        _expect_sol_cpi(
            fixed_program in package_by_id
            and type(callee_role) is dict
            and callee_role.get("fixedProgram") == fixed_program,
            extension_path, f"API {qn} has a malformed callee role")
        group_ids = [item.get("id") for item in groups if type(item) is dict]
        _expect_sol_cpi(
            group_ids == list(range(len(groups))),
            extension_path, f"API {qn} signer group IDs are not dense")
        group_by_id = {item["id"]: item for item in groups}
        used_groups: set[int] = set()
        for item in metas:
            fixed_meta = item.get("fixedProgram")
            if fixed_meta is not None:
                _expect_sol_cpi(
                    fixed_meta in package_by_id,
                    extension_path, f"API {qn} references unknown fixed meta package")
            group_id = item.get("signerGroupId")
            if group_id is not None:
                _expect_sol_cpi(
                    group_id in group_by_id
                    and item.get("arg") == group_by_id[group_id].get("metaArg")
                    and item.get("cpiSigner") is True
                    and item.get("outerSignerContribution") is False,
                    extension_path, f"API {qn} has a malformed PDA signer group join")
                used_groups.add(group_id)
            if item.get("cpiSigner") is True:
                _expect_sol_cpi(
                    item.get("outerSignerContribution") is True or group_id is not None,
                    extension_path, f"API {qn} has an unbacked CPI signer")
        _expect_sol_cpi(
            used_groups == set(group_by_id),
            extension_path, f"API {qn} has an unused signer group")

    ata = apis[-1]
    _expect_sol_cpi(
        len(ata["metas"]) == 6
        and ata["metas"][4].get("fixedProgram") == "system-v1"
        and ata["metas"][5].get("fixedProgram") == "token-classic-v1",
        extension_path, "ATA CreateIdempotent must carry System and Token metas 5/6")


def clean_cell(cell: str) -> str:
    value = cell.strip()
    if len(value) >= 2 and value[0] == "`" and value[-1] == "`":
        return value[1:-1].strip()
    return value


def mask_fenced_blocks(text: str) -> str:
    masked: list[str] = []
    fence: tuple[str, int] | None = None
    for line in text.splitlines():
        if fence is None:
            marker = re.match(r"^ {0,3}(`{3,}|~{3,})(.*)$", line)
            if marker and not (marker.group(1)[0] == "`" and "`" in marker.group(2)):
                fence = (marker.group(1)[0], len(marker.group(1)))
                masked.append("")
            else:
                masked.append(line)
        else:
            character, minimum = fence
            closing = re.match(
                rf"^ {{0,3}}({re.escape(character)}{{{minimum},}})[ \t]*$", line)
            if closing:
                fence = None
            masked.append("")
    return "\n".join(masked)


def mask_html_comments(text: str) -> str:
    return re.sub(
        r"<!--.*?(?:-->|$)",
        lambda match: "".join("\n" if character == "\n" else " "
                              for character in match.group(0)),
        text,
        flags=re.DOTALL,
    )


def mask_indented_code(text: str) -> str:
    return "\n".join(
        "" if line.startswith(("    ", "\t")) else line
        for line in text.splitlines()
    )


def mask_nonrendered(text: str) -> str:
    return mask_indented_code(mask_html_comments(mask_fenced_blocks(text)))


def mask_inline_code(text: str) -> str:
    result = list(text)
    index = 0
    while index < len(text):
        if text[index] != "`":
            index += 1
            continue
        backslashes = 0
        before = index - 1
        while before >= 0 and text[before] == "\\":
            backslashes += 1
            before -= 1
        if backslashes % 2 == 1:
            index += 1
            continue
        end_open = index
        while end_open < len(text) and text[end_open] == "`":
            end_open += 1
        width = end_open - index
        search = end_open
        closing = -1
        while search < len(text):
            candidate = text.find("`" * width, search)
            if candidate < 0:
                break
            before_run = candidate > 0 and text[candidate - 1] == "`"
            after_run = candidate + width < len(text) and text[candidate + width] == "`"
            slash_count = 0
            before = candidate - 1
            while before >= 0 and text[before] == "\\":
                slash_count += 1
                before -= 1
            if not before_run and not after_run and slash_count % 2 == 0:
                closing = candidate
                break
            search = candidate + width
        if closing < 0:
            index = end_open
            continue
        for position in range(index, closing + width):
            if result[position] != "\n":
                result[position] = " "
        index = closing + width
    return "".join(result)


def split_table_line(line: str, *, clean: bool = True) -> tuple[str, ...]:
    value = line.strip()
    if value.startswith("|"):
        value = value[1:]
    if value.endswith("|") and not value.endswith("\\|"):
        value = value[:-1]
    cells: list[str] = []
    current: list[str] = []
    escaped = False
    in_code = False
    for character in value:
        if escaped:
            current.append(character)
            escaped = False
        elif character == "\\":
            current.append(character)
            escaped = True
        elif character == "`":
            current.append(character)
            in_code = not in_code
        elif character == "|" and not in_code:
            cells.append(clean_cell("".join(current)) if clean
                         else "".join(current).strip())
            current = []
        else:
            current.append(character)
    cells.append(clean_cell("".join(current)) if clean
                 else "".join(current).strip())
    return tuple(cells)


def parse_tables(document: Document,
                 diagnostics: list[OrderedDiagnostic] | None = None,
                 *, ignore_inline_code: bool = True) -> list[TableRow]:
    visible = mask_nonrendered(document.text)
    if ignore_inline_code:
        visible = mask_inline_code(visible)
    lines = visible.splitlines()
    rows: list[TableRow] = []
    index = 0
    while index + 1 < len(lines):
        header_line = lines[index].strip()
        separator = lines[index + 1].strip()
        if not header_line.startswith("|") or not separator.startswith("|"):
            index += 1
            continue
        headers = split_table_line(header_line)
        separators = split_table_line(separator)
        if len(headers) != len(separators) or not all(re.fullmatch(r":?-{3,}:?", cell) for cell in separators):
            index += 1
            continue
        index += 2
        while index < len(lines) and lines[index].strip().startswith("|"):
            cells = split_table_line(lines[index])
            if len(cells) != len(headers):
                marker = cells[0] if cells else "<empty>"
                error = DocsCheckError(
                    "PF-DOC-TABLE-SHAPE", document.relative,
                    f"line {index + 1} row {marker} has {len(cells)} cells; "
                    f"expected {len(headers)}")
                if diagnostics is None:
                    raise error
                diagnostics.append(OrderedDiagnostic(
                    document.relative, index + 1, 1, marker, error))
                index += 1
                continue
            rows.append(TableRow(document.relative, index + 1, headers, cells))
            index += 1
    return rows


def split_ids(cell: str, row: TableRow, allowed: tuple[str, ...], *, allow_empty: bool) -> tuple[str, ...]:
    value = clean_cell(cell)
    if value in {"", "—"}:
        if allow_empty:
            return ()
        raise_error("PF-DOC-TRACE-INCOMPLETE", row.relative, f"line {row.line} has empty ID axis")
    identifiers = tuple(part.strip().strip("`") for part in value.split(","))
    for identifier in identifiers:
        if not TRACE_ID_RE.fullmatch(identifier) or not identifier.startswith(allowed):
            raise_error("PF-DOC-ID-FORMAT", row.relative,
                        f"line {row.line} requires exact comma-separated IDs, got {identifier}")
    if len(set(identifiers)) != len(identifiers):
        raise_error("PF-DOC-ID-DUPLICATE", row.relative,
                    f"line {row.line} repeats {next(x for x in identifiers if identifiers.count(x) > 1)}")
    return identifiers


def split_prerequisites(cell: str, row: TableRow) -> tuple[tuple[str, str], ...]:
    value = clean_cell(cell)
    if value in {"", "—"}:
        return ()
    result: list[tuple[str, str]] = []
    for part in value.split(","):
        item = part.strip().strip("`")
        match = re.fullmatch(r"([A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+)@(accepted)", item)
        if not match:
            raise_error("PF-DOC-PREREQUISITE", row.relative,
                        f"line {row.line} requires DOCUMENT-ID@accepted, got {item}")
        result.append((match.group(1), match.group(2)))
    if len(set(result)) != len(result):
        raise_error("PF-DOC-ID-DUPLICATE", row.relative,
                    f"line {row.line} repeats prerequisite {result[0][0]}")
    return tuple(result)


def ensure_known(definitions: dict[str, Definition], identifiers: Iterable[str], row: TableRow,
                 *, kinds: set[str] | None = None) -> None:
    for identifier in identifiers:
        if identifier not in definitions:
            raise_error("PF-DOC-ID-UNKNOWN", row.relative,
                        f"line {row.line} references unknown {identifier}")
        if kinds is not None and definitions[identifier].kind not in kinds:
            raise_error("PF-DOC-ID-TYPE", row.relative,
                        f"line {row.line} references {identifier} as {sorted(kinds)}, "
                        f"but it is {definitions[identifier].kind}")


def add_definition(definitions: dict[str, Definition], identifier: str,
                   relative_path: str, line: int, kind: str) -> None:
    if identifier in definitions:
        first = definitions[identifier]
        raise_error("PF-DOC-ID-DUPLICATE", relative_path,
                    f"{identifier} already defined at {first.relative}:{first.line}")
    definitions[identifier] = Definition(identifier, relative_path, line, kind)


def primary_definition_kind(identifier: str) -> str:
    if identifier.startswith("ADR-"):
        return "adr"
    if identifier.startswith("SPEC-"):
        return "spec"
    if identifier.startswith("MOD-"):
        return "module"
    if identifier.startswith("TRACE-"):
        return "trace"
    if identifier.startswith("TARGET-"):
        return "target"
    if identifier.startswith("REL-"):
        return "release"
    return "document"


def ensure_repository_path(root: Path, path: Path, display: str) -> None:
    try:
        parts = path.relative_to(root).parts
    except ValueError:
        raise_error("PF-DOC-PATH", display, "path is outside repository root")
    current = root
    for part in parts:
        current = current / part
        if current.is_symlink():
            raise_error("PF-DOC-PATH", display, f"symlink path component {current.name}")
    try:
        path.resolve().relative_to(root)
    except ValueError:
        raise_error("PF-DOC-PATH", display, "resolved path is outside repository root")


def ensure_no_tree_symlinks(root: Path, tree: Path) -> None:
    for current_text, directory_names, file_names in os.walk(tree, followlinks=False):
        current = Path(current_text)
        for name in sorted(directory_names + file_names):
            candidate = current / name
            if candidate.is_symlink():
                raise_error("PF-DOC-PATH", relative(root, candidate),
                            f"symlink path component {name}")


def heading_anchors(text: str) -> set[str]:
    anchors: set[str] = set()
    counts: dict[str, int] = {}
    for line in mask_nonrendered(text).splitlines():
        stripped = line.strip()
        for explicit in re.findall(r"<a\s+(?:[^>]*?\s)?id=[\"']([^\"']+)[\"']", line,
                                   re.IGNORECASE):
            anchors.add(explicit)
        match = re.match(r"^#{1,6}\s+(.+?)\s*#*\s*$", stripped)
        if not match:
            continue
        heading = re.sub(r"<[^>]+>", "", match.group(1))
        heading = re.sub(r"[`*_~]", "", heading).strip().lower()
        slug = re.sub(r"[^\w\-\s]", "", heading, flags=re.UNICODE)
        slug = re.sub(r"\s+", "-", slug)
        occurrence = counts.get(slug, 0)
        counts[slug] = occurrence + 1
        anchors.add(slug if occurrence == 0 else f"{slug}-{occurrence}")
    return anchors


def markdown_token_is_escaped(text: str, index: int) -> bool:
    backslashes = 0
    position = index - 1
    while position >= 0 and text[position] == "\\":
        backslashes += 1
        position -= 1
    return backslashes % 2 == 1


def supersession_cycle_details(documents: list[Document],
                               by_id: dict[str, Document]) -> dict[str, str]:
    successors = {
        document.meta["id"]: document.meta["successor"]
        for document in documents
        if (document.meta["status"] == "superseded"
            and document.meta.get("successor") in by_id)
    }
    details: dict[str, str] = {}
    for start in sorted(successors):
        order: list[str] = []
        positions: dict[str, int] = {}
        current = start
        while current in successors:
            if current in positions:
                cycle = order[positions[current]:] + [current]
                details[start] = " -> ".join(cycle)
                break
            positions[current] = len(order)
            order.append(current)
            current = successors[current]
    return details


def check_links(root: Path, docs_root: Path, documents: list[Document],
                by_id: dict[str, Document]) -> dict[Path, set[Path]]:
    graph: dict[Path, set[Path]] = {document.path: set() for document in documents}
    document_paths = set(graph)
    anchors = {document.path: heading_anchors(document.text) for document in documents}
    cycle_details = supersession_cycle_details(documents, by_id)
    diagnostics: list[OrderedDiagnostic] = []

    def validate_target(document: Document, raw_target: str, *, contributes_to_graph: bool) -> None:
        target = raw_target.strip().strip("<>")
        if target.lower().startswith(("http://", "https://", "mailto:")):
            return
        if len(target) > MAX_LINK_TARGET_LENGTH:
            raise_error("PF-DOC-LINK", document.relative,
                        f"local link target exceeds {MAX_LINK_TARGET_LENGTH} characters")
        path_text, separator, fragment = target.partition("#")
        path_text = unquote(path_text.strip())
        fragment = unquote(fragment.strip()) if separator else ""
        linked_lexical = document.path if not path_text else document.path.parent / path_text
        try:
            linked = linked_lexical.resolve()
            linked.relative_to(root)
        except ValueError:
            raise_error("PF-DOC-LINK-ESCAPE", document.relative,
                        f"link escapes repository root: {target}")
        except (OSError, RuntimeError) as error:
            raise_error("PF-DOC-LINK", document.relative,
                        f"invalid local link target: {error}")
        try:
            if not linked_lexical.exists():
                raise_error("PF-DOC-LINK", document.relative, f"broken link {target}")
            ensure_repository_path(root, linked_lexical, document.relative)
        except (OSError, RuntimeError) as error:
            raise_error("PF-DOC-LINK", document.relative,
                        f"invalid local link target: {error}")
        if fragment and linked.suffix == ".md":
            if linked not in anchors or fragment not in anchors[linked]:
                raise_error("PF-DOC-LINK-FRAGMENT", document.relative,
                            f"unknown fragment {fragment} in {target}")
        if contributes_to_graph and linked in document_paths and linked.suffix == ".md":
            graph[document.path].add(linked)

    def check_document_links(document: Document) -> None:
        visible = mask_inline_code(mask_nonrendered(document.text))
        references: dict[str, str] = {}
        occupied: list[tuple[int, int]] = []
        events: list[tuple[int, int, str, str, bool]] = []
        serial = 0

        definition_pattern = re.compile(
            r"(?m)^ {0,3}\[([^\]]+)\]:\s*(?:<([^>]+)>|(\S+))")
        for match in definition_pattern.finditer(visible):
            occupied.append(match.span())
            label = " ".join(match.group(1).lower().split())
            target = match.group(2) or match.group(3) or ""
            if label in references:
                events.append((match.start(), serial, "duplicate", label, False))
                serial += 1
            else:
                references[label] = target

        for match in INLINE_LINK_RE.finditer(visible):
            occupied.append(match.span())
            if markdown_token_is_escaped(visible, match.start()):
                continue
            events.append((match.start(), serial, "target", match.group(2),
                           match.group(1) != "!"))
            serial += 1

        full_reference_pattern = re.compile(r"(!?)\[([^\]]+)\]\[([^\]]*)\]")
        for match in full_reference_pattern.finditer(visible):
            occupied.append(match.span())
            if markdown_token_is_escaped(visible, match.start()):
                continue
            label = " ".join((match.group(3) or match.group(2)).lower().split())
            if label in references:
                events.append((match.start(), serial, "target", references[label],
                               match.group(1) != "!"))
            else:
                events.append((match.start(), serial, "unknown", label, False))
            serial += 1

        def overlaps_occupied(start: int, end: int) -> bool:
            return any(start < occupied_end and end > occupied_start
                       for occupied_start, occupied_end in occupied)

        shortcut_pattern = re.compile(r"(!?)\[([^\]\n]+)\]")
        for match in shortcut_pattern.finditer(visible):
            if overlaps_occupied(*match.span()):
                continue
            if markdown_token_is_escaped(visible, match.start()):
                continue
            label = " ".join(match.group(2).lower().split())
            if label not in references:
                continue
            events.append((match.start(), serial, "target", references[label],
                           match.group(1) != "!"))
            serial += 1

        for offset, _serial, kind, value, contributes_to_graph in sorted(events):
            line, column = source_position(visible, offset)
            if kind == "duplicate":
                error = DocsCheckError(
                    "PF-DOC-LINK", document.relative,
                    f"duplicate reference-link definition {value}")
                diagnostics.append(OrderedDiagnostic(
                    document.relative, line, column, value, error))
                continue
            if kind == "unknown":
                error = DocsCheckError(
                    "PF-DOC-LINK", document.relative,
                    f"unknown reference link {value}")
                diagnostics.append(OrderedDiagnostic(
                    document.relative, line, column, value, error))
                continue
            try:
                validate_target(document, value,
                                contributes_to_graph=contributes_to_graph)
            except DocsCheckError as error:
                diagnostics.append(OrderedDiagnostic(
                    document.relative, line, column, value, error))

    for document in documents:
        try:
            validate_document_lifecycle(document, by_id)
        except DocsCheckError as error:
            field = "successor" if error.code.startswith("PF-DOC-SUCCESSOR") else "status"
            diagnostics.append(OrderedDiagnostic(
                document.relative, frontmatter_field_line(document, field), 1,
                document.meta["id"], error))
        if document.meta["id"] in cycle_details:
            error = DocsCheckError(
                "PF-DOC-SUPERSESSION-CYCLE", document.relative,
                cycle_details[document.meta["id"]])
            diagnostics.append(OrderedDiagnostic(
                document.relative, frontmatter_field_line(document, "successor"), 1,
                document.meta["id"], error))
        check_document_links(document)
        if document.meta["status"] == "accepted":
            visible = mask_inline_code(mask_nonrendered(document.text))
            unresolved = UNRESOLVED_MARKER_RE.search(visible)
            if unresolved:
                line, column = source_position(visible, unresolved.start())
                error = DocsCheckError(
                    "PF-DOC-ACCEPTED-TODO", document.relative,
                    "accepted document has unresolved marker")
                diagnostics.append(OrderedDiagnostic(
                    document.relative, line, column, unresolved.group(0), error))
    index = (docs_root / "index.md").resolve()
    reachable: set[Path] = set()
    pending = [index]
    while pending:
        current = pending.pop()
        if current in reachable:
            continue
        reachable.add(current)
        pending.extend(sorted(graph.get(current, ()), reverse=True))
    for document in documents:
        if (document.meta["normative"] == "true" and document.meta["status"] != "archived"
                and document.path not in reachable):
            error = DocsCheckError(
                "PF-DOC-NORMATIVE-ORPHAN", document.relative,
                f"normative document {document.meta['id']} is unreachable from docs/index.md")
            diagnostics.append(OrderedDiagnostic(
                document.relative, frontmatter_field_line(document, "id"), 1,
                document.meta["id"], error))
    diagnostics.extend(document_status_index_diagnostics(documents))
    raise_first(diagnostics)
    return graph


def document_status_index_diagnostics(
        documents: list[Document]) -> list[OrderedDiagnostic]:
    by_relative = {document.relative: document for document in documents}
    index = by_relative["docs/document-status.md"]
    diagnostics: list[OrderedDiagnostic] = []
    rows = parse_tables(index, diagnostics, ignore_inline_code=False)
    counts = {target: 0 for target in STATUS_INDEX_TARGETS}
    for row in rows:
        if not {"当前文档", "状态"}.issubset(set(row.headers)):
            continue
        current = row.value({"当前文档"})
        stated_status = row.value({"状态"})
        if current is None or stated_status is None:
            error = DocsCheckError(
                "PF-DOC-STATUS", row.relative,
                f"line {row.line} status index lacks 当前文档/状态")
            diagnostics.append(OrderedDiagnostic(
                row.relative, row.line, 1, "<status-index>", error))
            continue
        link = INLINE_LINK_RE.search(current)
        if link is None:
            error = DocsCheckError(
                "PF-DOC-STATUS", row.relative,
                f"line {row.line} current document is not a local link")
            diagnostics.append(OrderedDiagnostic(
                row.relative, row.line, 1, current, error))
            continue
        target = link.group(2).strip().strip("<>").partition("#")[0]
        try:
            target_path = (index.path.parent / unquote(target)).resolve()
            target_relative = target_path.relative_to(index.path.parents[1]).as_posix()
        except (ValueError, OSError, RuntimeError) as path_error:
            error = DocsCheckError(
                "PF-DOC-STATUS", row.relative,
                f"line {row.line} has invalid current document {target}: {path_error}")
            diagnostics.append(OrderedDiagnostic(
                row.relative, row.line, 1, target, error))
            continue
        document = by_relative.get(target_relative)
        if document is None or target_relative not in counts:
            error = DocsCheckError(
                "PF-DOC-STATUS", row.relative,
                f"line {row.line} indexes non-canonical document {target}")
            diagnostics.append(OrderedDiagnostic(
                row.relative, row.line, 1, target, error))
            continue
        counts[target_relative] += 1
        expected = clean_cell(stated_status)
        if expected != document.meta["status"]:
            error = DocsCheckError(
                "PF-DOC-STATUS", row.relative,
                f"line {row.line} states {document.meta['id']} as {expected}, "
                f"frontmatter is {document.meta['status']}")
            diagnostics.append(OrderedDiagnostic(
                row.relative, row.line, 1, document.meta["id"], error))
    for target, count in counts.items():
        if count == 1:
            continue
        document = by_relative[target]
        error = DocsCheckError(
            "PF-DOC-STATUS", index.relative,
            f"canonical status index requires exactly one {target}, got {count}")
        diagnostics.append(OrderedDiagnostic(
            index.relative, 1, 1, document.meta["id"], error))
    return diagnostics


def collect_definitions(root: Path, documents: list[Document], json_values: dict[str, Any]) -> tuple[
        dict[str, Definition], list[TableRow], list[TaskRecord],
        dict[str, EvidenceRecord]]:
    definitions: dict[str, Definition] = {}
    by_relative = {document.relative: document for document in documents}
    tables: list[TableRow] = []
    evidence_records: dict[str, EvidenceRecord] = {}
    task_records: list[TaskRecord] = []
    diagnostics: list[OrderedDiagnostic] = []
    source_path = "docs/research/source-register.json"
    claim_path = "docs/research/claim-register.json"
    genesis_effective, genesis_failure = genesis_authority_state(root, by_relative)

    def capture(relative_path: str, line: int, identifier: str,
                action: Callable[[], None]) -> None:
        try:
            action()
        except DocsCheckError as error:
            diagnostics.append(OrderedDiagnostic(
                relative_path, line, 1, identifier, error))

    def collect_registry_item(relative_path: str, item_index: int, item: Any,
                              prefix: str, kind: str) -> None:
        if not isinstance(item, dict) or not isinstance(item.get("id"), str):
            raise_error("PF-DOC-JSON", relative_path,
                        f"each {kind} requires string id")
        identifier = item["id"]
        if not re.fullmatch(rf"{prefix}-[A-Z0-9]+(?:-[A-Z0-9]+)*", identifier):
            raise_error("PF-DOC-ID-FORMAT", relative_path,
                        f"malformed {kind} ID {identifier}")
        add_definition(definitions, identifier, relative_path, item_index, kind)

    def collect_business(row: TableRow) -> None:
        identifier = row.value({"ID"})
        if identifier is None:
            return
        if not re.fullmatch(r"BV-[A-Z0-9]+(?:-[A-Z0-9]+)*", identifier):
            raise_error("PF-DOC-ID-FORMAT", row.relative,
                        f"line {row.line} has malformed business ID {identifier}")
        add_definition(definitions, identifier, row.relative, row.line, "business")

    def collect_requirement(row: TableRow) -> None:
        identifier = row.value({"ID"})
        if identifier is None:
            return
        if not re.fullmatch(
                r"(?:GOAL|FR|NFR|OOS)-[A-Z0-9]+(?:-[A-Z0-9]+)*", identifier):
            raise_error("PF-DOC-ID-FORMAT", row.relative,
                        f"line {row.line} has malformed requirement ID {identifier}")
        kind = "goal" if identifier.startswith("GOAL-") else (
            "out_of_scope" if identifier.startswith("OOS-") else "requirement")
        add_definition(definitions, identifier, row.relative, row.line, kind)

    def collect_task(row: TableRow) -> None:
        headers = set(row.headers)
        first = row.cells[0] if row.cells else ""
        if "ID" not in headers and not first.lower().startswith("task"):
            return
        required_headers = {"ID", "Dependencies", "Prerequisites", "Tests", "Evidence"}
        missing_headers = required_headers - headers
        if not ({"Status", "状态"} & headers):
            missing_headers.add("Status")
        if missing_headers:
            code = ("PF-DOC-PREREQUISITE" if missing_headers == {"Prerequisites"}
                    else "PF-DOC-TASK-SCHEMA")
            raise_error(code, row.relative,
                        f"task table at line {row.line} lacks {sorted(missing_headers)}")
        identifier = row.value({"ID"})
        if identifier is None:
            raise_error("PF-DOC-ID-FORMAT", row.relative,
                        f"line {row.line} task row lacks ID")
        if not re.fullmatch(r"TASK-[A-Z0-9]+(?:-[A-Z0-9]+)*", identifier):
            raise_error("PF-DOC-ID-FORMAT", row.relative,
                        f"line {row.line} has malformed task ID {identifier}")
        if identifier.startswith("TASK-A0-") and not is_frozen_a0_task(identifier):
            raise_error(
                "PF-DOC-ID-FORMAT", row.relative,
                f"line {row.line} has A0 task outside frozen TASK-A0-01..20: {identifier}")
        add_definition(definitions, identifier, row.relative, row.line, "task")
        dependencies_cell = row.value({"Dependencies"})
        prerequisites_cell = row.value({"Prerequisites"})
        tests_cell = row.value({"Tests", "Test", "先行测试", "先行测试/验证"})
        evidence_cell = row.value({"Evidence"})
        status = row.value({"Status", "状态"})
        if (dependencies_cell is None or prerequisites_cell is None
                or tests_cell is None or evidence_cell is None or status is None):
            raise_error("PF-DOC-TASK-SCHEMA", row.relative,
                        f"task table at line {row.line} requires Dependencies, "
                        "Prerequisites, Tests, Evidence, Status")
        dependencies = split_ids(dependencies_cell, row, ("TASK-",), allow_empty=True)
        prerequisites = split_prerequisites(prerequisites_cell, row)
        tests = split_ids(tests_cell, row, ("TST-",), allow_empty=True)
        evidence = split_ids(evidence_cell, row, ("EV-",), allow_empty=True)
        if status not in TASK_STATUS:
            raise_error("PF-DOC-STATUS", row.relative,
                        f"task {identifier} has invalid status {status}")
        task_records.append(TaskRecord(
            identifier, dependencies, prerequisites, tests, evidence, status,
            row.relative, row.line))

    def collect_test(row: TableRow) -> None:
        identifier = row.value({"ID"})
        if identifier is None:
            return
        if not re.fullmatch(r"TST-[A-Z0-9]+(?:-[A-Z0-9]+)*", identifier):
            raise_error("PF-DOC-ID-FORMAT", row.relative,
                        f"catalog has malformed test ID {identifier}")
        if identifier.startswith("TST-A0-") and not is_frozen_a0_test(identifier):
            raise_error(
                "PF-DOC-ID-FORMAT", row.relative,
                f"catalog has A0 test outside frozen TST-A0-001..020: {identifier}")
        add_definition(definitions, identifier, row.relative, row.line, "test")

    def collect_evidence(row: TableRow, raw_lines: list[str]) -> None:
        first = row.cells[0] if row.cells else ""
        if "ID" not in set(row.headers) and not first.startswith("EV-"):
            return
        expected_headers = (
            "ID", "Task", "Tests", "Grade", "Gate / command", "Result",
            "Scope and limitation",
        )
        if row.headers != expected_headers:
            raise_error("PF-DOC-EVIDENCE-SCHEMA", row.relative,
                        f"evidence table at line {row.line} requires exact columns "
                        f"{list(expected_headers)}, got {list(row.headers)}")
        identifier = row.value({"ID"})
        task_cell = row.value({"Task"})
        tests_cell = row.value({"Tests"})
        grade = row.value({"Grade"})
        result = row.value({"Result"})
        if None in {identifier, task_cell, tests_cell, grade, result}:
            raise_error("PF-DOC-EVIDENCE-SCHEMA", row.relative,
                        f"evidence row at line {row.line} is incomplete")
        assert identifier is not None and task_cell is not None and tests_cell is not None
        assert grade is not None and result is not None
        if not re.fullmatch(r"EV-[0-9]{8}-[0-9]{4}", identifier):
            raise_error("PF-DOC-ID-FORMAT", row.relative,
                        f"line {row.line} has malformed evidence ID {identifier}")
        task_ids = split_ids(task_cell, row, ("TASK-",), allow_empty=True)
        if len(task_ids) > 1:
            raise_error("PF-DOC-EVIDENCE-SCHEMA", row.relative,
                        f"{identifier} must bind at most one task")
        tests = split_ids(tests_cell, row, ("TST-",), allow_empty=True)
        task = task_ids[0] if task_ids else None
        if task is None and tests:
            raise_error("PF-DOC-EVIDENCE-SCHEMA", row.relative,
                        f"{identifier} has tests without a task")
        if task is not None and not tests:
            raise_error("PF-DOC-EVIDENCE-SCHEMA", row.relative,
                        f"{identifier} binds {task} without tests")
        if grade not in {"development", "bootstrap", "formal"}:
            raise_error("PF-DOC-EVIDENCE-SCHEMA", row.relative,
                        f"{identifier} has invalid grade {grade}")
        gate_index = row.headers.index("Gate / command")
        raw_cells = (split_table_line(raw_lines[row.line - 1], clean=False)
                     if 0 < row.line <= len(raw_lines) else ())
        gate = raw_cells[gate_index] if gate_index < len(raw_cells) else ""
        if not gate.strip():
            raise_error("PF-DOC-EVIDENCE-COMMANDS", row.relative,
                        f"{identifier} has an empty Gate / command cell")
        for segment in gate.split("；"):
            segment = segment.strip()
            if not segment:
                raise_error("PF-DOC-EVIDENCE-COMMANDS", row.relative,
                            f"{identifier} has an empty command segment")
            attest = re.fullmatch(r"attest\s+`([^`]+)`", segment)
            if attest is None:
                continue
            attest_relative = attest.group(1)
            attest_path = root / attest_relative
            ensure_repository_path(root, attest_path, row.relative)
            if not attest_path.is_file():
                raise_error("PF-DOC-EVIDENCE-COMMANDS", row.relative,
                            f"{identifier} attests missing path {attest_relative}")
        add_definition(definitions, identifier, row.relative, row.line, "evidence")
        evidence_records[identifier] = EvidenceRecord(
            identifier, task, tests, grade, result, row.relative, row.line)

    def collect_fx_approvals(document: Document) -> None:
        visible_lines = mask_nonrendered(document.text).splitlines()
        fx_identifier: str | None = None
        fx_state: str | None = None
        fx_line = 0
        approval_seen = False
        void_seen = False
        required_void_record_seen = False
        fx_counts: dict[str, int] = {}

        def flush() -> None:
            nonlocal approval_seen, void_seen, required_void_record_seen
            if fx_identifier is not None and fx_state == "active" and not approval_seen:
                error = DocsCheckError(
                    "PF-DOC-FX-APPROVAL", document.relative,
                    f"freeze exception {fx_identifier} has no 批准 row "
                    "citing GOV-GENESIS-001")
                diagnostics.append(OrderedDiagnostic(
                    document.relative, fx_line, 1, fx_identifier, error))
            elif fx_identifier is not None and fx_state == "void" and not void_seen:
                error = DocsCheckError(
                    "PF-DOC-FX-APPROVAL", document.relative,
                    f"voided freeze exception {fx_identifier} requires 状态 `void`")
                diagnostics.append(OrderedDiagnostic(
                    document.relative, fx_line, 1, fx_identifier, error))
            if (fx_identifier == "FX-2026-07-17-D0-06"
                    and fx_state == "void" and void_seen):
                required_void_record_seen = True
            approval_seen = False
            void_seen = False

        for index, line in enumerate(visible_lines):
            if re.match(r"^#{1,6}\s", line):
                flush()
                fx_match = re.fullmatch(
                    r"#{1,6}\s+(?:[0-9]+(?:\.[0-9]+)*\s+)?"
                    r"(Voided Freeze Exception|Freeze Exception)"
                    r"\s+`(FX-[^`]+)`\s*", line)
                fx_identifier = fx_match.group(2) if fx_match else None
                fx_state = (
                    "void" if fx_match and fx_match.group(1).startswith("Voided")
                    else "active" if fx_match else None
                )
                fx_line = index + 1
                if fx_identifier is not None:
                    fx_counts[fx_identifier] = fx_counts.get(fx_identifier, 0) + 1
                    if fx_counts[fx_identifier] > 1:
                        error = DocsCheckError(
                            "PF-DOC-FX-APPROVAL", document.relative,
                            f"duplicate freeze exception {fx_identifier}")
                        diagnostics.append(OrderedDiagnostic(
                            document.relative, fx_line, 1, fx_identifier, error))
                continue
            if fx_identifier is None:
                continue
            stripped = line.strip()
            if not stripped.startswith("|"):
                continue
            cells = split_table_line(stripped)
            if fx_state == "void":
                if len(cells) >= 2 and cells[0] == "状态" and cells[1] == "void":
                    void_seen = True
                elif len(cells) >= 1 and cells[0] == "批准":
                    error = DocsCheckError(
                        "PF-DOC-FX-APPROVAL", document.relative,
                        f"voided freeze exception {fx_identifier} must not contain "
                        "an active 批准 row")
                    diagnostics.append(OrderedDiagnostic(
                        document.relative, index + 1, 1, fx_identifier, error))
                continue
            if approval_seen:
                continue
            if len(cells) < 2 or cells[0] != "批准":
                continue
            approval_seen = True
            approval_value = cells[1]
            if approval_value != (
                    "Quality + Architecture（经 `GOV-GENESIS-001` 追认）"):
                error = DocsCheckError(
                    "PF-DOC-FX-APPROVAL", document.relative,
                    f"freeze exception {fx_identifier} approval must match the exact "
                    "GOV-GENESIS-001 ratification grammar")
                diagnostics.append(OrderedDiagnostic(
                    document.relative, index + 1, 1, fx_identifier, error))
            elif not genesis_effective:
                error = DocsCheckError(
                    "PF-DOC-FX-APPROVAL", document.relative,
                    f"freeze exception {fx_identifier} cites ineffective "
                    f"{genesis_failure}; the full genesis governance stack must "
                    "be accepted by architecture-owner, davirain, quality-owner")
                diagnostics.append(OrderedDiagnostic(
                    document.relative, index + 1, 1, genesis_failure, error))
        flush()
        if (document.meta.get("id") == "GOV-TASK-FREEZE-001"
                and not required_void_record_seen):
            error = DocsCheckError(
                "PF-DOC-FX-APPROVAL", document.relative,
                "required void record FX-2026-07-17-D0-06 is missing or active")
            diagnostics.append(OrderedDiagnostic(
                document.relative, 1, 1, "FX-2026-07-17-D0-06", error))

    authoritative_paths = sorted({*by_relative, source_path, claim_path})
    for relative_path in authoritative_paths:
        if relative_path in {source_path, claim_path}:
            data = json_values.get(relative_path)
            array_name = "sources" if relative_path == source_path else "claims"
            prefix = "SRC" if relative_path == source_path else "CLM"
            kind = "source" if relative_path == source_path else "claim"
            if not isinstance(data, dict) or not isinstance(data.get(array_name), list):
                error = DocsCheckError(
                    "PF-DOC-JSON", relative_path, f"{array_name} must be an array")
                diagnostics.append(OrderedDiagnostic(
                    relative_path, 1, 1, array_name, error))
                continue
            for item_index, item in enumerate(data[array_name], start=1):
                identifier = item.get("id", f"<{kind}-{item_index}>") if isinstance(item, dict) else f"<{kind}-{item_index}>"
                capture(relative_path, item_index, str(identifier),
                        lambda item=item, item_index=item_index: collect_registry_item(
                            relative_path, item_index, item, prefix, kind))
            continue

        document = by_relative[relative_path]
        primary_id = document.meta["id"]
        capture(document.relative, 2, primary_id,
                lambda: add_definition(
                    definitions, primary_id, document.relative, 2,
                    primary_definition_kind(primary_id)))
        document_tables = parse_tables(document, diagnostics)
        tables.extend(document_tables)

        if relative_path == "docs/00-business-validation.md":
            for row in document_tables:
                capture(row.relative, row.line, row.value({"ID"}) or "<business>",
                        lambda row=row: collect_business(row))

        elif relative_path == "docs/01-prd.md":
            for row in document_tables:
                capture(row.relative, row.line, row.value({"ID"}) or "<requirement>",
                        lambda row=row: collect_requirement(row))

        elif relative_path == "docs/02-architecture.md":
            visible_lines = mask_inline_code(mask_nonrendered(document.text)).splitlines()
            invariant_marker = "## 架构不变量"
            try:
                marker_index = next(
                    index for index, line in enumerate(visible_lines)
                    if line.strip() == invariant_marker)
            except StopIteration:
                error = DocsCheckError(
                    "PF-DOC-REQUIRED", document.relative,
                    f"missing section {invariant_marker}")
                diagnostics.append(OrderedDiagnostic(
                    document.relative, 1, 1, invariant_marker, error))
                marker_index = len(visible_lines)
            section_end = next(
                (index for index in range(marker_index + 1, len(visible_lines))
                 if re.match(r"^##\s+", visible_lines[index].strip())),
                len(visible_lines),
            )
            for index in range(marker_index + 1, section_end):
                line = visible_lines[index]
                if not re.match(r"^\s*-\s+", line):
                    continue
                candidate = re.match(r"^\s*-\s+([^：:\s]+)[：:]", line)
                line_number = index + 1
                if not candidate:
                    error = DocsCheckError(
                        "PF-DOC-ID-FORMAT", document.relative,
                        f"invariant row at line {line_number} lacks canonical ID")
                    diagnostics.append(OrderedDiagnostic(
                        document.relative, line_number, 1, "<invariant>", error))
                    continue
                identifier = candidate.group(1)
                def collect_invariant(identifier: str = identifier,
                                      line_number: int = line_number) -> None:
                    if not re.fullmatch(r"INV-[A-Z0-9]+(?:-[A-Z0-9]+)*", identifier):
                        raise_error("PF-DOC-ID-FORMAT", document.relative,
                                    f"line {line_number} has malformed invariant ID {identifier}")
                    add_definition(definitions, identifier, document.relative,
                                   line_number, "invariant")
                capture(document.relative, line_number, identifier, collect_invariant)

        elif relative_path == "docs/04-task-breakdown.md":
            for row in document_tables:
                identifier = row.value({"ID"}) or (row.cells[0] if row.cells else "<task>")
                capture(row.relative, row.line, identifier,
                        lambda row=row: collect_task(row))

        elif relative_path == "docs/05-test-spec.md":
            visible_lines = mask_inline_code(mask_nonrendered(document.text)).splitlines()
            marker = "## 完整 Test ID Catalog"
            try:
                marker_index = next(
                    index for index, line in enumerate(visible_lines)
                    if line.strip() == marker)
            except StopIteration:
                error = DocsCheckError(
                    "PF-DOC-REQUIRED", document.relative, f"missing section {marker}")
                diagnostics.append(OrderedDiagnostic(
                    document.relative, 1, 1, marker, error))
                marker_index = len(visible_lines)
            catalog_end = next(
                (index for index in range(marker_index + 1, len(visible_lines))
                 if re.match(r"^###\s+", visible_lines[index].strip())),
                len(visible_lines),
            )
            for row in document_tables:
                if not (marker_index + 1 < row.line <= catalog_end):
                    continue
                capture(row.relative, row.line, row.value({"ID"}) or "<test>",
                        lambda row=row: collect_test(row))

        elif relative_path == "docs/traceability/evidence-ledger.md":
            raw_lines = document.text.splitlines()
            for row in document_tables:
                capture(row.relative, row.line, row.value({"ID"}) or "<evidence>",
                        lambda row=row: collect_evidence(row, raw_lines))

        elif relative_path == "docs/governance/task-freeze.md":
            collect_fx_approvals(document)

    raise_first(diagnostics)
    return definitions, tables, task_records, evidence_records


def validate_claims(definitions: dict[str, Definition], json_values: dict[str, Any]) -> None:
    claim_path = "docs/research/claim-register.json"
    for claim in json_values[claim_path]["claims"]:
        identifier = claim["id"]
        sources = claim.get("sources")
        if not isinstance(sources, list) or not sources or not all(isinstance(item, str) for item in sources):
            raise_error("PF-DOC-CLAIM-SOURCE", claim_path,
                        f"claim {identifier} requires at least one source")
        for source in sources:
            if (source not in definitions or not source.startswith("SRC-")
                    or definitions[source].kind != "source"):
                raise_error("PF-DOC-CLAIM-SOURCE", claim_path,
                            f"claim {identifier} references unknown {source}")


def load_task_set_lock(root: Path) -> dict[str, tuple[str, ...]]:
    relative = TASK_SET_LOCK_RELATIVE
    path = root / relative
    ensure_repository_path(root, path, relative)
    if not path.is_file():
        raise_error("PF-DOC-TASK-SET-LOCK", relative, "required task-set lock is missing")
    payload = load_json(root, path)
    if not isinstance(payload, dict):
        raise_error("PF-DOC-TASK-SET-LOCK", relative, "lock root must be a JSON object")
    schema_version = payload.get("schemaVersion")
    if schema_version != 1:
        raise_error(
            "PF-DOC-TASK-SET-LOCK", relative,
            f"schemaVersion must be 1, got {schema_version!r}")
    milestones = payload.get("milestones")
    if not isinstance(milestones, dict) or not milestones:
        raise_error("PF-DOC-TASK-SET-LOCK", relative, "milestones must be a non-empty object")
    locked: dict[str, tuple[str, ...]] = {}
    for raw_name, raw_ids in milestones.items():
        if not isinstance(raw_name, str) or not re.fullmatch(r"(?:A0|D[0-9]+)", raw_name):
            raise_error(
                "PF-DOC-TASK-SET-LOCK", relative,
                f"invalid milestone key {raw_name!r}")
        if not isinstance(raw_ids, list) or not raw_ids:
            raise_error(
                "PF-DOC-TASK-SET-LOCK", relative,
                f"milestone {raw_name} must be a non-empty array")
        seen: set[str] = set()
        ordered: list[str] = []
        for item in raw_ids:
            if not isinstance(item, str) or milestone_for_task(item) != raw_name:
                raise_error(
                    "PF-DOC-TASK-SET-LOCK", relative,
                    f"milestone {raw_name} has invalid task id {item!r}")
            if item in seen:
                raise_error(
                    "PF-DOC-TASK-SET-LOCK", relative,
                    f"milestone {raw_name} repeats {item}")
            seen.add(item)
            ordered.append(item)
        locked[raw_name] = tuple(ordered)
    return locked


def validate_task_set_lock(root: Path, tasks: list[TaskRecord]) -> None:
    locked = load_task_set_lock(root)
    relative = TASK_SET_LOCK_RELATIVE
    by_milestone: dict[str, set[str]] = {}
    for task in tasks:
        milestone = milestone_for_task(task.identifier)
        if milestone is None:
            continue
        by_milestone.setdefault(milestone, set()).add(task.identifier)
        if milestone not in locked:
            raise_error(
                "PF-DOC-TASK-SET-LOCK", task.relative,
                f"{task.identifier} belongs to unlocked milestone {milestone}; "
                f"add it only via approved lock update")

    for milestone, expected_ids in sorted(locked.items()):
        actual = by_milestone.get(milestone, set())
        expected = set(expected_ids)
        if actual != expected:
            missing = sorted(expected - actual)
            unexpected = sorted(actual - expected)
            raise_error(
                "PF-DOC-TASK-SET-LOCK", relative,
                f"milestone {milestone} task set must be exact; "
                f"missing={missing}, unexpected={unexpected}")


def _package_id_list(values: Any, *, field: str, relative: str) -> tuple[str, ...]:
    if values is None:
        return ()
    if not isinstance(values, list):
        raise_error(
            "PF-DOC-TASK-FREEZE", relative,
            f"{field} must be an array")
    ordered: list[str] = []
    seen: set[str] = set()
    for item in values:
        if not isinstance(item, str) or not item:
            raise_error(
                "PF-DOC-TASK-FREEZE", relative,
                f"{field} entries must be non-empty strings")
        if item in seen:
            raise_error(
                "PF-DOC-TASK-FREEZE", relative,
                f"{field} repeats {item}")
        seen.add(item)
        ordered.append(item)
    return tuple(ordered)


def load_task_freeze_package(root: Path, task_id: str) -> dict[str, Any]:
    relative = f"{TASK_FREEZE_PACKAGES_RELATIVE}/{task_id}.json"
    path = root / relative
    ensure_repository_path(root, path, relative)
    if not path.is_file():
        raise_error(
            "PF-DOC-TASK-FREEZE", relative,
            f"in_progress task {task_id} requires freeze package")
    payload = load_json(root, path)
    if not isinstance(payload, dict):
        raise_error("PF-DOC-TASK-FREEZE", relative, "package root must be a JSON object")
    if payload.get("schemaVersion") != 1:
        raise_error(
            "PF-DOC-TASK-FREEZE", relative,
            f"schemaVersion must be 1, got {payload.get('schemaVersion')!r}")
    if payload.get("taskId") != task_id:
        raise_error(
            "PF-DOC-TASK-FREEZE", relative,
            f"taskId must equal filename id {task_id}")
    output = payload.get("output")
    if not isinstance(output, str) or not output.strip():
        raise_error("PF-DOC-TASK-FREEZE", relative, "output must be a non-empty string")
    freeze_commit = payload.get("freezeCommit")
    if (not isinstance(freeze_commit, str)
            or not re.fullmatch(r"[0-9a-f]{40}", freeze_commit)):
        raise_error(
            "PF-DOC-TASK-FREEZE", relative,
            "freezeCommit must be a 40-char lowercase hex git commit")
    frozen_at = payload.get("frozenAt")
    if not isinstance(frozen_at, str):
        raise_error("PF-DOC-TASK-FREEZE", relative, "frozenAt must be a string date")
    parse_exact_date(frozen_at, code="PF-DOC-TASK-FREEZE", path=relative, field="frozenAt")
    return payload


def validate_task_freeze_packages(root: Path, tasks: list[TaskRecord]) -> None:
    packages_dir = root / TASK_FREEZE_PACKAGES_RELATIVE
    ensure_repository_path(root, packages_dir, TASK_FREEZE_PACKAGES_RELATIVE)
    if packages_dir.is_file():
        raise_error(
            "PF-DOC-TASK-FREEZE", TASK_FREEZE_PACKAGES_RELATIVE,
            "path must be a directory")
    if packages_dir.is_dir():
        ensure_no_tree_symlinks(root, packages_dir)
        for path in sorted(packages_dir.iterdir(), key=lambda item: item.name):
            rel = relative(root, path)
            ensure_repository_path(root, path, rel)
            if path.name.startswith("."):
                continue
            if path.is_dir() or not TASK_FREEZE_PACKAGE_NAME_RE.fullmatch(path.name):
                raise_error(
                    "PF-DOC-TASK-FREEZE", rel,
                    "freeze package files must be exactly TASK-*.json")

    tasks_by_id = {task.identifier: task for task in tasks}
    for task in sorted(
            (item for item in tasks if item.status == "in_progress"),
            key=lambda item: (item.relative, item.line, item.identifier)):
        relative_pkg = f"{TASK_FREEZE_PACKAGES_RELATIVE}/{task.identifier}.json"
        package = load_task_freeze_package(root, task.identifier)
        package_output = package["output"].strip()
        # Output is the second table cell; TaskRecord does not store it yet.
        # Re-parse from the task row text via package binding: require tests/deps/prereqs.
        deps = _package_id_list(
            package.get("dependencies"), field="dependencies", relative=relative_pkg)
        tests = _package_id_list(
            package.get("tests"), field="tests", relative=relative_pkg)
        raw_prereqs = package.get("prerequisites")
        if raw_prereqs is None:
            prereq_tokens: tuple[str, ...] = ()
        elif not isinstance(raw_prereqs, list):
            raise_error(
                "PF-DOC-TASK-FREEZE", relative_pkg,
                "prerequisites must be an array")
        else:
            prereq_tokens = _package_id_list(
                raw_prereqs, field="prerequisites", relative=relative_pkg)
        for token in prereq_tokens:
            if not re.fullmatch(r"[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+@accepted", token):
                raise_error(
                    "PF-DOC-TASK-FREEZE", relative_pkg,
                    f"prerequisite {token!r} must be DOCUMENT-ID@accepted")

        task_prereq_tokens = tuple(
            f"{doc}@{status}" for doc, status in task.prerequisites)
        if task.dependencies != deps:
            raise_error(
                "PF-DOC-TASK-FREEZE", relative_pkg,
                f"{task.identifier} dependencies drifted from freeze package: "
                f"task={list(task.dependencies)} package={list(deps)}")
        if task.tests != tests:
            raise_error(
                "PF-DOC-TASK-FREEZE", relative_pkg,
                f"{task.identifier} tests drifted from freeze package: "
                f"task={list(task.tests)} package={list(tests)}")
        if task_prereq_tokens != prereq_tokens:
            raise_error(
                "PF-DOC-TASK-FREEZE", relative_pkg,
                f"{task.identifier} prerequisites drifted from freeze package: "
                f"task={list(task_prereq_tokens)} package={list(prereq_tokens)}")

        if not _task_output_matches(root, task, package_output):
            raise_error(
                "PF-DOC-TASK-FREEZE", relative_pkg,
                f"{task.identifier} output drifted from freeze package")

    # Packages without a matching in_progress task are allowed (historical/pending prep),
    # but taskId must still parse and match filename when the file exists and is loaded
    # only for in_progress above. Validate orphan package filenames reference known tasks.
    if packages_dir.is_dir():
        for path in sorted(packages_dir.glob("TASK-*.json"), key=lambda item: item.name):
            task_id = path.stem
            if task_id not in tasks_by_id:
                raise_error(
                    "PF-DOC-TASK-FREEZE", relative(root, path),
                    f"freeze package {task_id} has no task row")


def _task_output_matches(root: Path, task: TaskRecord, expected_output: str) -> bool:
    path = root / task.relative
    text = read_repository_text(root, path, task.relative)
    lines = text.splitlines()
    if task.line < 1 or task.line > len(lines):
        return False
    line = lines[task.line - 1]
    if not line.startswith("|"):
        return False
    cells = list(split_table_line(line))
    if len(cells) < 2 or cells[0] != task.identifier:
        return False
    return cells[1] == expected_output


def validate_frozen_a0_pairs(definitions: dict[str, Definition],
                             tasks: list[TaskRecord]) -> None:
    tasks_by_id = {task.identifier: task for task in tasks}
    expected_tasks = set(FROZEN_A0_TASK_TO_TEST)
    actual_tasks = {
        task.identifier for task in tasks
        if task.identifier.startswith("TASK-A0-")
    }
    if actual_tasks != expected_tasks:
        missing = sorted(expected_tasks - actual_tasks)
        unexpected = sorted(actual_tasks - expected_tasks)
        raise_error(
            "PF-DOC-TASK-SCHEMA", "docs/04-task-breakdown.md",
            f"frozen A0 task set must be exact; missing={missing}, unexpected={unexpected}")

    expected_tests = set(FROZEN_A0_TEST_TO_TASK)
    actual_tests = {
        identifier for identifier, definition in definitions.items()
        if definition.kind == "test" and identifier.startswith("TST-A0-")
    }
    if actual_tests != expected_tests:
        missing = sorted(expected_tests - actual_tests)
        unexpected = sorted(actual_tests - expected_tests)
        raise_error(
            "PF-DOC-TASK-SCHEMA", "docs/05-test-spec.md",
            f"frozen A0 test set must be exact; missing={missing}, unexpected={unexpected}")

    for task in sorted(tasks, key=lambda item: (item.relative, item.line, item.identifier)):
        if is_frozen_a0_task(task.identifier):
            expected = FROZEN_A0_TASK_TO_TEST[task.identifier]
            if task.tests != (expected,):
                raise_error(
                    "PF-DOC-TASK-SCHEMA", task.relative,
                    f"frozen {task.identifier} must own only {expected}, got {list(task.tests)}")
            if task.status != "done":
                raise_error(
                    "PF-DOC-TASK-SCHEMA", task.relative,
                    f"frozen {task.identifier} must remain done, got {task.status}")
            continue
        frozen_tests = [test for test in task.tests if is_frozen_a0_test(test)]
        if frozen_tests:
            test = frozen_tests[0]
            raise_error(
                "PF-DOC-TASK-SCHEMA", task.relative,
                f"{test} may only be owned by {FROZEN_A0_TEST_TO_TASK[test]}, "
                f"not {task.identifier}")

    for test, task_identifier in FROZEN_A0_TEST_TO_TASK.items():
        definition = definitions.get(test)
        if definition is None or definition.kind != "test":
            continue
        if task_identifier not in tasks_by_id:
            raise_error(
                "PF-DOC-TRACE-ORPHAN", definition.relative,
                f"frozen A0 test {test} has no corresponding {task_identifier}")


def validate_trace(documents: list[Document], definitions: dict[str, Definition],
                   tasks: list[TaskRecord]) -> None:
    validate_frozen_a0_pairs(definitions, tasks)
    matrix = next(document for document in documents
                  if document.relative == "docs/traceability/requirements-matrix.md")
    rows = [row for row in parse_tables(matrix)
            if row.value({"Requirement"}) and row.value({"Requirement"}) != "Requirement"]
    traced: dict[str, TableRow] = {}
    traced_tests: set[str] = set()
    traced_tasks: set[str] = set()
    traced_task_test_pairs: set[tuple[str, str]] = set()
    used_goals: set[str] = set()
    tasks_by_id = {task.identifier: task for task in tasks}
    for row in rows:
        requirement_cell = row.value({"Requirement"})
        goal_cell = row.value({"Goal"})
        adr_cell = row.value({"ADR/INV"})
        spec_cell = row.value({"Spec/Module"})
        task_cell = row.value({"Task"})
        test_cell = row.value({"Test"})
        evidence_cell = row.value({"Evidence"})
        if None in {requirement_cell, goal_cell, adr_cell, spec_cell, task_cell, test_cell,
                    evidence_cell}:
            raise_error("PF-DOC-TRACE-INCOMPLETE", row.relative,
                        f"line {row.line} lacks canonical trace columns")
        requirements = split_ids(requirement_cell or "", row, ("FR-", "NFR-"), allow_empty=False)
        if len(requirements) != 1:
            raise_error("PF-DOC-TRACE-INCOMPLETE", row.relative,
                        f"line {row.line} must identify one requirement")
        requirement = requirements[0]
        if requirement in traced:
            raise_error("PF-DOC-ID-DUPLICATE", row.relative,
                        f"trace row repeated for {requirement}")
        def required_axis(cell: str, allowed: tuple[str, ...], label: str) -> tuple[str, ...]:
            if clean_cell(cell) in {"", "—"}:
                raise_error("PF-DOC-TRACE-INCOMPLETE", row.relative,
                            f"{requirement} has empty {label} axis at line {row.line}")
            return split_ids(cell, row, allowed, allow_empty=False)

        goals = required_axis(goal_cell or "", ("GOAL-",), "Goal")
        decisions = required_axis(adr_cell or "", ("ADR-", "INV-"), "ADR/INV")
        specs = required_axis(spec_cell or "",
                              ("SPEC-", "MOD-", "TRACE-", "TARGET-"), "Spec/Module")
        task_ids = required_axis(task_cell or "", ("TASK-",), "Task")
        test_ids = required_axis(test_cell or "", ("TST-",), "Test")
        if clean_cell(evidence_cell or "") != "specified":
            raise_error("PF-DOC-TRACE-INCOMPLETE", row.relative,
                        f"{requirement} Evidence must be specified, got {evidence_cell}")
        ensure_known(definitions, requirements, row, kinds={"requirement"})
        ensure_known(definitions, goals, row, kinds={"goal"})
        for decision in decisions:
            expected = {"adr"} if decision.startswith("ADR-") else {"invariant"}
            ensure_known(definitions, (decision,), row, kinds=expected)
        for spec in specs:
            if spec.startswith("SPEC-"):
                expected = {"spec"}
            elif spec.startswith("MOD-"):
                expected = {"module"}
            elif spec.startswith("TRACE-"):
                expected = {"trace"}
            else:
                expected = {"target"}
            ensure_known(definitions, (spec,), row, kinds=expected)
        ensure_known(definitions, task_ids, row, kinds={"task"})
        ensure_known(definitions, test_ids, row, kinds={"test"})
        owned_tests = {
            test
            for task_identifier in task_ids
            for test in tasks_by_id[task_identifier].tests
        }
        for test in test_ids:
            if test not in owned_tests:
                raise_error("PF-DOC-TRACE-OWNERSHIP", row.relative,
                            f"{requirement} test {test} is not owned by any task in the row")
            for task_identifier in task_ids:
                if test in tasks_by_id[task_identifier].tests:
                    traced_task_test_pairs.add((task_identifier, test))
        traced[requirement] = row
        traced_tests.update(test_ids)
        traced_tasks.update(task_ids)
        used_goals.update(goals)

    prd = next(document for document in documents if document.relative == "docs/01-prd.md")
    if prd.meta["normative"] == "true" and prd.meta["status"] in ACTIVE_NORMATIVE_STATUS:
        for identifier, definition in sorted(definitions.items()):
            if definition.relative != prd.relative:
                continue
            if identifier.startswith(("FR-", "NFR-")) and identifier not in traced:
                raise_error("PF-DOC-TRACE-ORPHAN", prd.relative,
                            f"active normative requirement {identifier} has no trace row")
            if identifier.startswith("GOAL-") and identifier not in used_goals:
                raise_error("PF-DOC-TRACE-ORPHAN", prd.relative,
                            f"active product goal {identifier} has no requirement edge")

    formal_tasks = sorted(
        (
            task for task in tasks
            if not is_frozen_a0_task(task.identifier)
        ),
        key=lambda task: (task.relative, task.line, task.identifier),
    )
    for task in formal_tasks:
        if task.identifier not in traced_tasks:
            raise_error(
                "PF-DOC-TRACE-ORPHAN", task.relative,
                f"formal task {task.identifier} has no requirement trace edge")
        for test in task.tests:
            if (task.identifier, test) not in traced_task_test_pairs:
                raise_error(
                    "PF-DOC-TRACE-ORPHAN", task.relative,
                    f"formal task {task.identifier} test {test} has no joint requirement trace edge")

    task_owned_tests = {
        test
        for task in tasks
        for test in task.tests
    }
    required_tests = sorted(
        (
            (identifier, definition)
            for identifier, definition in definitions.items()
            if definition.kind == "test"
            and not is_frozen_a0_test(identifier)
        ),
        key=lambda item: (item[1].relative, item[1].line, item[0]),
    )
    for identifier, definition in required_tests:
        if identifier not in task_owned_tests:
            raise_error(
                "PF-DOC-TRACE-ORPHAN", definition.relative,
                f"required test {identifier} has no task owner")
        if identifier not in traced_tests:
            raise_error(
                "PF-DOC-TRACE-ORPHAN", definition.relative,
                f"required test {identifier} has no requirement trace edge")


def _load_bootstrap_closure_attest(root: Path, relative_path: str) -> dict[str, Any] | None:
    path = root / relative_path
    try:
        ensure_repository_path(root, path, relative_path)
    except DocsCheckError:
        return None
    if not path.is_file():
        return None
    try:
        payload = load_json(root, path)
    except DocsCheckError:
        return None
    if not isinstance(payload, dict):
        return None
    return payload


def d0_01_pure_consumer_attested(root: Path) -> bool:
    """Return True only for FX-2026-07-17-D0-01 pure-consumer closure attestation."""
    payload = _load_bootstrap_closure_attest(root, D0_01_PURE_CONSUMER_ATTEST_RELATIVE)
    if payload is None:
        return False
    required = {
        "schemaVersion": 1,
        "taskId": "TASK-D0-01",
        "kind": "pure-consumer-closure",
        "freezeException": "FX-2026-07-17-D0-01",
        "selfTestResult": "ok",
        "protectedIntegration": "deferred-fail-closed-to-D0-04",
    }
    for key, expected in required.items():
        if payload.get(key) != expected:
            return False
    consumer = payload.get("consumerModule")
    if consumer != "scripts/bootstrap_task_objects.py":
        return False
    consumer_commit = payload.get("consumerCommit")
    if (not isinstance(consumer_commit, str)
            or not re.fullmatch(r"[0-9a-f]{40}", consumer_commit)):
        return False
    for field in ("selfTestCommand", "docsCheckCommand"):
        value = payload.get(field)
        if not isinstance(value, str) or "python3" not in value:
            return False
    return True


def d0_02_package_boundary_attested(root: Path) -> bool:
    """Return True only for FX-2026-07-17-D0-02 package-boundary closure attestation."""
    payload = _load_bootstrap_closure_attest(root, D0_02_PACKAGE_BOUNDARY_ATTEST_RELATIVE)
    if payload is None:
        return False
    required = {
        "schemaVersion": 1,
        "taskId": "TASK-D0-02",
        "kind": "package-boundary-closure",
        "freezeException": "FX-2026-07-17-D0-02",
        "selfTestResult": "ok",
        "isolationResult": "ok",
        "bootstrapAuthority": "deferred-fail-closed-to-D0-04",
    }
    for key, expected in required.items():
        if payload.get(key) != expected:
            return False
    green = payload.get("implementationGreenCommit")
    if (not isinstance(green, str)
            or not re.fullmatch(r"[0-9a-f]{40}", green)):
        return False
    self_test = payload.get("selfTestCommand")
    if (not isinstance(self_test, str)
            or "python3" not in self_test
            or "v2_isolation" not in self_test):
        return False
    isolation = payload.get("isolationCommand")
    if not isinstance(isolation, str) or "v2-isolation" not in isolation:
        return False
    docs_check = payload.get("docsCheckCommand")
    if (not isinstance(docs_check, str)
            or ("docs_check" not in docs_check and "docs-check" not in docs_check)):
        return False
    return True


def d0_03_development_triad_attested(root: Path) -> bool:
    """Return True only for FX-2026-07-17-D0-03 development triad closure attestation."""
    payload = _load_bootstrap_closure_attest(root, D0_03_DEVELOPMENT_TRIAD_ATTEST_RELATIVE)
    if payload is None:
        return False
    required = {
        "schemaVersion": 1,
        "taskId": "TASK-D0-03",
        "kind": "development-triad-closure",
        "freezeException": "FX-2026-07-17-D0-03",
        "evidenceCoreResult": "ok",
        "hostDevelopmentResult": "ok",
        "hostFormalEligible": False,
        "toolchainResult": "ok",
        "bootstrapAuthority": "deferred-fail-closed-to-D0-04",
        "fullPolicyReceiptEvaluator": "implemented",
    }
    for key, expected in required.items():
        if payload.get(key) != expected:
            return False
    for field, needle in (
        ("evidenceCoreCommand", "gate_evidence"),
        ("hostDevelopmentCommand", "verify_host_stage0"),
        ("toolchainCommand", "toolchain_assets"),
        ("docsCheckCommand", "docs_check"),
    ):
        value = payload.get(field)
        if not isinstance(value, str) or needle not in value:
            return False
    return True




def d0_05_sbom_inventory_attested(root: Path) -> bool:
    """Return True only for FX-2026-07-17-D0-05 SBOM inventory closure attestation."""
    payload = _load_bootstrap_closure_attest(root, D0_05_SBOM_INVENTORY_ATTEST_RELATIVE)
    if payload is None:
        return False
    required = {
        "schemaVersion": 1,
        "taskId": "TASK-D0-05",
        "kind": "sbom-inventory-closure",
        "freezeException": "FX-2026-07-17-D0-05",
        "selfTestResult": "ok",
        "generateResult": "ok",
        "verifyResult": "ok",
        "bootstrapAuthority": "deferred-fail-closed-to-D0-04",
    }
    for key, expected in required.items():
        if payload.get(key) != expected:
            return False
    for field, needle in (
        ("selfTestCommand", "sbom_self_test"),
        ("generateCommand", "sbom_generate"),
        ("verifyCommand", "sbom_generate"),
        ("docsCheckCommand", "docs_check"),
    ):
        value = payload.get(field)
        if not isinstance(value, str) or needle not in value:
            return False
    return True


def d0_06_common_primitives_attested(
        root: Path, evidence_records: dict[str, EvidenceRecord]) -> bool:
    """Validate the exact GOV-GENESIS-001 common-primitives closure."""
    payload = _load_bootstrap_closure_attest(
        root, D0_06_COMMON_PRIMITIVES_ATTEST_RELATIVE)
    if payload is None:
        return False
    expected_fields = {
        "schemaVersion",
        "taskId",
        "kind",
        "genesisAuthority",
        "freezePackage",
        "freezePackageSha256",
        "frozenTechnicalEvidence",
        "technicalEvidenceGrade",
        "redCommit",
        "implementationGreenCommit",
        "focusedTestCommand",
        "focusedTestResult",
        "focusedAssertionCount",
        "cleanCiCommand",
        "cleanCiContext",
        "cleanCiResult",
        "independentReviewP0",
        "independentReviewP1",
        "docsCheckCommand",
        "bootstrapAuthority",
        "notes",
    }
    if set(payload) != expected_fields:
        return False
    exact_values: dict[str, Any] = {
        "taskId": "TASK-D0-06",
        "kind": "common-primitives-genesis-closure",
        "genesisAuthority": "GOV-GENESIS-001",
        "freezePackage": (
            "docs/governance/task-freeze-packages/TASK-D0-06.json"),
        "frozenTechnicalEvidence": "EV-20260717-0034",
        "technicalEvidenceGrade": "development",
        "redCommit": "807d73ba9e5f4bcb3f6b9591de02dd67336c8cf2",
        "implementationGreenCommit": (
            "343a08f27835ca9d55b4a3698bf3313cb8e4e06d"),
        "focusedTestCommand": (
            "lake build ProofForgeV2.Core.Common proof_forge_next_tests && "
            "lake exe proof_forge_next_tests"),
        "focusedTestResult": "ok",
        "cleanCiCommand": "just ci",
        "cleanCiContext": "clean-detached-worktree",
        "cleanCiResult": "ok",
        "docsCheckCommand": (
            "/usr/bin/python3 -I -S scripts/docs_check.py --root ."),
        "bootstrapAuthority": "deferred-fail-closed-to-D0-04",
    }
    for field, expected in exact_values.items():
        if payload.get(field) != expected:
            return False
    technical_evidence = evidence_records.get("EV-20260717-0034")
    if (technical_evidence is None
            or technical_evidence.task != "TASK-D0-06"
            or technical_evidence.tests != ("TST-COMMON-001",)
            or technical_evidence.grade != "development"
            or technical_evidence.result
            != "passed (complete frozen common-primitives technical slice)"):
        return False
    for field, expected in (
        ("schemaVersion", 1),
        ("focusedAssertionCount", 232),
        ("independentReviewP0", 0),
        ("independentReviewP1", 0),
    ):
        value = payload.get(field)
        if type(value) is not int or value != expected:
            return False
    freeze_digest = payload.get("freezePackageSha256")
    if (not isinstance(freeze_digest, str)
            or not re.fullmatch(r"[0-9a-f]{64}", freeze_digest)):
        return False
    freeze_path = root / exact_values["freezePackage"]
    try:
        ensure_repository_path(root, freeze_path, str(exact_values["freezePackage"]))
        freeze_bytes = read_repository_regular_bytes(
            root, freeze_path, str(exact_values["freezePackage"]))
        actual_freeze_digest = hashlib.sha256(freeze_bytes).hexdigest()
    except (DocsCheckError, OSError):
        return False
    if freeze_digest != actual_freeze_digest:
        return False
    notes = payload.get("notes")
    if (not isinstance(notes, str)
            or "not formal or hermetic evidence" not in notes):
        return False
    return True


def d0_08_sbom_closure_attested(root: Path) -> bool:
    """Return True only for GOV-PRECUTOVER-001 SBOM closure attestation."""
    payload = _load_bootstrap_closure_attest(root, D0_08_SBOM_CLOSURE_ATTEST_RELATIVE)
    if payload is None:
        return False
    exact_values = {
        "schemaVersion": 1,
        "taskId": "TASK-D0-08",
        "kind": "sbom-closure-closure",
        "ruling": "GOV-PRECUTOVER-001",
        "selfTestResult": "ok",
        "freezePackage": (
            "docs/governance/task-freeze-packages/TASK-D0-08.json"),
        "docsCheckCommand": (
            "/usr/bin/python3 -I -S scripts/docs_check.py --root ."),
        "bootstrapAuthority": "deferred-fail-closed-to-D0-04",
    }
    for field, expected in exact_values.items():
        if payload.get(field) != expected:
            return False
    for field, needle in (
        ("selfTestCommand", "sbom_closure_self_test"),
    ):
        value = payload.get(field)
        if not isinstance(value, str) or needle not in value:
            return False
    freeze_digest = payload.get("freezePackageSha256")
    if (not isinstance(freeze_digest, str)
            or not re.fullmatch(r"[0-9a-f]{64}", freeze_digest)):
        return False
    freeze_path = root / exact_values["freezePackage"]
    try:
        ensure_repository_path(root, freeze_path, str(exact_values["freezePackage"]))
        freeze_bytes = read_repository_regular_bytes(
            root, freeze_path, str(exact_values["freezePackage"]))
        actual_freeze_digest = hashlib.sha256(freeze_bytes).hexdigest()
    except (DocsCheckError, OSError):
        return False
    if freeze_digest != actual_freeze_digest:
        return False
    notes = payload.get("notes")
    if (not isinstance(notes, str)
            or "not formal or hermetic evidence" not in notes):
        return False
    return True


def d0_09_linux_host_attested(root: Path) -> bool:
    """Return True only for GOV-PRECUTOVER-001 linux host profile attestation."""
    payload = _load_bootstrap_closure_attest(root, D0_09_LINUX_HOST_ATTEST_RELATIVE)
    if payload is None:
        return False
    exact_values = {
        "schemaVersion": 1,
        "taskId": "TASK-D0-09",
        "kind": "linux-host-profile-closure",
        "ruling": "GOV-PRECUTOVER-001",
        "selfTestResult": "ok",
        "validateResult": "ok",
        "laneResult": "ok",
        "darwinPreservation": "static-verified-byte-identical",
        "darwinLiveRegression": "deferred-p2-before-D0-07",
        "docsCheckCommand": (
            "/usr/bin/python3 -I -S scripts/docs_check.py --root ."),
        "bootstrapAuthority": "deferred-fail-closed-to-D0-04",
    }
    for field, expected in exact_values.items():
        if payload.get(field) != expected:
            return False
    for field, needle in (
        ("selfTestCommand", "host_profiles_self_test"),
        ("validateCommand", "toolchain_assets"),
    ):
        value = payload.get(field)
        if not isinstance(value, str) or needle not in value:
            return False
    notes = payload.get("notes")
    if (not isinstance(notes, str)
            or "not formal or hermetic evidence" not in notes):
        return False
    return True


def _verify_task_qualification_object_signatures(
    raw_bytes: bytes,
    obj: Any,
    policy: Any,
    statement_domain: bytes,
    signature_domain: bytes,
    bootstrap_consumer: Any,
) -> bool:
    """Verify Ed25519 signatures on a parsed task-qualification object.

    The signed object is canonical PF-JCS encoded with ``signatures`` replaced
    by the exact empty array. The statement digest is
    ``SHA-256(domain || NUL || canonical)`` and the Ed25519 message is
    ``domain || NUL || raw32(statement)``.
    """
    try:
        wire = json.loads(raw_bytes.decode("utf-8", errors="strict"))
        if not isinstance(wire, dict):
            return False
        if "signatures" not in wire or not isinstance(wire["signatures"], list):
            return False
        signatures = wire["signatures"]
        wire["signatures"] = []
        unsigned_bytes = bootstrap_consumer.canonical_pf_jcs(wire)
        statement = hashlib.sha256(statement_domain + b"\x00" + unsigned_bytes).digest()
        message = signature_domain + b"\x00" + statement
        principal_by_key = {principal.keyId: principal for principal in policy.principals}
        signed_roles: set[str] = set()
        signed_principals: set[str] = set()
        for sig in obj.signatures:
            principal = principal_by_key.get(sig.keyId)
            if principal is None:
                return False
            if not bootstrap_consumer.verify_ed25519(
                principal.publicKey, message, sig.signature
            ):
                return False
            signed_principals.add(principal.principalId)
            signed_roles.update(principal.roles)
        # SPEC-TASKQUAL-001 §1 fixed rule for task qualification objects.
        required = {"architecture", "quality", "security"}
        if not required.issubset(signed_roles):
            return False
        if len(signed_principals) < 3:
            return False
        return True
    except Exception:
        return False


def _content_ref_value_equal(left: object, right: object) -> bool:
    """Compare ContentRef-shaped records across exact-path module namespaces."""
    try:
        return (
            left.schema == right.schema
            and left.id == right.id
            and left.version == right.version
            and left.digest.algorithm == right.digest.algorithm
            and left.digest.bytes == right.digest.bytes
        )
    except AttributeError:
        return False


def _d0_10_structural_approval(root: Path) -> dict[str, Any] | None:
    """Verify D0-10's candidate-owned approval without claiming completion.

    This is the D-state structural consumer from SPEC-TASKQUAL-001 §8.5.  It
    verifies canonical bytes, the activated policy, A+Q+S signatures, the
    frozen package ref, and the one reserved Ledger ID.  Receipt/currentness
    authority remains external; absence of a bootstrap Ledger row is allowed
    only for this exact reserved ID.
    """
    bootstrap_consumer = _load_bootstrap_task_consumer()
    taskqual = _load_task_qualification_objects()
    if bootstrap_consumer is None or taskqual is None:
        return None
    approval_relative = (
        "docs/governance/task-qualifications/TASK-D0-10/bootstrap-approval.json"
    )
    policy_relative = (
        D0_04_BOOTSTRAP_ACTIVATION_BUNDLE_RELATIVE + "/authority-policy.json"
    )
    freeze_relative = "docs/governance/task-freeze-packages/TASK-D0-10.json"
    try:
        approval_bytes = read_repository_regular_bytes(
            root, root / approval_relative, approval_relative)
        policy_bytes = read_repository_regular_bytes(
            root, root / policy_relative, policy_relative)
        freeze_bytes = read_repository_regular_bytes(
            root, root / freeze_relative, freeze_relative)
        approval_wire = taskqual.decode_canonical_pf_jcs(approval_bytes)
        if taskqual.canonical_pf_jcs(approval_wire) != approval_bytes:
            return None
        approval = taskqual.parse_d0_10_bootstrap_approval(
            approval_wire, "bootstrapApproval")
        policy, policy_ref = bootstrap_consumer.parse_bootstrap_authority_policy(
            policy_bytes)
        if not _content_ref_value_equal(approval.authorityPolicy, policy_ref):
            return None
        if not _verify_task_qualification_object_signatures(
            approval_bytes, approval, policy,
            taskqual.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_STATEMENT,
            taskqual.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_SIGNATURE,
            bootstrap_consumer,
        ):
            return None
        if approval.taskId != "TASK-D0-10" or approval.taskRow.status != "in_progress":
            return None
        if approval.freezePackage.taskId != "TASK-D0-10":
            return None
        freeze_digest = taskqual.domain_digest_raw(
            taskqual.DOMAIN_TASK_FREEZE_PACKAGE_SOURCE, freeze_bytes)
        if approval.freezePackage.digest != freeze_digest:
            return None
        if approval.ledgerEvidenceId in approval.taskRow.evidenceIds:
            return None
        resulting_evidence = (
            tuple(approval.taskRow.evidenceIds) + (approval.ledgerEvidenceId,)
        )
        if resulting_evidence != tuple(sorted(resulting_evidence)):
            return None
        return {
            "approval": approval,
            "approvalBytes": approval_bytes,
            "reservedEvidenceId": approval.ledgerEvidenceId,
            "resultingEvidenceIds": resulting_evidence,
        }
    except Exception:
        return None


def d0_10_task_qualification_attested(root: Path) -> bool:
    """Return True only for a fully verified D0-10 task qualification closure.

    The D0-10 closure requires:
    - attest.json with exact fields per GOV-TASKQUAL-BOOTSTRAP-001
    - candidate-owned bootstrap-approval.json at the fixed path
    - external D0_10BootstrapReceiptV1
    - GovernanceBootstrapCompletionV1 for D0-10
    - all signatures verify against the activated D0-04 authority policy
    - cross-object joins (taskId, candidate identity, approval digest) hold
    """
    payload = _load_bootstrap_closure_attest(
        root, D0_10_TASK_QUALIFICATION_ATTEST_RELATIVE)
    if payload is None:
        return False
    expected_fields = {
        "schemaVersion",
        "taskId",
        "kind",
        "ruling",
        "freezePackage",
        "freezePackageSha256",
        "bootstrapApproval",
        "bootstrapApprovalSha256",
        "bootstrapReceipt",
        "bootstrapReceiptSha256",
        "governanceBootstrapCompletion",
        "governanceBootstrapCompletionSha256",
        "ledgerProjection",
        "ledgerProjectionSha256",
        "protectedReceiptAcceptanceSha256",
        "docsCheckCommand",
        "notes",
    }
    if set(payload) != expected_fields:
        return False
    exact_values: dict[str, Any] = {
        "schemaVersion": 1,
        "taskId": "TASK-D0-10",
        "kind": "d0-10-taskqual-one-time-bridge-closure",
        "ruling": "GOV-TASKQUAL-BOOTSTRAP-001",
        "freezePackage": "docs/governance/task-freeze-packages/TASK-D0-10.json",
        "bootstrapApproval": (
            "docs/governance/task-qualifications/TASK-D0-10/bootstrap-approval.json"
        ),
        "bootstrapReceipt": (
            "docs/governance/task-completions/TASK-D0-10/bootstrap-receipt.json"
        ),
        "governanceBootstrapCompletion": (
            "docs/governance/task-completions/TASK-D0-10/receipt.json"
        ),
        "ledgerProjection": (
            "docs/governance/task-completions/TASK-D0-10/ledger-projection.json"
        ),
        "docsCheckCommand": (
            "/usr/bin/python3 -I -S scripts/docs_check.py --root ."),
    }
    for field, expected in exact_values.items():
        if payload.get(field) != expected:
            return False
    notes = payload.get("notes")
    if (not isinstance(notes, str)
            or "not formal or hermetic evidence" not in notes):
        return False
    if not re.fullmatch(
            r"[0-9a-f]{64}", payload.get("protectedReceiptAcceptanceSha256", "")):
        return False

    # Load the pure bootstrap consumer and the typed task-qualification objects.
    bootstrap_consumer = _load_bootstrap_task_consumer()
    taskqual = _load_task_qualification_objects()
    if bootstrap_consumer is None or taskqual is None:
        return False

    # Load the activated D0-04 authority policy. D0-10 is not authorized
    # to substitute or relax this policy; the exact file from the activation
    # bundle is the only trust root for closure signatures.
    policy_path = root / D0_04_BOOTSTRAP_ACTIVATION_BUNDLE_RELATIVE / "authority-policy.json"
    policy_relative = D0_04_BOOTSTRAP_ACTIVATION_BUNDLE_RELATIVE + "/authority-policy.json"
    try:
        ensure_repository_path(root, policy_path, policy_relative)
        policy_bytes = policy_path.read_bytes()
        policy, policy_ref = bootstrap_consumer.parse_bootstrap_authority_policy(
            policy_bytes)
    except Exception:
        return False

    # Resolve the four fixed closure files referenced by the attest.
    approval_path = root / payload["bootstrapApproval"]
    receipt_path = root / payload["bootstrapReceipt"]
    completion_path = root / payload["governanceBootstrapCompletion"]
    ledger_path = root / payload["ledgerProjection"]
    freeze_path = root / payload["freezePackage"]
    try:
        artifact_paths = (
            approval_path, receipt_path, completion_path, ledger_path, freeze_path)
        for artifact_path in artifact_paths:
            ensure_repository_path(
                root, artifact_path, artifact_path.relative_to(root).as_posix())
        approval_bytes = approval_path.read_bytes()
        receipt_bytes = receipt_path.read_bytes()
        completion_bytes = completion_path.read_bytes()
        ledger_bytes = ledger_path.read_bytes()
        freeze_bytes = freeze_path.read_bytes()
    except Exception:
        return False

    # Attest hash claims must be plain SHA-256 of the exact file bytes.
    expected_hashes = {
        "freezePackage": freeze_bytes,
        "bootstrapApproval": approval_bytes,
        "bootstrapReceipt": receipt_bytes,
        "governanceBootstrapCompletion": completion_bytes,
        "ledgerProjection": ledger_bytes,
    }
    for stem, artifact_bytes in expected_hashes.items():
        if hashlib.sha256(artifact_bytes).hexdigest() != payload.get(f"{stem}Sha256"):
            return False

    # Parse the three signed objects and the closed Ledger projection. Any
    # non-canonical bytes, schema deviation, or structural drift fails closed.
    try:
        object_bytes = (
            approval_bytes, receipt_bytes, completion_bytes, ledger_bytes)
        decoded = tuple(
            taskqual.decode_canonical_pf_jcs(item) for item in object_bytes)
        if not all(isinstance(wire, dict) for wire in decoded):
            return False
        if any(
                taskqual.canonical_pf_jcs(wire) != raw
                for wire, raw in zip(decoded, object_bytes)):
            return False
        approval_wire, receipt_wire, completion_wire, ledger_wire = decoded
        approval = taskqual.parse_d0_10_bootstrap_approval(
            approval_wire, "bootstrapApproval")
        receipt = taskqual.parse_d0_10_bootstrap_receipt(
            receipt_wire, "bootstrapReceipt")
        completion = taskqual.parse_governance_bootstrap_completion(
            completion_wire, "governanceBootstrapCompletion")
        ledger = taskqual.parse_d0_10_receipt_ledger_projection(
            ledger_wire, "receiptLedgerProjection")
    except Exception:
        return False

    # Each object must point to the same activated authority policy.
    if not _content_ref_value_equal(approval.authorityPolicy, policy_ref):
        return False
    if not _content_ref_value_equal(receipt.authorityPolicy, policy_ref):
        return False
    if not _content_ref_value_equal(completion.authorityPolicy, policy_ref):
        return False

    # Recompute the approval digest before signature verification mutates the
    # parsed wire dict; the receipt must carry this exact digest.
    try:
        expected_approval_digest = taskqual.domain_digest(
            taskqual.DOMAIN_D0_10_BOOTSTRAP_APPROVAL, approval_wire)
        expected_receipt_digest = taskqual.domain_digest(
            taskqual.DOMAIN_D0_10_BOOTSTRAP_RECEIPT, receipt_wire)
        taskqual.domain_digest(
            taskqual.DOMAIN_D0_10_RECEIPT_LEDGER_PROJECTION, ledger_wire)
    except Exception:
        return False
    if receipt.approvalDigest != expected_approval_digest:
        return False

    # Verify Ed25519 signatures on all three objects.
    if not _verify_task_qualification_object_signatures(
        approval_bytes, approval, policy,
        taskqual.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_STATEMENT,
        taskqual.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_SIGNATURE,
        bootstrap_consumer,
    ):
        return False
    if not _verify_task_qualification_object_signatures(
        receipt_bytes, receipt, policy,
        taskqual.DOMAIN_D0_10_BOOTSTRAP_RECEIPT_STATEMENT,
        taskqual.DOMAIN_D0_10_BOOTSTRAP_RECEIPT_SIGNATURE,
        bootstrap_consumer,
    ):
        return False
    if not _verify_task_qualification_object_signatures(
        completion_bytes, completion, policy,
        taskqual.DOMAIN_GOVERNANCE_BOOTSTRAP_COMPLETION_STATEMENT,
        taskqual.DOMAIN_GOVERNANCE_BOOTSTRAP_COMPLETION_SIGNATURE,
        bootstrap_consumer,
    ):
        return False

    # Cross-object joins required by GOV-TASKQUAL-BOOTSTRAP-001.
    if approval.taskId != "TASK-D0-10":
        return False
    if receipt.taskId != "TASK-D0-10":
        return False
    if completion.taskId != "TASK-D0-10":
        return False
    if completion.rulingId != "GOV-TASKQUAL-BOOTSTRAP-001":
        return False
    if completion.purpose != "d0-10-taskqual-one-time-bridge":
        return False
    if receipt.ledgerGrade != "bootstrap":
        return False
    if receipt.purpose != "d0-10-taskqual-one-time-bridge":
        return False
    if completion.sourceClosure.path != (
        "docs/governance/task-completions/TASK-D0-10/bootstrap-receipt.json"
    ):
        return False
    if approval.preCloseCandidate != receipt.preCloseCandidate:
        return False
    if completion.completionCandidate != receipt.closeoutCandidate:
        return False
    if approval.allowedCloseoutPatch != receipt.allowedCloseoutPatch:
        return False
    if approval.ledgerEvidenceId != receipt.ledgerEvidenceId:
        return False
    if not approval.independentReviews or not completion.independentReviews:
        return False
    if approval.freezePackage.taskId != "TASK-D0-10":
        return False
    freeze_digest = taskqual.domain_digest_raw(
        taskqual.DOMAIN_TASK_FREEZE_PACKAGE_SOURCE, freeze_bytes)
    if approval.freezePackage.digest != freeze_digest:
        return False
    if completion.sourceClosure.digest.bytes != hashlib.sha256(receipt_bytes).digest():
        return False

    # The optional-P Ledger projection is fully derived from the two signed
    # objects and the verified ruling; it cannot introduce another authority.
    if ledger.evidenceId != approval.ledgerEvidenceId:
        return False
    if ledger.approvalRef.id != "d0-10-bootstrap-approval":
        return False
    if ledger.approvalRef.digest != expected_approval_digest:
        return False
    if ledger.receiptRef.id != receipt.id:
        return False
    if ledger.receiptRef.digest != expected_receipt_digest:
        return False
    if ledger.rulingRef != approval.ruling:
        return False

    # The human-readable Evidence Ledger row is an exact seven-column mirror
    # of the closed projection. No hidden column or alternate wording is
    # accepted for the reserved ID.
    evidence_relative = "docs/traceability/evidence-ledger.md"
    try:
        evidence_text = read_repository_regular_bytes(
            root, root / evidence_relative, evidence_relative).decode("utf-8")
    except Exception:
        return False
    expected_row = (
        f"| {ledger.evidenceId} | TASK-D0-10 | TST-DOC-001 | bootstrap | "
        f"protected receipt sha256:{expected_receipt_digest.bytes.hex()} | passed | "
        "GOV-TASKQUAL-BOOTSTRAP-001 one-time receipt projection |"
    )
    if sum(line == expected_row for line in evidence_text.splitlines()) != 1:
        return False

    return True


def _load_bootstrap_task_consumer() -> Any | None:
    """Load scripts/bootstrap_task_objects.py with exact-path discipline."""
    try:
        checker_path = Path(__file__).resolve(strict=True)
        tool_path = checker_path.with_name("bootstrap_task_objects.py")
        if tool_path.is_symlink() or not tool_path.is_file():
            return None
        exact_tool_path = tool_path.resolve(strict=True)
        if exact_tool_path != tool_path:
            return None
        spec = importlib.util.spec_from_file_location(
            "proof_forge_bootstrap_task_objects_for_docs_check",
            exact_tool_path,
        )
        if spec is None or spec.loader is None or spec.origin is None:
            return None
        if Path(spec.origin).resolve(strict=True) != exact_tool_path:
            return None
        module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
        for name in (
            "BootstrapDocumentSnapshotV1",
            "canonical_pf_jcs",
            "decode_canonical_pf_jcs",
            "parse_bootstrap_authority_policy",
            "parse_document_bound_required_test_set",
            "parse_task_approval",
            "parse_bootstrap_task_verifier_receipt",
            "parse_bootstrap_approval_set",
            "parse_bootstrap_approval_verifier_receipt",
            "parse_candidate_identity",
            "_preflight_eligible_stage0_handoff",
            "Rejected",
        ):
            if getattr(module, name, None) is None:
                return None
        return module
    except Exception:
        return None


def _load_task_qualification_objects() -> Any | None:
    """Load scripts/task_qualification_objects.py with exact-path discipline."""
    try:
        checker_path = Path(__file__).resolve(strict=True)
        tool_path = checker_path.with_name("task_qualification_objects.py")
        if tool_path.is_symlink() or not tool_path.is_file():
            return None
        exact_tool_path = tool_path.resolve(strict=True)
        if exact_tool_path != tool_path:
            return None
        # The object module imports its PF-JCS/value-object dependency by
        # module name. Under ``python -I -S script.py`` the script directory is
        # absent from sys.path, so inject only the exact-path-loaded bootstrap
        # module instead of relying on ambient import resolution.
        bootstrap_module = _load_bootstrap_task_consumer()
        if bootstrap_module is None:
            return None
        sys.modules["bootstrap_task_objects"] = bootstrap_module
        spec = importlib.util.spec_from_file_location(
            "proof_forge_task_qualification_objects_for_docs_check",
            exact_tool_path,
        )
        if spec is None or spec.loader is None or spec.origin is None:
            return None
        if Path(spec.origin).resolve(strict=True) != exact_tool_path:
            return None
        module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
        for name in (
            "D0_10BootstrapApprovalV1",
            "D0_10BootstrapReceiptV1",
            "GovernanceBootstrapCompletionV1",
            "D0_10ReceiptLedgerProjectionV1",
            "CandidateIdentity",
            "ContentRef",
            "parse_d0_10_bootstrap_approval",
            "parse_d0_10_bootstrap_receipt",
            "parse_governance_bootstrap_completion",
            "parse_d0_10_receipt_ledger_projection",
            "canonical_pf_jcs",
            "decode_canonical_pf_jcs",
            "domain_digest",
            "domain_digest_raw",
            "DOMAIN_TASK_FREEZE_PACKAGE_SOURCE",
            "DOMAIN_D0_10_BOOTSTRAP_APPROVAL_STATEMENT",
            "DOMAIN_D0_10_BOOTSTRAP_APPROVAL_SIGNATURE",
            "DOMAIN_D0_10_BOOTSTRAP_APPROVAL",
            "DOMAIN_D0_10_BOOTSTRAP_RECEIPT_STATEMENT",
            "DOMAIN_D0_10_BOOTSTRAP_RECEIPT_SIGNATURE",
            "DOMAIN_D0_10_BOOTSTRAP_RECEIPT",
            "DOMAIN_D0_10_RECEIPT_LEDGER_PROJECTION",
            "DOMAIN_GOVERNANCE_BOOTSTRAP_COMPLETION_STATEMENT",
            "DOMAIN_GOVERNANCE_BOOTSTRAP_COMPLETION_SIGNATURE",
        ):
            if getattr(module, name, None) is None:
                return None
        return module
    except Exception:
        return None


def _d0_04_bundle_file_bytes(root: Path, bundle_relative: str) -> dict[str, bytes] | None:
    """Read the exact 22-file activation closure bundle layout, fail closed."""
    expected = {
        "activation-receipt.json",
        "authority-policy.json",
        "bootstrap-approval-set.json",
        "candidate.json",
        "closure-manifest.json",
        "eligible-stage0-handoff.json",
        "host-observation.json",
        "phase5-snapshot.json",
        "required-test-set.json",
        "service-descriptor.json",
    }
    expected.update(
        f"approvals/task-d0-0{index}-approval.json" for index in range(1, 7))
    expected.update(
        f"receipts/task-d0-0{index}-receipt.json" for index in range(1, 7))
    bundle_dir = root / bundle_relative
    if bundle_dir.is_symlink() or not bundle_dir.is_dir():
        return None
    found: set[str] = set()
    for path in bundle_dir.rglob("*"):
        if path.is_symlink():
            return None
        if path.is_dir():
            continue
        if not path.is_file():
            return None
        found.add(path.relative_to(bundle_dir).as_posix())
    if found != expected:
        return None
    payload: dict[str, bytes] = {}
    try:
        for relative in sorted(expected):
            payload[relative] = read_repository_regular_bytes(
                root, bundle_dir / relative, f"{bundle_relative}/{relative}")
    except (DocsCheckError, OSError):
        return None
    return payload


def _d0_04_verify_activation_bundle(root: Path, payload: dict[str, Any]) -> bool:
    """Re-verify the real activation bundle with the bootstrap consumer.

    Mirrors the live checks of stage0_activate.py plus the closure-manifest
    digest bindings; every digest is recomputed from the bundle bytes and the
    current repo TCB files, so any post-ceremony drift fails closed.
    """
    consumer = _load_bootstrap_task_consumer()
    if consumer is None:
        return False
    bundle_relative = payload["bundlePath"]
    files = _d0_04_bundle_file_bytes(root, bundle_relative)
    if files is None:
        return False
    try:
        policy_bytes = files["authority-policy.json"]
        policy, policy_ref = consumer.parse_bootstrap_authority_policy(
            policy_bytes)
        # The required-set's PHASE-5 join binds the candidate-time snapshot
        # committed in the bundle: docs/05-test-spec.md is a living catalog
        # whose denominator the snapshot captures exactly; current-doc churn
        # must not invalidate the historical activation.
        snapshot_wire = json.loads(files["phase5-snapshot.json"].decode("utf-8"))
        if (type(snapshot_wire) is not dict
                or set(snapshot_wire) != {"id", "path", "bytesHex"}
                or snapshot_wire["id"] != "PHASE-5"
                or snapshot_wire["path"] != "docs/05-test-spec.md"
                or type(snapshot_wire["bytesHex"]) is not str):
            return False
        snapshot = consumer.BootstrapDocumentSnapshotV1(
            "PHASE-5", "docs/05-test-spec.md",
            bytes.fromhex(snapshot_wire["bytesHex"]))
        required_bytes = files["required-test-set.json"]
        _, required_ref = consumer.parse_document_bound_required_test_set(
            required_bytes, policy_bytes, snapshot)

        candidate_wire = json.loads(files["candidate.json"].decode("utf-8"))
        candidate = consumer.parse_candidate_identity(candidate_wire)
        if candidate.commit != payload["candidate"]:
            return False

        handoff_bytes = files["eligible-stage0-handoff.json"]
        handoff_preflight = consumer._preflight_eligible_stage0_handoff(
            handoff_bytes)
        handoff = handoff_preflight.handoff
        if handoff.authorityPolicy != policy_ref:
            return False
        if handoff.authorityStoreService != policy.authorityStoreService:
            return False
        if handoff.candidate != candidate:
            return False

        observation = json.loads(files["host-observation.json"].decode("utf-8"))
        if (type(observation) is not dict
                or observation.get("eligibleForHermetic") is not True):
            return False
        if handoff.hostObservation.digest.bytes != hashlib.sha256(
                files["host-observation.json"]).digest():
            return False

        descriptor_wire = json.loads(
            files["service-descriptor.json"].decode("utf-8"))
        if (type(descriptor_wire) is not dict
                or set(descriptor_wire) != {
                    "schema", "id", "version", "protocol",
                    "serviceExecutableDigest", "servicePublicKey",
                    "namespaceId", "maximumFrameBytes"}
                or descriptor_wire["schema"] != "proof-forge.authority-store-service.v1"
                or descriptor_wire["protocol"] != "pf.authority-store.rpc.v1"):
            return False
        descriptor_digest = hashlib.sha256(
            b"pf.authority-store-service.v1\x00"
            + consumer.canonical_pf_jcs(descriptor_wire)).digest()
        if policy.authorityStoreService.digest.bytes != descriptor_digest:
            return False
        if (policy.authorityStoreService.id != descriptor_wire["id"]
                or policy.authorityStoreService.version
                != descriptor_wire["version"]):
            return False

        def current_script_digest(relative: str) -> bytes:
            return hashlib.sha256(read_repository_regular_bytes(
                root, root / relative, relative)).digest()

        service_executable = current_script_digest(
            "scripts/stage0_store_service.py")
        if descriptor_wire["serviceExecutableDigest"] != (
                "sha256:" + service_executable.hex()):
            return False
        verifier_executable = current_script_digest("scripts/stage0_activate.py")
        if policy.verifier.executableDigest.bytes != verifier_executable:
            return False
        expected_tcb = (
            current_script_digest("scripts/verify_host_stage0.sh"),
            policy.verifier.executableDigest.bytes,
            current_script_digest("scripts/stage0_containment.py"),
            current_script_digest("scripts/gate_evidence.py"),
        )
        actual_tcb = (
            handoff.tcb.stage0VerifierDigest.bytes,
            handoff.tcb.bootstrapVerifierDigest.bytes,
            handoff.tcb.continuationDigest.bytes,
            handoff.tcb.formalFinalizerDigest.bytes,
        )
        if actual_tcb != expected_tcb:
            return False

        approval_bytes: dict[str, bytes] = {}
        receipt_bytes: dict[str, bytes] = {}
        receipt_refs = {}
        for task_id in D0_04_TOPOLOGICAL_TASK_IDS:
            task_approval_bytes = files[f"approvals/{task_id.lower()}-approval.json"]
            task_receipt_bytes = files[f"receipts/{task_id.lower()}-receipt.json"]
            approval, _ = consumer.parse_task_approval(
                task_approval_bytes, required_bytes, policy_bytes, snapshot)
            receipt, receipt_ref = (
                consumer.parse_bootstrap_task_verifier_receipt(
                    task_receipt_bytes, task_approval_bytes, required_bytes,
                    policy_bytes, snapshot, handoff_bytes))
            if receipt.dependencyCompletions != approval.dependencyCompletions:
                return False
            for completion in approval.dependencyCompletions:
                if receipt_refs.get(completion.taskId) != completion:
                    return False
            approval_bytes[task_id] = task_approval_bytes
            receipt_bytes[task_id] = task_receipt_bytes
            receipt_refs[receipt.taskId] = receipt_ref

        set_bytes = files["bootstrap-approval-set.json"]
        consumer.parse_bootstrap_approval_set(
            set_bytes,
            tuple(receipt_bytes[task_id] for task_id in D0_04_BOOTSTRAP_TASK_IDS),
            required_bytes, policy_bytes, snapshot, handoff_bytes)
        activation_bytes = files["activation-receipt.json"]
        activation, activation_ref = (
            consumer.parse_bootstrap_approval_verifier_receipt(
                activation_bytes, set_bytes,
                tuple(receipt_bytes[task_id]
                      for task_id in D0_04_BOOTSTRAP_TASK_IDS),
                required_bytes, policy_bytes, snapshot, handoff_bytes))
        if activation.id != payload["activationReceiptId"]:
            return False

        manifest_bytes = files["closure-manifest.json"]
        manifest = json.loads(manifest_bytes.decode("utf-8"))
        if (type(manifest) is not dict
                or set(manifest) != {
                    "schema", "authorityPolicy", "requiredTestSet",
                    "approvalSet", "stage0Handoff", "taskApprovals",
                    "taskReceipts", "activationReceipt"}
                or manifest["schema"]
                != "proof-forge.stage0-activation-closure-manifest.v1"):
            return False

        def domain_digest(domain: bytes, content: bytes) -> str:
            return "sha256:" + hashlib.sha256(domain + content).hexdigest()

        def ref_matches(section: Any, domain: bytes, content: bytes,
                        identifier: str, version: str, schema: str) -> bool:
            return (type(section) is dict
                    and section.get("schema") == schema
                    and section.get("id") == identifier
                    and section.get("version") == version
                    and section.get("digest") == domain_digest(domain, content))

        if not ref_matches(
                manifest["authorityPolicy"],
                b"pf.bootstrap-authority-policy.v1\x00", policy_bytes,
                policy_ref.id, policy_ref.version, policy_ref.schema):
            return False
        if not ref_matches(
                manifest["requiredTestSet"],
                b"pf.required-test-set.v1\x00", required_bytes,
                required_ref.id, required_ref.version, required_ref.schema):
            return False
        if not ref_matches(
                manifest["approvalSet"],
                b"pf.bootstrap-approval-set.v1\x00", set_bytes,
                "bootstrap-approval-set", "1.0.0",
                "proof-forge.bootstrap-approval-set.v1"):
            return False
        if not ref_matches(
                manifest["stage0Handoff"],
                b"pf.eligible-stage0-handoff.v1\x00", handoff_bytes,
                handoff.id, handoff.version, handoff.schema):
            return False
        task_approvals = manifest["taskApprovals"]
        task_receipts = manifest["taskReceipts"]
        if (type(task_approvals) is not list or type(task_receipts) is not list
                or len(task_approvals) != 6 or len(task_receipts) != 6):
            return False
        for index, task_id in enumerate(D0_04_BOOTSTRAP_TASK_IDS):
            approval_section = task_approvals[index]
            receipt_section = task_receipts[index]
            receipt_wire = consumer.decode_canonical_pf_jcs(
                receipt_bytes[task_id])
            if (type(approval_section) is not dict
                    or set(approval_section) != {"taskId", "digest"}
                    or approval_section["taskId"] != task_id
                    or approval_section["digest"] != domain_digest(
                        b"pf.bootstrap-task-approval.v1\x00",
                        approval_bytes[task_id])):
                return False
            if (type(receipt_section) is not dict
                    or set(receipt_section) != {"taskId", "id", "digest"}
                    or receipt_section["taskId"] != task_id
                    or receipt_section["id"] != receipt_wire["id"]
                    or receipt_section["digest"] != domain_digest(
                        b"pf.bootstrap-task-verifier-receipt.v1\x00",
                        receipt_bytes[task_id])):
                return False
        activation_section = manifest["activationReceipt"]
        if (type(activation_section) is not dict
                or set(activation_section) != {"id", "digest"}
                or activation_section["id"] != activation.id
                or activation_section["digest"]
                != "sha256:" + activation_ref.digest.bytes.hex()):
            return False
        return hashlib.sha256(
            manifest_bytes).hexdigest() == payload["closureManifestSha256"]
    except Exception:
        return False


def d0_04_bootstrap_activation_attested(root: Path) -> bool:
    """Return True only for a fully re-verified TASK-D0-04 activation closure."""
    payload = _load_bootstrap_closure_attest(
        root, D0_04_BOOTSTRAP_ACTIVATION_ATTEST_RELATIVE)
    if payload is None:
        return False
    expected_fields = {
        "schemaVersion",
        "taskId",
        "kind",
        "candidate",
        "activationReceiptId",
        "bundlePath",
        "closureManifestSha256",
        "freezePackage",
        "freezePackageSha256",
        "stage0FormalCommand",
        "stage0FormalResult",
        "rehearsalCommand",
        "rehearsalResult",
        "docsCheckCommand",
        "notes",
    }
    if set(payload) != expected_fields:
        return False
    exact_values: dict[str, Any] = {
        "schemaVersion": 1,
        "taskId": "TASK-D0-04",
        "kind": "bootstrap-activation-closure",
        "bundlePath": D0_04_BOOTSTRAP_ACTIVATION_BUNDLE_RELATIVE,
        "freezePackage": "docs/governance/task-freeze-packages/TASK-D0-04.json",
        "stage0FormalResult": "eligible",
        "rehearsalResult": "ok",
        "docsCheckCommand": (
            "/usr/bin/python3 -I -S scripts/docs_check.py --root ."),
    }
    for field, expected in exact_values.items():
        if payload.get(field) != expected:
            return False
    candidate = payload.get("candidate")
    if (not isinstance(candidate, str)
            or not re.fullmatch(r"[0-9a-f]{40}", candidate)):
        return False
    receipt_id = payload.get("activationReceiptId")
    if (not isinstance(receipt_id, str)
            or not re.fullmatch(r"BAV-[0-9]{8}-[0-9]{4}", receipt_id)):
        return False
    manifest_digest = payload.get("closureManifestSha256")
    if (not isinstance(manifest_digest, str)
            or not re.fullmatch(r"[0-9a-f]{64}", manifest_digest)):
        return False
    for field, needle in (
        ("stage0FormalCommand", "verify_host_stage0.sh --require-eligible"),
        ("rehearsalCommand", "bootstrap_acceptance_self_test.py"),
    ):
        value = payload.get(field)
        if not isinstance(value, str) or needle not in value:
            return False
    notes = payload.get("notes")
    if (not isinstance(notes, str)
            or "not formal or hermetic evidence" not in notes):
        return False
    freeze_digest = payload.get("freezePackageSha256")
    if (not isinstance(freeze_digest, str)
            or not re.fullmatch(r"[0-9a-f]{64}", freeze_digest)):
        return False
    freeze_path = root / exact_values["freezePackage"]
    try:
        ensure_repository_path(root, freeze_path, str(exact_values["freezePackage"]))
        freeze_bytes = read_repository_regular_bytes(
            root, freeze_path, str(exact_values["freezePackage"]))
        actual_freeze_digest = hashlib.sha256(freeze_bytes).hexdigest()
    except (DocsCheckError, OSError):
        return False
    if freeze_digest != actual_freeze_digest:
        return False
    return _d0_04_verify_activation_bundle(root, payload)


def _d0_07_replay_report_verified(report: object) -> bool:
    """Verify the committed genesis replay report shape and all-green legs."""
    if type(report) is not dict:
        return False
    if report.get("schema") != D0_07_GENESIS_REPORT_SCHEMA:
        return False
    if report.get("overallStatus") != "passed":
        return False
    legs = report.get("legs")
    if type(legs) is not list or len(legs) != len(D0_07_GENESIS_TST_IDS):
        return False
    tst_ids = tuple(
        leg.get("tstId") for leg in legs if type(leg) is dict
    )
    if tst_ids != D0_07_GENESIS_TST_IDS:
        return False
    for leg in legs:
        commands = leg.get("commands")
        if type(commands) is not list or not commands:
            return False
        for command in commands:
            if type(command) is not dict or command.get("status") != "passed":
                return False
    return True


def d0_07_fixture_acceptance_attested(root: Path) -> bool:
    """Return True only for a fully verified D0-07 fixture acceptance closure."""
    payload = _load_bootstrap_closure_attest(
        root, D0_07_FIXTURE_ACCEPTANCE_ATTEST_RELATIVE)
    if payload is None:
        return False
    expected_fields = {
        "schemaVersion",
        "taskId",
        "kind",
        "ruling",
        "freezePackage",
        "freezePackageSha256",
        "genesisReplayReport",
        "genesisReplayReportSha256",
        "darwinLiveReobservation",
        "d003DeferredClearance",
        "fixtureEvidenceEvidence",
        "cleanRoomEvidence",
        "docsCheckCommand",
        "notes",
    }
    if set(payload) != expected_fields:
        return False
    exact_values: dict[str, Any] = {
        "schemaVersion": 1,
        "taskId": "TASK-D0-07",
        "kind": "d0-07-fixture-acceptance-closure",
        "ruling": "GOV-D0CLOSE-001",
        "freezePackage": "docs/governance/task-freeze-packages/TASK-D0-07.json",
        "genesisReplayReport": D0_07_GENESIS_REPLAY_REPORT_RELATIVE,
        "d003DeferredClearance": "EV-20260719-0117",
        "fixtureEvidenceEvidence": "EV-20260719-0113",
        "cleanRoomEvidence": "EV-20260719-0115",
        "docsCheckCommand": (
            "/usr/bin/python3 -I -S scripts/docs_check.py --root ."),
    }
    for field, expected in exact_values.items():
        if payload.get(field) != expected:
            return False
    darwin = payload.get("darwinLiveReobservation")
    if not isinstance(darwin, str) or "darwin-arm64-" not in darwin:
        return False
    notes = payload.get("notes")
    if (not isinstance(notes, str)
            or "not formal or hermetic evidence" not in notes):
        return False
    freeze_digest = payload.get("freezePackageSha256")
    if (not isinstance(freeze_digest, str)
            or not re.fullmatch(r"[0-9a-f]{64}", freeze_digest)):
        return False
    freeze_path = root / exact_values["freezePackage"]
    try:
        ensure_repository_path(root, freeze_path, str(exact_values["freezePackage"]))
        freeze_bytes = read_repository_regular_bytes(
            root, freeze_path, str(exact_values["freezePackage"]))
        actual_freeze_digest = hashlib.sha256(freeze_bytes).hexdigest()
    except (DocsCheckError, OSError):
        return False
    if freeze_digest != actual_freeze_digest:
        return False
    replay_digest = payload.get("genesisReplayReportSha256")
    if (not isinstance(replay_digest, str)
            or not re.fullmatch(r"[0-9a-f]{64}", replay_digest)):
        return False
    replay_relative = exact_values["genesisReplayReport"]
    try:
        report_bytes = read_repository_regular_bytes(
            root, root / replay_relative, replay_relative)
    except (DocsCheckError, OSError):
        return False
    if hashlib.sha256(report_bytes).hexdigest() != replay_digest:
        return False
    try:
        report = json.loads(report_bytes.decode("utf-8", errors="strict"))
    except (UnicodeError, json.JSONDecodeError):
        return False
    return _d0_07_replay_report_verified(report)


def validate_tasks(root: Path, definitions: dict[str, Definition], tasks: list[TaskRecord],
                   evidence_records: dict[str, EvidenceRecord],
                   document_status: dict[str, str],
                   genesis_effective: bool) -> None:
    tasks_by_id = {task.identifier: task for task in tasks}
    diagnostics: list[OrderedDiagnostic] = []
    d0_10_structural = _d0_10_structural_approval(root)

    def add_task_error(task: TaskRecord, code: str, detail: str,
                       identifier: str | None = None) -> None:
        error = DocsCheckError(code, task.relative, detail)
        diagnostics.append(OrderedDiagnostic(
            task.relative, task.line, 1, identifier or task.identifier, error))

    for record in sorted(evidence_records.values(),
                         key=lambda item: (item.relative, item.line, item.identifier)):
        if record.grade == "formal":
            error = DocsCheckError(
                "PF-DOC-EVIDENCE-FORMAL-UNVERIFIED", record.relative,
                f"{record.identifier} cannot claim formal before the D0-07 "
                "formal finalizer and candidate-bound evidence-set binder exist")
            diagnostics.append(OrderedDiagnostic(
                record.relative, record.line, 1, record.identifier, error))
        bootstrap_tasks = {
            "TASK-D0-01", "TASK-D0-02", "TASK-D0-03",
            "TASK-D0-04", "TASK-D0-05", "TASK-D0-06",
            "TASK-D0-07", "TASK-D0-08", "TASK-D0-09", "TASK-D0-10",
        }
        if record.grade == "bootstrap" and record.task not in bootstrap_tasks:
            error = DocsCheckError(
                "PF-DOC-EVIDENCE-SCHEMA", record.relative,
                f"{record.identifier} uses bootstrap grade outside the exact D0 trust-root set")
            diagnostics.append(OrderedDiagnostic(
                record.relative, record.line, 1, record.identifier, error))
        elif record.grade == "bootstrap":
            # Freeze exceptions: D0-01 pure-consumer and D0-02 package-boundary may close
            # without protected receipt lookup. GOV-PRECUTOVER-001 adds attested D0-08/D0-09.
            # TASK-D0-04 closes only with the fully re-verified real activation bundle.
            # TASK-D0-07 closes only with the GOV-D0CLOSE-001 fixture acceptance evidence.
            # Other D0 trust-root tasks remain zero-closure.
            allowed = (
                (record.task == "TASK-D0-01" and d0_01_pure_consumer_attested(root))
                or (record.task == "TASK-D0-02" and d0_02_package_boundary_attested(root))
                or (record.task == "TASK-D0-03" and d0_03_development_triad_attested(root))
                or (record.task == "TASK-D0-04" and d0_04_bootstrap_activation_attested(root))
                or (record.task == "TASK-D0-05" and d0_05_sbom_inventory_attested(root))
                or (record.task == "TASK-D0-06"
                    and genesis_effective
                    and d0_06_common_primitives_attested(root, evidence_records))
                or (record.task == "TASK-D0-07" and d0_07_fixture_acceptance_attested(root))
                or (record.task == "TASK-D0-08" and d0_08_sbom_closure_attested(root))
                or (record.task == "TASK-D0-09" and d0_09_linux_host_attested(root))
                or (record.task == "TASK-D0-10" and d0_10_task_qualification_attested(root))
            )
            if not allowed:
                error = DocsCheckError(
                    "PF-DOC-EVIDENCE-BOOTSTRAP-UNVERIFIED", record.relative,
                    f"{record.identifier} cannot close {record.task} before the external "
                    "TaskApprovalV1/BootstrapTaskVerifierReceiptV1 verifier and immutable "
                    "receipt lookup exist")
                diagnostics.append(OrderedDiagnostic(
                    record.relative, record.line, 1, record.identifier, error))
        if record.task is None:
            continue
        task = tasks_by_id.get(record.task)
        if task is None:
            error = DocsCheckError(
                "PF-DOC-ID-UNKNOWN", record.relative,
                f"{record.identifier} binds unknown {record.task}")
            diagnostics.append(OrderedDiagnostic(
                record.relative, record.line, 1, record.task, error))
            continue
        owned = set(task.tests)
        for test in record.tests:
            definition = definitions.get(test)
            if definition is None or definition.kind != "test":
                error = DocsCheckError(
                    "PF-DOC-ID-UNKNOWN", record.relative,
                    f"{record.identifier} references unknown {test}")
                diagnostics.append(OrderedDiagnostic(
                    record.relative, record.line, 1, test, error))
            elif test not in owned:
                error = DocsCheckError(
                    "PF-DOC-DONE-EV", record.relative,
                    f"{record.identifier} test {test} is not owned by {record.task}")
                diagnostics.append(OrderedDiagnostic(
                    record.relative, record.line, 1, test, error))

    for task in sorted(tasks, key=lambda item: (item.relative, item.line, item.identifier)):
        for dependency in task.dependencies:
            definition = definitions.get(dependency)
            if dependency not in tasks_by_id or definition is None or definition.kind != "task":
                add_task_error(
                    task, "PF-DOC-ID-UNKNOWN",
                    f"task {task.identifier} references unknown {dependency}", dependency)
        for prerequisite, required_status in task.prerequisites:
            definition = definitions.get(prerequisite)
            if (definition is None or definition.kind not in DOCUMENT_KINDS
                    or prerequisite not in document_status):
                add_task_error(
                    task, "PF-DOC-ID-UNKNOWN",
                    f"task {task.identifier} references unknown prerequisite {prerequisite}",
                    prerequisite)
            elif (task.status == "done"
                    and document_status[prerequisite] != required_status):
                add_task_error(
                    task, "PF-DOC-TASK-DEPENDENCY",
                    f"task {task.identifier} requires {prerequisite}@{required_status}, "
                    f"got {document_status[prerequisite]}", prerequisite)

        if task.status in {"in_progress", "done"}:
            for dependency in task.dependencies:
                dependency_task = tasks_by_id.get(dependency)
                if dependency_task is not None and dependency_task.status != "done":
                    add_task_error(
                        task, "PF-DOC-TASK-DEPENDENCY",
                        f"task {task.identifier} depends on unfinished {dependency}", dependency)
        if task.status == "done" and not task.tests:
            add_task_error(task, "PF-DOC-DONE-TST",
                           f"done task {task.identifier} has no TST")
        for test in task.tests:
            definition = definitions.get(test)
            if definition is None or definition.kind != "test":
                code = "PF-DOC-DONE-TST" if task.status == "done" else "PF-DOC-ID-UNKNOWN"
                add_task_error(task, code,
                               f"task {task.identifier} references unknown {test}", test)
        if task.status == "done" and not task.evidence:
            add_task_error(task, "PF-DOC-DONE-EV",
                           f"done task {task.identifier} has no EV")
        if task.status == "done" and task.identifier == "TASK-D0-10":
            if d0_10_structural is None:
                add_task_error(
                    task, "PF-DOC-D0-10-STRUCTURAL",
                    "TASK-D0-10 done requires its verified candidate-owned bootstrap approval")
            elif task.evidence != d0_10_structural["resultingEvidenceIds"]:
                add_task_error(
                    task, "PF-DOC-D0-10-STRUCTURAL",
                    "TASK-D0-10 evidence IDs must equal C development IDs plus the "
                    "single signed reserved Ledger ID")

        covered_tests: set[str] = set()
        for evidence in task.evidence:
            record = evidence_records.get(evidence)
            definition = definitions.get(evidence)
            if record is None or definition is None or definition.kind != "evidence":
                is_reserved_d0_10 = (
                    task.status == "done"
                    and task.identifier == "TASK-D0-10"
                    and d0_10_structural is not None
                    and evidence == d0_10_structural["reservedEvidenceId"]
                )
                if is_reserved_d0_10:
                    # D state: the signed ID is reserved but the external
                    # receipt projection has not yet been mirrored into P.
                    continue
                code = "PF-DOC-DONE-EV" if task.status == "done" else "PF-DOC-ID-UNKNOWN"
                add_task_error(task, code,
                               f"task {task.identifier} references unknown {evidence}", evidence)
                continue
            if record.task != task.identifier:
                add_task_error(
                    task, "PF-DOC-DONE-EV",
                    f"{evidence} is bound to {record.task or 'no task'}, not {task.identifier}",
                    evidence)
                continue
            covered_tests.update(record.tests)
            if task.status == "done":
                if is_frozen_a0_task(task.identifier):
                    required_grade = "development"
                elif task.identifier == "TASK-D0-10":
                    if (d0_10_structural is not None
                            and evidence == d0_10_structural["reservedEvidenceId"]):
                        required_grade = "bootstrap"
                    else:
                        required_grade = "development"
                elif task.identifier in {
                    "TASK-D0-01", "TASK-D0-02", "TASK-D0-03",
                    "TASK-D0-04", "TASK-D0-05", "TASK-D0-06",
                    "TASK-D0-07", "TASK-D0-08", "TASK-D0-09",
                }:
                    required_grade = "bootstrap"
                else:
                    required_grade = "formal"
                if record.grade != required_grade:
                    add_task_error(
                        task, "PF-DOC-DONE-EV",
                        f"{evidence} for {task.identifier} requires {required_grade}, "
                        f"got {record.grade}",
                        evidence)
                if not re.fullmatch(r"passed(?: \([^()]+\))?", record.result):
                    add_task_error(
                        task, "PF-DOC-DONE-EV",
                        f"{evidence} for {task.identifier} is not passed: {record.result}",
                        evidence)
        if task.status == "done":
            missing_tests = sorted(set(task.tests) - covered_tests)
            if missing_tests:
                add_task_error(
                    task, "PF-DOC-DONE-EV",
                    f"task {task.identifier} evidence does not cover {', '.join(missing_tests)}",
                    missing_tests[0])

    unseen, active_state, done_state = 0, 1, 2
    state = {identifier: unseen for identifier in tasks_by_id}
    ordered_tasks = sorted(
        tasks_by_id,
        key=lambda identifier: (
            tasks_by_id[identifier].relative,
            tasks_by_id[identifier].line,
            identifier,
        ),
    )
    for start in ordered_tasks:
        if state[start] != unseen:
            continue
        stack: list[tuple[str, int, tuple[str, ...]]] = [
            (start, 0, tuple(sorted(
                dependency for dependency in tasks_by_id[start].dependencies
                if dependency in tasks_by_id))),
        ]
        path: list[str] = []
        active_index: dict[str, int] = {}
        while stack:
            identifier, next_dependency, dependencies = stack[-1]
            if state[identifier] == unseen:
                state[identifier] = active_state
                active_index[identifier] = len(path)
                path.append(identifier)
            if next_dependency < len(dependencies):
                dependency = dependencies[next_dependency]
                stack[-1] = (identifier, next_dependency + 1, dependencies)
                if state[dependency] == unseen:
                    stack.append((
                        dependency,
                        0,
                        tuple(sorted(
                            child for child in tasks_by_id[dependency].dependencies
                            if child in tasks_by_id)),
                    ))
                elif state[dependency] == active_state:
                    cycle = path[active_index[dependency]:] + [dependency]
                    task = tasks_by_id[dependency]
                    add_task_error(task, "PF-DOC-TASK-CYCLE", " -> ".join(cycle),
                                   dependency)
                continue
            stack.pop()
            path.pop()
            active_index.pop(identifier)
            state[identifier] = done_state

    active = sorted(task.identifier for task in tasks if task.status == "in_progress")
    if len(active) > 1:
        active_tasks = sorted(
            (tasks_by_id[identifier] for identifier in active),
            key=lambda item: (item.relative, item.line, item.identifier))
        first = active_tasks[0]
        add_task_error(first, "PF-DOC-TASK-ACTIVE",
                       f"multiple in_progress tasks: {', '.join(active)}")
    raise_first(diagnostics)


def validate_agents_checkpoint(root: Path, tasks: list[TaskRecord]) -> None:
    agents_path = root / "AGENTS.md"
    ensure_repository_path(root, agents_path, "AGENTS.md")
    if not agents_path.is_file():
        raise_error("PF-DOC-CHECKPOINT", "AGENTS.md", "required checkpoint file is missing")
    text = read_repository_text(
        root, agents_path, "AGENTS.md", encoding_code="PF-DOC-CHECKPOINT")

    lines = text.splitlines()
    visible_lines = mask_nonrendered(text).splitlines()
    checkpoint_headings = [
        index for index, line in enumerate(visible_lines)
        if line.strip() == "## Current Checkpoint"
    ]
    if len(checkpoint_headings) != 1:
        raise_error(
            "PF-DOC-CHECKPOINT", "AGENTS.md",
            "requires exactly one rendered ## Current Checkpoint section")
    checkpoint_heading = checkpoint_headings[0]
    section_end = next(
        (
            index for index in range(checkpoint_heading + 1, len(visible_lines))
            if re.match(r"^#{1,2}\s+", visible_lines[index].strip())
        ),
        len(visible_lines),
    )
    checkpoint_headers = [
        index for index, line in enumerate(visible_lines)
        if line.strip() == "| Field | Current value |"
    ]
    if len(checkpoint_headers) != 1:
        raise_error(
            "PF-DOC-CHECKPOINT", "AGENTS.md",
            "requires exactly one rendered canonical Field/Current value table")
    header = checkpoint_headers[0]
    if not checkpoint_heading < header < section_end:
        raise_error(
            "PF-DOC-CHECKPOINT", "AGENTS.md",
            "canonical Field/Current value table must be inside Current Checkpoint")
    if header + 1 >= len(lines) or lines[header + 1].strip() != "|---|---|":
        raise_error("PF-DOC-CHECKPOINT", "AGENTS.md",
                    "Current Checkpoint lacks canonical separator")

    fields: dict[str, str] = {}
    for line in lines[header + 2:]:
        if not line.startswith("|"):
            break
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) != 2 or not cells[0]:
            raise_error("PF-DOC-CHECKPOINT", "AGENTS.md",
                        f"invalid checkpoint row {line}")
        if cells[0] in fields:
            raise_error("PF-DOC-CHECKPOINT", "AGENTS.md",
                        f"duplicate checkpoint field {cells[0]}")
        fields[cells[0]] = cells[1]

    for field in ("Active task", "Next task", "Known blocker",
                  "Task authority", "Document authority"):
        if field not in fields:
            raise_error("PF-DOC-CHECKPOINT", "AGENTS.md",
                        f"missing checkpoint field {field}")

    def checkpoint_task_ids(field: str) -> set[str]:
        return set(re.findall(
            r"(?<![A-Za-z0-9_-])TASK-[A-Z0-9]+-[0-9]+(?![A-Za-z0-9_-])",
            fields[field],
        ))

    active = [task.identifier for task in tasks if task.status == "in_progress"]
    expected_active = set(active)
    actual_active = checkpoint_task_ids("Active task")
    if actual_active != expected_active or (not expected_active and "无" not in fields["Active task"]):
        raise_error("PF-DOC-CHECKPOINT", "AGENTS.md",
                    f"Active task mirrors {sorted(actual_active)}, expected {sorted(expected_active)}")

    if active:
        active_index = next(index for index, task in enumerate(tasks)
                            if task.identifier == active[0])
        remaining = [task for task in tasks[active_index + 1:]
                     if task.status != "done"]
    else:
        remaining = [task for task in tasks if task.status != "done"]
    expected_next = {remaining[0].identifier} if remaining else set()
    actual_next = checkpoint_task_ids("Next task")
    if actual_next != expected_next or (not expected_next and "无" not in fields["Next task"]):
        raise_error("PF-DOC-CHECKPOINT", "AGENTS.md",
                    f"Next task mirrors {sorted(actual_next)}, expected {sorted(expected_next)}")

    expected_blocked = {task.identifier for task in tasks if task.status == "blocked"}
    actual_blocked = checkpoint_task_ids("Known blocker")
    if (actual_blocked != expected_blocked
            or (not expected_blocked and "无" not in fields["Known blocker"])):
        raise_error("PF-DOC-CHECKPOINT", "AGENTS.md",
                    f"Known blocker mirrors {sorted(actual_blocked)}, "
                    f"expected {sorted(expected_blocked)}")

    def checkpoint_authority_target(field: str, expected: str) -> None:
        value = fields[field]
        links = list(INLINE_LINK_RE.finditer(value))
        if links:
            if len(links) != 1 or links[0].group(1):
                raise_error(
                    "PF-DOC-CHECKPOINT", "AGENTS.md",
                    f"{field} must contain exactly one non-image inline link")
            actual = links[0].group(2).strip().strip("<>")
        else:
            actual = clean_cell(value)
        if actual != expected:
            raise_error(
                "PF-DOC-CHECKPOINT", "AGENTS.md",
                f"{field} must point exactly to {expected}")

    checkpoint_authority_target("Task authority", "docs/04-task-breakdown.md")
    checkpoint_authority_target("Document authority", "docs/document-status.md")


def check(root: Path, profile: str = "development") -> None:
    if profile != "development":
        raise ValueError(f"unknown docs-check profile: {profile}")
    root_input = root.expanduser().absolute()
    for component in (root_input, *root_input.parents):
        if component.is_symlink():
            raise_error("PF-DOC-PATH", ".",
                        f"repository root has symlink component {component.as_posix()}")
    root = root_input.resolve()
    docs_root = root / "docs"
    ensure_repository_path(root, docs_root, "docs")
    if not docs_root.is_dir():
        raise_error("PF-DOC-REQUIRED", "docs", "docs/ does not exist")
    required_paths = [item for item in REQUIRED if item != "governance/task-set.lock.json"]
    for required in sorted(required_paths):
        required_path = docs_root / required
        ensure_repository_path(root, required_path, f"docs/{required}")
        if not required_path.is_file():
            raise_error("PF-DOC-REQUIRED", f"docs/{required}", "required document is missing")
    ensure_no_tree_symlinks(root, docs_root)
    present_targets = {path.name for path in (docs_root / "targets").glob("*.md")}
    missing_targets = sorted(TARGETS - present_targets)
    if missing_targets:
        raise_error("PF-DOC-REQUIRED", "docs/targets", f"missing target dossiers {missing_targets}")

    json_values: dict[str, Any] = {}
    documents: list[Document] = []
    by_id: dict[str, Document] = {}
    corpus_paths = sorted([
        *docs_root.rglob("*.json"),
        *docs_root.rglob("*.md"),
    ], key=lambda path: relative(root, path))
    for path in corpus_paths:
        relative_path = relative(root, path)
        ensure_repository_path(root, path, relative_path)
        if path.suffix == ".json":
            # GenesisRootPolicyV1 has a dedicated bounded O_NOFOLLOW reader.
            # Never touch it first through the generic unbounded text loader:
            # a FIFO or mutable hardlink must reach only the exact validator.
            if relative_path == GENESIS_ROOT_POLICY_RELATIVE:
                continue
            json_values[relative_path] = load_json(root, path)
            continue
        text = read_repository_text(root, path, relative_path)
        meta = parse_frontmatter(root, path, text)
        document = Document(path.resolve(), relative_path, text, meta)
        by_id.setdefault(meta["id"], document)
        documents.append(document)

    validate_sol_cpi_contract(root, json_values, by_id)
    validate_solana_cpi_active_contract(root, by_id)
    validate_solana_cpi_epic_checkpoint(root)
    validate_pf_assets_extension_contract(root, json_values)
    check_links(root, docs_root, documents, by_id)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT,
                        help="repository root containing docs/")
    arguments = parser.parse_args()
    try:
        check(arguments.root)
    except DocsCheckError as error:
        print(f"docs-check: {error.render()}", file=sys.stderr)
        raise SystemExit(1)
    print("docs-check: development ok")


if __name__ == "__main__":
    main()
