#!/usr/bin/env bash
set -euo pipefail

# Deploy DynamicConstructorProbe initcode with dynamic constructor args on Anvil
# and assert the runtime getters observe constructor-bound storage.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${EVM_OUT_DIR:-$ROOT/build/evm}"
RUN_DIR="${EVM_DYNAMIC_CONSTRUCTOR_RUN_DIR:-$ROOT/build/dynamic-constructor-anvil-smoke}"
CHAIN_ID="${EVM_ANVIL_CHAIN_ID:-31337}"
CHAIN_PROFILE="${EVM_ANVIL_CHAIN_PROFILE:-anvil-local}"
ANVIL_PORT="${EVM_ANVIL_PORT:-18549}"
PROBE_NAME="DynamicConstructorProbe"
PROBE_LEAN="$ROOT/Examples/Evm/Contracts/${PROBE_NAME}.lean"
RUNTIME_OUT="$OUT_DIR/${PROBE_NAME}.bin"
INIT_OUT="$OUT_DIR/${PROBE_NAME}.ctor.init.bin"
DEPLOY_MANIFEST="$OUT_DIR/${PROBE_NAME}.proof-forge-deploy.json"
DEPLOY_RUN="$RUN_DIR/${PROBE_NAME}.proof-forge-deploy-run.json"

export PATH="$HOME/.foundry/bin:$PATH"

if ! command -v anvil >/dev/null 2>&1; then
  echo "dynamic-constructor-anvil-smoke: anvil not found. Install Foundry, then re-run this script." >&2
  exit 127
fi

if ! command -v cast >/dev/null 2>&1; then
  echo "dynamic-constructor-anvil-smoke: cast not found. Install Foundry, then re-run this script." >&2
  exit 127
fi

if [[ -n "${PROOF_FORGE_BIN:-}" ]]; then
  proof_forge=("$PROOF_FORGE_BIN")
else
  proof_forge=(lake env proof-forge)
fi

mkdir -p "$OUT_DIR" "$RUN_DIR"

(
  cd "$ROOT"
  "${proof_forge[@]}" build \
    --target evm \
    --root . \
    --yul-output "$OUT_DIR/${PROBE_NAME}.yul" \
    --artifact-output "$OUT_DIR/${PROBE_NAME}.proof-forge-artifact.json" \
    --evm-chain-profile "$CHAIN_PROFILE" \
    --evm-constructor-arg "name=hello" \
    --evm-constructor-arg "payload=0xdeadbeef" \
    --evm-constructor-arg "amounts=1,2,3" \
    -o "$RUNTIME_OUT" \
    "$PROBE_LEAN"
  diff -u "$ROOT/Examples/Evm/Contracts/${PROBE_NAME}.golden.yul" "$OUT_DIR/${PROBE_NAME}.yul"
  cp "$OUT_DIR/${PROBE_NAME}.init.bin" "$INIT_OUT"
  python3 "$ROOT/scripts/evm/validate-artifact-metadata.py" \
    --root "$ROOT" \
    --expect-fixture "$PROBE_NAME" \
    --expect-source-kind contract-sdk \
    --expect-chain-profile "$CHAIN_PROFILE" \
    --expect-chain-id "$CHAIN_ID" \
    "$OUT_DIR/${PROBE_NAME}.proof-forge-artifact.json"
)

ANVIL_LOG="$RUN_DIR/anvil.log"
ANVIL_PID=""
cleanup() {
  if [[ -n "$ANVIL_PID" ]]; then
    kill "$ANVIL_PID" >/dev/null 2>&1 || true
    wait "$ANVIL_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

anvil --port "$ANVIL_PORT" --chain-id "$CHAIN_ID" >"$ANVIL_LOG" 2>&1 &
ANVIL_PID=$!
sleep 1

RPC_URL="http://127.0.0.1:${ANVIL_PORT}"
PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
INIT_HEX="0x$(tr -d '\n' <"$INIT_OUT")"

RECEIPT_JSON="$RUN_DIR/cast-send.json"
cast send \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --create "$INIT_HEX" \
  --json >"$RECEIPT_JSON"

CONTRACT_ADDRESS="$(python3 - "$RECEIPT_JSON" <<'PY'
import json
import sys

receipt = json.load(open(sys.argv[1], encoding="utf-8"))
address = receipt.get("contractAddress")
if not address:
    raise SystemExit("dynamic-constructor-anvil-smoke: deploy receipt missing contractAddress")
print(address)
PY
)"

