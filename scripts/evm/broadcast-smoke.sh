#!/usr/bin/env bash
set -euo pipefail

# Broadcast Counter deploy with explicit gas flags on a local Anvil chain.
# Exercises the `proof-forge deploy` --gas-limit / --gas-price /
# --max-priority-fee-per-gas path and validates the deploy-run artifact.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PROOF_FORGE_DEPLOY_PRIVATE_KEY="${PROOF_FORGE_DEPLOY_PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
OUT_DIR="${EVM_OUT_DIR:-$ROOT/build/evm}"
RUN_DIR="${EVM_BROADCAST_RUN_DIR:-$ROOT/build/broadcast-smoke}"
CHAIN_ID="${EVM_ANVIL_CHAIN_ID:-31337}"
# Publicly known first Anvil account key. Test-only and passed explicitly so
# the product deploy command never supplies signing material.
ANVIL_TEST_PRIVATE_KEY="${EVM_ANVIL_TEST_PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
ANVIL_TEST_DEPLOYER="${EVM_ANVIL_TEST_DEPLOYER:-0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266}"

export PATH="$HOME/.foundry/bin:$PATH"

if ! command -v cast >/dev/null 2>&1; then
  echo "broadcast-smoke: cast not found on PATH" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "broadcast-smoke: python3 not found on PATH" >&2
  exit 1
fi

mkdir -p "$OUT_DIR" "$RUN_DIR"

lake build proof-forge Examples.Product.Counter >/dev/null

lake env proof-forge build \
  --target evm \
  --root . \
  --module Counter \
  --evm-chain-profile anvil-local \
  --artifact-output "$OUT_DIR/Counter.proof-forge-artifact.json" \
  -o "$OUT_DIR/Counter.bin" \
  Examples/Backend/Evm/Contracts/Counter.lean

DEPLOY_MANIFEST="$OUT_DIR/Counter.proof-forge-deploy.json"
DEPLOY_RUN="$RUN_DIR/Counter.proof-forge-deploy-run.json"

lake env proof-forge deploy \
  --deploy-manifest "$DEPLOY_MANIFEST" \
  --evm-chain-profile anvil-local \
  --start-anvil \
  --private-key "$ANVIL_TEST_PRIVATE_KEY" \
  --deployer "$ANVIL_TEST_DEPLOYER" \
  --gas-limit 3000000 \
  --gas-price 1000000000 \
  --max-priority-fee-per-gas 100000000 \
  -o "$DEPLOY_RUN"

python3 "$ROOT/scripts/evm/validate-deploy-run.py" \
  --root "$ROOT" \
  --expect-chain-profile anvil-local \
  --expect-chain-id "$CHAIN_ID" \
  "$DEPLOY_RUN"

CONTRACT_ADDRESS="$(python3 - "$DEPLOY_RUN" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
print(data["transaction"]["contractAddress"])
PY
)"

echo "broadcast-smoke: deployed Counter to $CONTRACT_ADDRESS on Anvil chain $CHAIN_ID"
echo "broadcast-smoke: ProofForge deploy-run artifact $DEPLOY_RUN"
