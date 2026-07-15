#!/usr/bin/env python3
"""Validate the four Phase-1 output contracts without overstating maturity."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


def load_manifest(root: Path, target: str) -> dict:
    path = root / target / "manifest.json"
    if not path.is_file():
        raise SystemExit(f"missing {path}")
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if manifest["target"] != target:
        raise SystemExit(f"target mismatch in {path}")
    for relative in manifest["files"]:
        if not (root / target / relative).is_file():
            raise SystemExit(f"manifest references missing file: {target}/{relative}")
    return manifest


def main() -> None:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "build/v2")
    manifests = {target: load_manifest(root, target) for target in ("evm", "solana", "near", "noir")}
    source_hashes = {manifest["sourceHash"] for manifest in manifests.values()}
    semantic_hashes = {manifest["semanticHash"] for manifest in manifests.values()}
    if len(source_hashes) != 1:
        raise SystemExit(f"source hash differs across targets: {source_hashes}")
    if len(semantic_hashes) != 1:
        raise SystemExit(f"semantic hash differs across targets: {semantic_hashes}")
    evm_bin = (root / "evm" / "Counter.bin").read_text(encoding="ascii").strip()
    if not manifests["evm"]["deployable"] or not re.fullmatch(r"[0-9a-fA-F]+", evm_bin):
        raise SystemExit("EVM artifact is not validated bytecode")
    wasm = (root / "near" / "Counter.wasm").read_bytes()
    if not manifests["near"]["deployable"] or not wasm.startswith(b"\x00asm"):
        raise SystemExit("NEAR artifact is not a validated Wasm binary")
    if manifests["solana"]["deployable"]:
        raise SystemExit("Solana must remain non-deployable until an sBPF ELF is produced")
    if manifests["noir"]["deployable"]:
        raise SystemExit("Noir must remain non-deployable until nargo/bb proof evidence exists")
    print("artifact-validation: ok")


if __name__ == "__main__":
    main()
