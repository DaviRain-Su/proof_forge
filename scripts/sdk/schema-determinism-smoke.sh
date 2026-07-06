#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

SNAP_A="build/sdk-determinism-a"
SNAP_B="build/sdk-determinism-b"

rm -rf build/sdk "$SNAP_A" "$SNAP_B"
lake env lean --run Tests/SdkSchema.lean
cp -R build/sdk "$SNAP_A"

rm -rf build/sdk
lake env lean --run Tests/SdkSchema.lean
cp -R build/sdk "$SNAP_B"

python3 - "$SNAP_A" "$SNAP_B" <<'PY'
import hashlib
import pathlib
import sys

a = pathlib.Path(sys.argv[1])
b = pathlib.Path(sys.argv[2])
targets = ["evm", "solana-sbpf-asm", "wasm-near", "move-sui"]
for target in targets:
    left = (a / target / "proof-forge-sdk.json").read_bytes()
    right = (b / target / "proof-forge-sdk.json").read_bytes()
    left_digest = hashlib.sha256(left).hexdigest()
    right_digest = hashlib.sha256(right).hexdigest()
    print(f"{target}: {left_digest}")
    if left_digest != right_digest or left != right:
        raise SystemExit(f"schema changed across deterministic runs for {target}")
PY

echo "sdk-schema-determinism: ok"
