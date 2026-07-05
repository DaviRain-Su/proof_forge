#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

OUT_ROOT="${PROOF_FORGE_SDK_DISCOVERABILITY_OUT:-build/sdk-discoverability}"
LOG_DIR="$OUT_ROOT/logs"
rm -rf "$OUT_ROOT" build/sdk
mkdir -p "$LOG_DIR"

run_and_check() {
  local label="$1"
  local out_dir="$2"
  shift 2
  local log="$LOG_DIR/${label}.log"
  "$@" 2>&1 | tee "$log"
  for rel in proof-forge-sdk.json proof-forge-client.ts proof-forge-artifact.json; do
    if ! grep -Fq "$out_dir/$rel" "$log"; then
      echo "sdk-discoverability: ${label} log missing ${out_dir}/${rel}" >&2
      exit 1
    fi
  done
  python3 - "$out_dir/proof-forge-artifact.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
metadata = json.loads(path.read_text())
if metadata.get("sdkSchema") != "proof-forge-sdk.json":
    raise SystemExit(f"sdk-discoverability: {path} missing sdkSchema reference")
PY
}

run_and_check build-evm build/sdk/evm \
  lake env proof-forge build --target evm --fixture counter --format bytecode -o build/sdk/evm
run_and_check emit-evm "$OUT_ROOT/emit/evm" \
  lake env proof-forge emit --target evm --fixture counter --format bytecode -o "$OUT_ROOT/emit/evm"

run_and_check build-solana build/sdk/solana-sbpf-asm \
  lake env proof-forge build --target solana-sbpf-asm --fixture counter -o build/sdk/solana-sbpf-asm
run_and_check emit-solana "$OUT_ROOT/emit/solana-sbpf-asm" \
  lake env proof-forge emit --target solana-sbpf-asm --fixture counter --format s -o "$OUT_ROOT/emit/solana-sbpf-asm"

run_and_check build-near build/sdk/wasm-near \
  lake env proof-forge build --target wasm-near --fixture counter --format wat -o build/sdk/wasm-near
run_and_check emit-near "$OUT_ROOT/emit/wasm-near" \
  lake env proof-forge emit --target wasm-near --fixture counter --format wat -o "$OUT_ROOT/emit/wasm-near"

run_and_check build-sui build/sdk/move-sui \
  lake env proof-forge build --target move-sui --fixture counter -o build/sdk/move-sui
run_and_check emit-sui "$OUT_ROOT/emit/move-sui" \
  lake env proof-forge emit --target move-sui --fixture counter --format sui -o "$OUT_ROOT/emit/move-sui"

scripts/sdk/validate-sdk-layout.py build/sdk
python3 scripts/sdk/validate-sdk-artifact-refs.py --require-relative --reject-absolute build/sdk/*/proof-forge-sdk.json

echo "sdk-discoverability: ok"