NAME_HASH="$(cast keccak hello)"
PAYLOAD_HASH="$(cast keccak 0xdeadbeef)"

expect_uint() {
  local sig="$1"
  local expected_dec="$2"
  local actual
  actual="$(cast call --rpc-url "$RPC_URL" "$CONTRACT_ADDRESS" "$sig")"
  local actual_dec
  actual_dec="$(python3 - "$actual" <<'PY'
import decimal
import sys

text = sys.argv[1].strip()
if text.startswith(("0x", "0X")):
    print(int(text, 16))
else:
    print(int(decimal.Decimal(text)))
PY
)"
  if [[ "$actual_dec" != "$expected_dec" ]]; then
    echo "dynamic-constructor-anvil-smoke: $sig expected $expected_dec, got $actual ($actual_dec)" >&2
    exit 1
  fi
}

expect_bytes32() {
  local sig="$1"
  local expected="$2"
  local actual
  actual="$(cast call --rpc-url "$RPC_URL" "$CONTRACT_ADDRESS" "$sig" | tr 'A-F' 'a-f')"
  expected="$(echo "$expected" | tr 'A-F' 'a-f')"
  if [[ "$actual" != "$expected" ]]; then
    echo "dynamic-constructor-anvil-smoke: $sig expected $expected, got $actual" >&2
    exit 1
  fi
}

expect_uint "getNameLen()(uint256)" "5"
expect_bytes32 "getNameHash()(bytes32)" "$NAME_HASH"
expect_uint "getPayloadLen()(uint256)" "4"
expect_bytes32 "getPayloadHash()(bytes32)" "$PAYLOAD_HASH"
expect_uint "getAmountCount()(uint256)" "3"
expect_uint "getAmountSum()(uint256)" "6"

DEPLOYED_CODE="$(cast code --rpc-url "$RPC_URL" "$CONTRACT_ADDRESS")"
RUNTIME_HEX="0x$(tr -d '\n' <"$RUNTIME_OUT")"
if [[ "$DEPLOYED_CODE" != "$RUNTIME_HEX" ]]; then
  echo "dynamic-constructor-anvil-smoke: deployed runtime code does not match ${PROBE_NAME}.bin" >&2
  exit 1
fi

python3 - "$DEPLOY_RUN" "$DEPLOY_MANIFEST" "$INIT_OUT" "$RUNTIME_OUT" "$RECEIPT_JSON" "$CONTRACT_ADDRESS" "$CHAIN_PROFILE" "$CHAIN_ID" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

run_path, manifest_path, init_path, runtime_path, receipt_path, address, profile, chain_id = sys.argv[1:10]
init_bytes = Path(init_path).read_bytes()
runtime_bytes = Path(runtime_path).read_bytes()
receipt = json.load(open(receipt_path, encoding="utf-8"))
manifest = json.load(open(manifest_path, encoding="utf-8"))

run = {
    "kind": "proof-forge-evm-deploy-run",
    "fixture": "DynamicConstructorProbe",
    "chainProfile": profile,
    "chainId": int(chain_id),
    "deployManifest": manifest_path,
    "initCode": {
        "path": init_path,
        "bytes": len(init_bytes),
        "sha256": hashlib.sha256(init_bytes).hexdigest(),
    },
    "runtimeBytecode": {
        "path": runtime_path,
        "bytes": len(runtime_bytes),
        "sha256": hashlib.sha256(runtime_bytes).hexdigest(),
    },
    "constructorArgs": manifest.get("constructorArgs", []),
    "transaction": {
        "contractAddress": address,
        "receipt": receipt,
    },
}
Path(run_path).write_text(json.dumps(run, indent=2) + "\n", encoding="utf-8")
PY

echo "dynamic-constructor-anvil-smoke: deployed ${PROBE_NAME} to ${CONTRACT_ADDRESS} on Anvil chain ${CHAIN_ID}"
echo "dynamic-constructor-anvil-smoke: deploy-run artifact ${DEPLOY_RUN}"
