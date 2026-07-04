#!/usr/bin/env bash
set -euo pipefail

# Validate proof-forge deploy plan generation for a documented testnet profile.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${EVM_OUT_DIR:-$ROOT/build/evm}"
PLAN_DIR="${EVM_DEPLOY_PLAN_DIR:-$ROOT/build/evm-deploy-plan-smoke}"
CHAIN_PROFILE="${EVM_DEPLOY_CHAIN_PROFILE:-robinhood-chain-testnet}"

export PATH="$HOME/.foundry/bin:$PATH"

if [[ -n "${PROOF_FORGE_BIN:-}" ]]; then
  proof_forge=("$PROOF_FORGE_BIN")
else
  proof_forge=(lake env proof-forge)
fi

"$ROOT/scripts/evm/build-examples.sh"

mkdir -p "$PLAN_DIR"
DEPLOY_MANIFEST="$OUT_DIR/Counter.proof-forge-deploy.json"
DEPLOY_PLAN="$PLAN_DIR/Counter.proof-forge-deploy-plan.json"

(
  cd "$ROOT"
  "${proof_forge[@]}" build \
    --target evm \
    --root . \
    --yul-output "$OUT_DIR/Counter.yul" \
    --artifact-output "$OUT_DIR/Counter.proof-forge-artifact.json" \
    --evm-chain-profile "$CHAIN_PROFILE" \
    -o "$OUT_DIR/Counter.bin" \
    Examples/Evm/Contracts/Counter.lean
)

(
  cd "$ROOT"
  "${proof_forge[@]}" deploy \
    --target evm \
    --root . \
    --deploy-manifest "$DEPLOY_MANIFEST" \
    --evm-chain-profile "$CHAIN_PROFILE" \
    --plan-only \
    --output "$DEPLOY_PLAN"
)

python3 "$ROOT/scripts/evm/validate-deploy-plan.py" \
  --root "$ROOT" \
  --expect-chain-profile "$CHAIN_PROFILE" \
  --expect-chain-id 46630 \
  "$DEPLOY_PLAN"

echo "deploy-plan-smoke: wrote $DEPLOY_PLAN for chain profile $CHAIN_PROFILE"
