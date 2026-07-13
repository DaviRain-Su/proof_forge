#!/usr/bin/env python3

import argparse
import os
import subprocess
import sys
from collections.abc import Sequence


SHARED_PREFIXES = (
    "ProofForge/IR/", "ProofForge/Frontend/", "ProofForge/Contract/",
    "ProofForge/Target/", "ProofForge/Compiler/CanonicalPipeline.lean",
    "Examples/Product/",
)
EVM_PREFIXES = ("ProofForge/Backend/Evm/", "scripts/evm/", "Tests/Backend/Evm/")
SOLANA_PREFIXES = (
    "ProofForge/Backend/Solana/", "ProofForge/Solana/", "scripts/solana/",
    "Tests/Backend/Solana/",
)
WASM_PREFIXES = (
    "ProofForge/Backend/WasmHost/", "ProofForge/Compiler/Wasm/", "scripts/near/",
    "Tests/Backend/Wasm/",
)
STYLUS_PREFIXES = (
    "ProofForge/Backend/Stylus/", "ProofForge/Cli/StylusArtifacts.lean",
    "runtime/stylus-host/", "scripts/stylus/", "Tests/Stylus/",
    "tools/stylus-",
)
DOC_PREFIXES = ("docs/", "README.md", "CONTRIBUTING.md", "scripts/i18n/")


def select_tags(paths: Sequence[str]) -> set[str]:
    tags = {"fast"}
    for path in paths:
        if path.startswith(SHARED_PREFIXES):
            tags.update({"evm-fast", "solana-fast", "wasm-fast", "stylus-fast"})
        elif path.startswith(EVM_PREFIXES):
            tags.add("evm-fast")
        elif path.startswith(SOLANA_PREFIXES):
            tags.add("solana-fast")
        elif path.startswith(WASM_PREFIXES):
            tags.add("wasm-fast")
        elif path.startswith(STYLUS_PREFIXES):
            tags.add("stylus-fast")
        elif path.startswith(DOC_PREFIXES):
            tags.add("docs")
    return tags


def _git(*args: str) -> str:
    return subprocess.run(
        ["git", *args], check=True, capture_output=True, text=True
    ).stdout.strip()


def resolve_base() -> str:
    override = os.environ.get("CHECK_BASE")
    if override:
        _git("rev-parse", "--verify", override)
        return override
    try:
        upstream = _git("rev-parse", "--abbrev-ref", "@{upstream}")
        return _git("merge-base", "HEAD", upstream)
    except subprocess.CalledProcessError:
        return _git("rev-parse", "HEAD^")


def changed_paths(base: str) -> list[str]:
    output = _git("diff", "--name-only", base)
    return output.splitlines() if output else []


def main() -> int:
    parser = argparse.ArgumentParser(description="Select focused ProofForge test tags")
    parser.add_argument("--print-paths", action="store_true")
    args = parser.parse_args()
    try:
        paths = changed_paths(resolve_base())
    except subprocess.CalledProcessError as error:
        print(f"check-fast: git selection failed: {error}", file=sys.stderr)
        return 2
    if args.print_paths:
        print("\n".join(paths))
    print(" ".join(sorted(select_tags(paths))))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
