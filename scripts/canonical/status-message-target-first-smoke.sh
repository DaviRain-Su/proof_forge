#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

export PATH="$HOME/.elan/bin:$HOME/.local/bin:$HOME/.foundry/bin:$PATH"

OUT="${STATUS_MESSAGE_CUTOVER_OUT:-build/status-message-authoring-cutover}"
SOURCE=Examples/Product/StatusMessage.lean
rm -rf "$OUT"
mkdir -p "$OUT/evm" "$OUT/solana" "$OUT/near"

lake env proof-forge build --target evm --root . \
  -o "$OUT/evm/StatusMessage.bin" \
  --yul-output "$OUT/evm/StatusMessage.yul" \
  --artifact-output "$OUT/evm/artifact.json" \
  "$SOURCE"

lake env proof-forge build --target solana-sbpf-asm --format s --root . \
  -o "$OUT/solana/StatusMessage.s" \
  --artifact-output "$OUT/solana/artifact.json" \
  "$SOURCE"

lake env proof-forge build --target wasm-near --root . \
  -o "$OUT/near" \
  --artifact-output "$OUT/near/artifact.json" \
  "$SOURCE"

python3 - "$OUT" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
expected = {"init", "set_status", "get_status"}
artifacts = {
    "evm": root / "evm/artifact.json",
    "solana-sbpf-asm": root / "solana/artifact.json",
    "wasm-near": root / "near/artifact.json",
}
for target, path in artifacts.items():
    artifact = json.loads(path.read_text())
    assert artifact["target"] == target, path
    assert artifact["sourceKind"] == "contract-source-authored", path
    assert artifact["sourceModule"] == "StatusMessage", path
    assert artifact["irVersion"] == "canonical-core-v1", path
    if target == "solana-sbpf-asm":
        idl_path = pathlib.Path(artifact["artifacts"]["solanaIdl"]["path"])
        idl = json.loads(idl_path.read_text())
        names = {entry["name"] for entry in idl["instructions"]}
    else:
        names = {entry["name"] for entry in artifact["abi"]["entrypoints"]}
    assert names == expected, (path, names)

required = [
    root / "evm/StatusMessage.yul",
    root / "evm/StatusMessage.bin",
    root / "solana/StatusMessage.s",
    root / "solana/manifest.toml",
    root / "solana/proof-forge-idl.json",
    root / "near/statusmessage.wat",
    root / "near/statusmessage.wasm",
]
for path in required:
    assert path.is_file() and path.stat().st_size > 0, path

retired = list(root.rglob("*contract-spec*")) + list(root.rglob("*ir-module*"))
assert not retired, retired
PY

printf 'status-message-target-first-smoke: ok\n'
