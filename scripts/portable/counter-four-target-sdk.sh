#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

OUT_ROOT="${PROOF_FORGE_FOUR_TARGET_SDK_OUT:-build/sdk}"
SNAP_A="build/sdk-four-target-a"
SNAP_B="build/sdk-four-target-b"

generate_sdk() {
  local out_root="$1"
  rm -rf "$out_root"
  mkdir -p "$out_root"

  lake env proof-forge build --target evm --fixture counter --format bytecode -o "$out_root/evm"
  lake env proof-forge build --target solana-sbpf-asm --fixture counter -o "$out_root/solana-sbpf-asm"
  lake env proof-forge build --target wasm-near --fixture counter --format wat -o "$out_root/wasm-near"
  lake env proof-forge build --target move-sui --fixture counter -o "$out_root/move-sui"
}

validate_counter_schemas() {
  local out_root="$1"
  python3 scripts/sdk/validate-sdk-schema.py \
    "$out_root"/*/proof-forge-sdk.json \
    --expect-schema proof-forge.sdk-schema.v0 \
    --expect-ir portable-ir-v0
  python3 scripts/sdk/validate-sdk-artifact-refs.py \
    --require-relative \
    --reject-absolute \
    "$out_root"/*/proof-forge-sdk.json
  scripts/sdk/validate-sdk-layout.py "$out_root"
  python3 - "$out_root" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
extension_by_target = {
    "evm": "evm",
    "solana-sbpf-asm": "solana",
    "wasm-near": "near",
    "move-sui": "sui",
}
required_entrypoints = {"initialize", "increment", "get"}
for target, extension in extension_by_target.items():
    schema_path = root / target / "proof-forge-sdk.json"
    data = json.loads(schema_path.read_text())
    contract = data.get("contract")
    contract_name = contract.get("name") if isinstance(contract, dict) else contract
    if contract_name != "Counter":
        raise SystemExit(f"{schema_path}: expected Counter contract")
    if data.get("target") != target:
        raise SystemExit(f"{schema_path}: target mismatch")
    entrypoints = {entry.get("name") for entry in data.get("entrypoints", [])}
    missing = required_entrypoints - entrypoints
    if missing:
        raise SystemExit(f"{schema_path}: missing entrypoints {sorted(missing)}")
    if not data.get("capabilities"):
        raise SystemExit(f"{schema_path}: missing capability metadata")
    if not data.get("artifacts"):
        raise SystemExit(f"{schema_path}: missing artifact references")
    if not data.get("clients"):
        raise SystemExit(f"{schema_path}: missing client references")
    populated = [
        key
        for key, value in data.get("extensions", {}).items()
        if value not in ({}, None)
    ]
    if populated != [extension]:
        raise SystemExit(
            f"{schema_path}: expected only {extension!r} extension, got {populated!r}"
        )
PY
}

rm -rf "$SNAP_A" "$SNAP_B" "$OUT_ROOT"
lake build proof-forge >/dev/null
generate_sdk "$OUT_ROOT"
validate_counter_schemas "$OUT_ROOT"
cp -R "$OUT_ROOT" "$SNAP_A"

rm -rf "$OUT_ROOT"
generate_sdk "$OUT_ROOT"
validate_counter_schemas "$OUT_ROOT"
cp -R "$OUT_ROOT" "$SNAP_B"

diff -ru "$SNAP_A" "$SNAP_B"

echo "counter-four-target-sdk: ok"
