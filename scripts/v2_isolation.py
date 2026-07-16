#!/usr/bin/env python3
"""Focused, portable product-tree checker for ``TST-ISO-001``.

The caller supplies an already extracted product snapshot.  Host eligibility,
tool closure, sandboxing, and formal evidence are deliberately out of scope.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import stat
import sys
import unicodedata
from pathlib import Path
from typing import NoReturn


MAX_FILES = 10_000
MAX_TEXT_BYTES = 4 * 1024 * 1024
MAX_TOTAL_SOURCE_BYTES = 64 * 1024 * 1024
MAX_GIT_TREE_BYTES = 16 * 1024 * 1024
REQUIRED_FILES = (
    "lakefile.lean",
    "lake-manifest.json",
    "lean-toolchain",
    "justfile",
    "ProofForgeV2.lean",
    "ProofForgeV2/CLI/Main.lean",
)
FORBIDDEN_TOP_LEVEL = {".git", ".lake", "active", "build", "new_design"}
FORBIDDEN_TOP_LEVEL_CASEFOLD = {name.casefold() for name in FORBIDDEN_TOP_LEVEL}
FORBIDDEN_PRODUCT_SUFFIXES = {
    ".a", ".bin", ".dylib", ".exe", ".ilean", ".o", ".olean",
    ".pyc", ".so", ".wasm",
}
TOOLCHAIN_RE = re.compile(r"leanprover/lean4:v[0-9]+\.[0-9]+\.[0-9]+\n")
LEGACY_NAME_RE = re.compile(r"\bProofForge(?!(?:V2(?:\.|\b)|V2Tests\b))")
ACTIVE_IMPORT_RE = re.compile(
    r"(?m)^[ \t]*(?:public[ \t\r\n]+)?import[ \t\r\n]+"
    r"(?:active|«active»)(?:\.|[ \t]*$)"
)
REMOTE_GIT_URL_RE = re.compile(
    r"(?:https?://|ssh://|git://)[^/\s][^\s]*|"
    r"[A-Za-z0-9._-]+@[A-Za-z0-9.-]+:[^\s]+"
)
TEXT_PRODUCT_SUFFIXES = {
    ".excalidraw", ".gitignore", ".in", ".json", ".lean", ".lock", ".md",
    ".py", ".sh", ".toml", ".yaml", ".yml",
}
TEXT_PRODUCT_NAMES = {"justfile", "lean-toolchain"}


class IsolationError(RuntimeError):
    def __init__(self, code: str, detail: str) -> None:
        super().__init__(detail)
        self.code = code
        self.detail = detail


def fail(code: str, detail: str) -> NoReturn:
    raise IsolationError(code, detail)


def _read_text(path: Path, label: str) -> str:
    try:
        metadata = os.stat(path, follow_symlinks=False)
    except OSError as error:
        fail("PF-ISO-IO", f"cannot stat {label}: {error}")
    if (not stat.S_ISREG(metadata.st_mode)
            or metadata.st_nlink != 1
            or not 1 <= metadata.st_size <= MAX_TEXT_BYTES):
        fail("PF-ISO-FILE", f"{label} must be a non-empty single-link regular file")
    try:
        data = path.read_bytes()
    except OSError as error:
        fail("PF-ISO-IO", f"cannot read {label}: {error}")
    if len(data) != metadata.st_size or b"\x00" in data or b"\r" in data:
        fail("PF-ISO-FILE", f"{label} has unstable or forbidden bytes")
    try:
        return data.decode("utf-8", errors="strict")
    except UnicodeError:
        fail("PF-ISO-ENCODING", f"{label} is not strict UTF-8")


def _decode_json(path: Path) -> object:
    text = _read_text(path, path.name)

    def pairs(values: list[tuple[str, object]]) -> dict[str, object]:
        result: dict[str, object] = {}
        for key, value in values:
            if key in result:
                fail("PF-ISO-MANIFEST", f"duplicate manifest key: {key}")
            result[key] = value
        return result

    try:
        return json.loads(text, object_pairs_hook=pairs)
    except (json.JSONDecodeError, UnicodeError) as error:
        fail("PF-ISO-MANIFEST", f"invalid lake-manifest.json: {error}")


def _strip_lean_comments(text: str, *, mask_strings: bool = False) -> str:
    output: list[str] = []
    index = 0
    block_depth = 0
    in_string = False
    escaped = False
    while index < len(text):
        pair = text[index:index + 2]
        character = text[index]
        if block_depth:
            if pair == "/-":
                block_depth += 1
                output.extend("  ")
                index += 2
            elif pair == "-/":
                block_depth -= 1
                output.extend("  ")
                index += 2
            else:
                output.append("\n" if character == "\n" else " ")
                index += 1
            continue
        if in_string:
            output.append(
                "\n" if character == "\n" else
                " " if mask_strings else
                character
            )
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                in_string = False
            index += 1
            continue
        if pair == "--":
            newline = text.find("\n", index + 2)
            if newline < 0:
                output.extend(" " * (len(text) - index))
                break
            output.extend(" " * (newline - index))
            output.append("\n")
            index = newline + 1
            continue
        if pair == "/-":
            block_depth = 1
            output.extend("  ")
            index += 2
            continue
        if character == '"':
            in_string = True
        output.append(character)
        index += 1
    if block_depth or in_string:
        fail("PF-ISO-LAKEFILE", "lakefile.lean has an unterminated comment or string")
    return "".join(output)


def _declaration_block(code: str, kind: str, name: str) -> str:
    header = re.compile(
        rf"(?m)^(?:{re.escape(kind)})[ \t]+{re.escape(name)}[ \t]+where[ \t]*$"
    )
    matches = tuple(header.finditer(code))
    if len(matches) != 1:
        fail("PF-ISO-LAKEFILE", f"expected exactly one {kind} {name} declaration")
    start = matches[0].end()
    lines = code[start:].splitlines(keepends=True)
    block: list[str] = []
    for line in lines:
        if line.strip() and not line[0].isspace():
            break
        block.append(line)
    return "".join(block)


def _unquote_identifier(name: str) -> str:
    if len(name) >= 2 and name.startswith("«") and name.endswith("»"):
        return name[1:-1]
    return name


def _check_lakefile(root: Path) -> None:
    source = _read_text(root / "lakefile.lean", "lakefile.lean")
    code = _strip_lean_comments(source)
    package_headers = re.findall(r"(?m)^package[ \t]+([^ \t]+)[ \t]+where[ \t]*$", code)
    if package_headers != ["«proof-forge-next»"]:
        fail("PF-ISO-PACKAGE", "Lake package must be exactly proof-forge-next")
    library_headers = re.findall(
        r"(?m)^lean_lib[ \t]+([^ \t]+)[ \t]+where[ \t]*$", code
    )
    if library_headers.count("ProofForgeV2") != 1:
        fail("PF-ISO-NAMESPACE", "expected exactly one ProofForgeV2 library")
    for name in library_headers:
        normalized_name = _unquote_identifier(name)
        if normalized_name.startswith("ProofForge") and normalized_name not in {
            "ProofForgeV2", "ProofForgeV2Tests",
        }:
            fail("PF-ISO-LEGACY", f"legacy Lake library declaration: {name}")
    library = _declaration_block(code, "lean_lib", "ProofForgeV2")
    roots = re.findall(r"(?m)^[ \t]+roots[ \t]*:=[ \t]*#\[(.*?)\][ \t]*$", library)
    if len(roots) != 1:
        fail("PF-ISO-NAMESPACE", "ProofForgeV2 library must own the ProofForgeV2 root")
    root_names = tuple(item.strip() for item in roots[0].split(","))
    if "`ProofForgeV2" not in root_names:
        fail("PF-ISO-NAMESPACE", "ProofForgeV2 library must own the ProofForgeV2 root")
    for root_name in root_names:
        normalized_root = _unquote_identifier(root_name.removeprefix("`"))
        if (normalized_root.startswith("ProofForge")
                and normalized_root != "ProofForgeV2"
                and not normalized_root.startswith("ProofForgeV2.")):
            fail("PF-ISO-LEGACY", f"legacy Lake library root: {root_name}")
    executable_headers = re.findall(
        r"(?m)^lean_exe[ \t]+([^ \t]+)[ \t]+where[ \t]*$", code
    )
    for name in executable_headers:
        normalized_name = _unquote_identifier(name)
        if normalized_name.startswith("proof_forge") and normalized_name not in {
            "proof_forge_next", "proof_forge_next_tests",
        }:
            fail("PF-ISO-LEGACY", f"legacy Lake executable declaration: {name}")
    executable = _declaration_block(code, "lean_exe", "proof_forge_next")
    if not re.search(r'(?m)^[ \t]+exeName[ \t]*:=[ \t]*"proof-forge-next"[ \t]*$', executable):
        fail("PF-ISO-EXECUTABLE", "proof_forge_next must emit proof-forge-next")
    if not re.search(r"(?m)^[ \t]+root[ \t]*:=[ \t]*`ProofForgeV2\.CLI\.Main[ \t]*$", executable):
        fail("PF-ISO-EXECUTABLE", "proof_forge_next must use ProofForgeV2.CLI.Main")
    lexical = _strip_lean_comments(source, mask_strings=True)
    has_require = re.search(r"(?m)^[ \t]*require\b", lexical) is not None
    if has_require and re.search(r"\bfrom[ \t\r\n]+(?!git\b)", lexical):
        fail("PF-ISO-PARENT", "lakefile.lean contains an explicit path dependency")
    git_sources = re.findall(
        r'\bfrom[ \t\r\n]+git[ \t\r\n]+"([^"\r\n]+)"', code
    )
    if len(git_sources) != len(re.findall(r"\bfrom[ \t\r\n]+git\b", lexical)):
        fail("PF-ISO-PARENT", "Lake Git dependencies require a literal remote URL")
    for url in git_sources:
        if REMOTE_GIT_URL_RE.fullmatch(url) is None:
            fail("PF-ISO-PARENT", f"Lake Git dependency is not explicitly remote: {url}")
    if has_require and (".." in code or "file:" in code):
        fail("PF-ISO-PARENT", "lakefile.lean contains a local parent dependency")


def _check_manifest(root: Path) -> None:
    value = _decode_json(root / "lake-manifest.json")
    if not isinstance(value, dict):
        fail("PF-ISO-MANIFEST", "lake-manifest.json root must be an object")
    if value.get("name") != "«proof-forge-next»":
        fail("PF-ISO-PACKAGE", "manifest package name is not proof-forge-next")
    if value.get("packagesDir") != ".lake/packages" or value.get("lakeDir") != ".lake":
        fail("PF-ISO-MANIFEST", "manifest Lake directories are not workspace-local")
    packages = value.get("packages")
    if not isinstance(packages, list):
        fail("PF-ISO-MANIFEST", "manifest packages must be an array")
    for index, package in enumerate(packages):
        if not isinstance(package, dict):
            fail("PF-ISO-MANIFEST", f"manifest package {index} is not an object")
        package_type = package.get("type")
        url = package.get("url")
        if package_type == "path":
            fail("PF-ISO-PARENT", f"manifest package {index} is a local path dependency")
        if (package_type != "git" or not isinstance(url, str)
                or REMOTE_GIT_URL_RE.fullmatch(url) is None):
            fail("PF-ISO-PARENT", f"manifest package {index} has no explicit remote Git URL")
        for field in ("configFile", "manifestFile", "subDir"):
            path_value = package.get(field)
            if path_value is None:
                continue
            if (not isinstance(path_value, str) or path_value.startswith(("/", "\\"))
                    or ".." in Path(path_value.replace("\\", "/")).parts):
                fail("PF-ISO-PARENT", f"manifest package {index} has unsafe {field}")


def _walk_product(root: Path) -> tuple[Path, ...]:
    files: list[Path] = []
    casefolded: dict[str, str] = {}
    for path in sorted(root.rglob("*"), key=lambda item: item.relative_to(root).as_posix()):
        relative = path.relative_to(root).as_posix()
        top_level = Path(relative).parts[0]
        if top_level.casefold() in FORBIDDEN_TOP_LEVEL_CASEFOLD:
            fail("PF-ISO-LEAK", f"product snapshot contains forbidden {top_level}")
        if top_level.casefold() == ".gitmodules":
            fail("PF-ISO-SUBMODULE", f"product snapshot contains {top_level}")
        if (relative != unicodedata.normalize("NFC", relative)
                or relative.startswith("/") or ".." in Path(relative).parts):
            fail("PF-ISO-PATH", f"noncanonical product path: {relative}")
        alias = unicodedata.normalize("NFC", relative).casefold()
        previous = casefolded.get(alias)
        if previous is not None and previous != relative:
            fail("PF-ISO-PATH", f"casefold path collision: {previous}, {relative}")
        casefolded[alias] = relative
        try:
            metadata = os.stat(path, follow_symlinks=False)
        except OSError as error:
            fail("PF-ISO-IO", f"cannot stat {relative}: {error}")
        if stat.S_ISLNK(metadata.st_mode):
            fail("PF-ISO-SYMLINK", f"product path is a symlink: {relative}")
        if stat.S_ISDIR(metadata.st_mode):
            continue
        if not stat.S_ISREG(metadata.st_mode):
            fail("PF-ISO-FILE", f"product path is not regular: {relative}")
        files.append(path)
        if len(files) > MAX_FILES:
            fail("PF-ISO-LIMIT", f"product tree exceeds {MAX_FILES} files")
    return tuple(files)


def check_git_tree_records(payload: bytes) -> None:
    if type(payload) is not bytes or not payload or len(payload) > MAX_GIT_TREE_BYTES:
        fail("PF-ISO-GIT-TREE", "Git tree records are empty, mistyped, or oversized")
    if not payload.endswith(b"\x00"):
        fail("PF-ISO-GIT-TREE", "Git tree records are not NUL terminated")
    records = payload[:-1].split(b"\x00")
    if len(records) > MAX_FILES:
        fail("PF-ISO-LIMIT", f"Git tree exceeds {MAX_FILES} files")
    for record in records:
        try:
            header, raw_path = record.split(b"\t", 1)
            mode, object_type, object_id = header.split(b" ")
            path = raw_path.decode("utf-8", errors="strict")
        except (UnicodeError, ValueError):
            fail("PF-ISO-GIT-TREE", "malformed Git tree record")
        if (not path or path.startswith("/") or ".." in Path(path).parts
                or any(character in path for character in "\x00\r\n\t")):
            fail("PF-ISO-PATH", f"noncanonical Git tree path: {path!r}")
        if path == "active" or path.startswith("active/"):
            continue
        if mode == b"120000":
            fail("PF-ISO-SYMLINK", f"tracked symlink is forbidden: {path}")
        if mode == b"160000":
            fail("PF-ISO-SUBMODULE", f"tracked submodule is forbidden: {path}")
        if (mode not in {b"100644", b"100755"} or object_type != b"blob"
                or re.fullmatch(rb"[0-9a-f]{40}|[0-9a-f]{64}", object_id) is None):
            fail("PF-ISO-GIT-TREE", f"unsupported Git tree record: {path}")


def check_product_tree(root: Path, forbidden_checkout: str) -> None:
    if not isinstance(root, Path) or type(forbidden_checkout) is not str or not forbidden_checkout:
        fail("PF-ISO-INPUT", "root and forbidden checkout must be exact typed values")
    try:
        root_metadata = os.stat(root, follow_symlinks=False)
    except OSError as error:
        fail("PF-ISO-IO", f"cannot stat product root: {error}")
    if not stat.S_ISDIR(root_metadata.st_mode) or root.is_symlink():
        fail("PF-ISO-ROOT", "product root must be a non-symlink directory")
    for name in FORBIDDEN_TOP_LEVEL:
        if (root / name).exists() or (root / name).is_symlink():
            fail("PF-ISO-LEAK", f"product snapshot contains forbidden {name}")
    if (root / ".gitmodules").exists():
        fail("PF-ISO-SUBMODULE", "product snapshot contains .gitmodules")
    files = _walk_product(root)
    exact_files = {path.relative_to(root).as_posix() for path in files}
    for relative in REQUIRED_FILES:
        if relative not in exact_files:
            fail("PF-ISO-REQUIRED", f"missing canonical product file: {relative}")
    for path in files:
        if path.suffix.lower() in FORBIDDEN_PRODUCT_SUFFIXES:
            fail("PF-ISO-BINARY", f"product snapshot contains built binary: {path.relative_to(root)}")

    _check_lakefile(root)
    _check_manifest(root)
    toolchain = _read_text(root / "lean-toolchain", "lean-toolchain")
    if TOOLCHAIN_RE.fullmatch(toolchain) is None:
        fail("PF-ISO-TOOLCHAIN", "lean-toolchain must be an exact remote Lean release")

    lean_sources = tuple(path for path in files if path.suffix == ".lean")
    total = 0
    checkout_bytes = forbidden_checkout.encode("utf-8")
    for source_path in lean_sources:
        text = _read_text(source_path, source_path.relative_to(root).as_posix())
        encoded = text.encode("utf-8")
        total += len(encoded)
        if total > MAX_TOTAL_SOURCE_BYTES:
            fail("PF-ISO-LIMIT", "product Lean sources exceed the aggregate limit")
        lexical = _strip_lean_comments(text, mask_strings=True)
        if LEGACY_NAME_RE.search(lexical):
            fail("PF-ISO-LEGACY", f"legacy ProofForge name: {source_path.relative_to(root)}")
        if ACTIVE_IMPORT_RE.search(lexical):
            fail("PF-ISO-LEGACY", f"active module import: {source_path.relative_to(root)}")
        if "active/" in text or "active\\" in text or "new_design/" in text:
            fail("PF-ISO-LEGACY", f"legacy fallback path: {source_path.relative_to(root)}")
    for product_path in files:
        if (product_path.name not in TEXT_PRODUCT_NAMES
                and product_path.suffix.lower() not in TEXT_PRODUCT_SUFFIXES):
            continue
        text = _read_text(product_path, product_path.relative_to(root).as_posix())
        if checkout_bytes in text.encode("utf-8"):
            fail("PF-ISO-ABSOLUTE", f"embedded checkout path: {product_path.relative_to(root)}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    operation = parser.add_mutually_exclusive_group(required=True)
    operation.add_argument("--root")
    operation.add_argument("--git-tree-records")
    parser.add_argument("--forbidden-checkout")
    arguments = parser.parse_args(argv)
    try:
        if arguments.git_tree_records is not None:
            if arguments.forbidden_checkout is not None:
                fail("PF-ISO-INPUT", "Git tree mode does not accept a checkout path")
            tree_path = Path(arguments.git_tree_records)
            try:
                payload = tree_path.read_bytes()
            except OSError as error:
                fail("PF-ISO-IO", f"cannot read Git tree records: {error}")
            check_git_tree_records(payload)
            print("v2-isolation: committed Git tree ok")
            return 0
        if arguments.forbidden_checkout is None:
            fail("PF-ISO-INPUT", "product tree mode requires a forbidden checkout path")
        check_product_tree(Path(arguments.root), arguments.forbidden_checkout)
    except IsolationError as error:
        print(f"{error.code}: {error.detail}", file=sys.stderr)
        return 1
    print("v2-isolation: product tree ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
