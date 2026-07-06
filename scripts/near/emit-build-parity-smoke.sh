#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

OUT_ROOT="${PROOF_FORGE_NEAR_PARITY_OUT:-build/wasm-near-emit-build-parity}"
EMIT_DIR="$OUT_ROOT/emit"
BUILD_DIR="$OUT_ROOT/build"

rm -rf "$OUT_ROOT"

lake env proof-forge emit --target wasm-near --fixture counter --format wat -o "$EMIT_DIR"
lake env proof-forge build --target wasm-near --fixture counter --format wat -o "$BUILD_DIR"

python3 scripts/near/validate-emitwat-metadata.py \
  "$EMIT_DIR/proof-forge-artifact.json" \
  --expected-fixture counter \
  --expected-module Counter \
  --expected-entrypoints initialize,increment,get
python3 scripts/near/validate-emitwat-metadata.py \
  "$BUILD_DIR/proof-forge-artifact.json" \
  --expected-fixture counter \
  --expected-module Counter \
  --expected-entrypoints initialize,increment,get

python3 scripts/sdk/validate-sdk-schema.py \
  "$EMIT_DIR/proof-forge-sdk.json" \
  "$BUILD_DIR/proof-forge-sdk.json" \
  --expect-schema proof-forge.sdk-schema.v0 \
  --expect-ir portable-ir-v0 \
  --expect-target wasm-near
python3 scripts/sdk/validate-sdk-artifact-refs.py \
  --require-relative \
  --reject-absolute \
  "$EMIT_DIR/proof-forge-sdk.json" \
  "$BUILD_DIR/proof-forge-sdk.json"

python3 - "$EMIT_DIR" "$BUILD_DIR" <<'PY'
import hashlib
import pathlib
import sys

emit_dir = pathlib.Path(sys.argv[1])
build_dir = pathlib.Path(sys.argv[2])
required = [
    "counter.wat",
    "proof-forge-artifact.json",
    "proof-forge-deploy.json",
    "proof-forge-sdk.json",
    "Counter.contract-spec.json",
    "proof-forge-near.ts",
    "proof-forge-client.ts",
]

for rel in required:
    for root in (emit_dir, build_dir):
        path = root / rel
        if not path.is_file() or path.stat().st_size == 0:
            raise SystemExit(f"near-emit-build-parity: missing required file {path}")

if (emit_dir / "counter.wasm").exists() != (build_dir / "counter.wasm").exists():
    raise SystemExit("near-emit-build-parity: counter.wasm presence differs")

for rel in required + (["counter.wasm"] if (emit_dir / "counter.wasm").exists() else []):
    left = hashlib.sha256((emit_dir / rel).read_bytes()).hexdigest()
    right = hashlib.sha256((build_dir / rel).read_bytes()).hexdigest()
    if left != right:
        raise SystemExit(f"near-emit-build-parity: {rel} digest differs")
PY

echo "near-emit-build-parity: ok"
