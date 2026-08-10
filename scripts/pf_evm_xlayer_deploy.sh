#!/usr/bin/env bash
# Engineering-only helper: deploy PF EVM bytecode to X Layer testnet/mainnet.
# NOT a product default. NOT formal/hermetic. NOT exposed on remote MCP.
#
# Required:
#   PF_XLAYER_CONFIRM=yes
#   PF_XLAYER_PRIVATE_KEY_ENV=<env var name holding hex key>   # never pass raw key argv
#   ARTIFACT_DIR=<pf build -t evm output dir with *.bin + *.abi.json>
#
# Optional:
#   PF_XLAYER_NETWORK=testnet|mainnet   (default testnet)
#   PF_XLAYER_RPC=<url override>
#   PF_XLAYER_CTOR_ARGS=<constructor args for cast>
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "${PF_XLAYER_CONFIRM:-}" != "yes" ]]; then
  cat <<'EOF' >&2
PF-XLAYER-REFUSED: engineering deploy is opt-in.

  export PF_XLAYER_CONFIRM=yes
  export PF_XLAYER_PRIVATE_KEY_ENV=PF_XLAYER_KEY   # name of env that holds the key
  export ARTIFACT_DIR=/path/to/pf-evm-out
  # optional: PF_XLAYER_NETWORK=testnet|mainnet

This script does not run on MCP remote surfaces. Prefer wallet-signed deploys for demos.
See docs/product/13-xlayer-onchainos.md and docs/product/networks.v1.json.
EOF
  exit 2
fi

NETWORK="${PF_XLAYER_NETWORK:-testnet}"
case "$NETWORK" in
  testnet)
    CHAIN_ID=1952
    RPC_DEFAULT="https://testrpc.xlayer.tech/terigon"
    ;;
  mainnet)
    CHAIN_ID=196
    RPC_DEFAULT="https://rpc.xlayer.tech"
    echo "PF-XLAYER-WARN: mainnet deploy — double-check policy and funds (OKB)." >&2
    ;;
  *)
    echo "PF-XLAYER-REFUSED: unknown PF_XLAYER_NETWORK='$NETWORK' (use testnet|mainnet)" >&2
    exit 2
    ;;
esac

RPC="${PF_XLAYER_RPC:-$RPC_DEFAULT}"
ARTIFACT_DIR="${ARTIFACT_DIR:?set ARTIFACT_DIR to pf build -t evm output}"
KEY_ENV_NAME="${PF_XLAYER_PRIVATE_KEY_ENV:?set PF_XLAYER_PRIVATE_KEY_ENV to the env var NAME}"

if [[ -z "${!KEY_ENV_NAME:-}" ]]; then
  echo "PF-XLAYER-REFUSED: env '$KEY_ENV_NAME' is empty (key must live in env, not argv)" >&2
  exit 2
fi

BIN="$(ls -1 "$ARTIFACT_DIR"/*.bin 2>/dev/null | head -1 || true)"
if [[ -z "$BIN" ]]; then
  echo "PF-XLAYER-REFUSED: no *.bin under $ARTIFACT_DIR (run pf build -t evm first)" >&2
  exit 2
fi

if ! command -v cast >/dev/null 2>&1; then
  echo "PF-XLAYER-REFUSED: cast not on PATH (use PROOF_FORGE_TOOL_ROOT / Foundry locked tools)" >&2
  exit 2
fi

echo "network=$NETWORK chainId=$CHAIN_ID rpc=$RPC bin=$BIN" >&2
echo "Creating cast send/create command — review gas token OKB and constructor args." >&2

# Intentionally minimal: operators pass constructor encoding themselves.
# Example (StateCell uint64 initial=7):
#   cast create --rpc-url "$RPC" --private-key "${!KEY_ENV_NAME}" \
#     --chain "$CHAIN_ID" "$(cat "$BIN")" 0000000000000000000000000000000000000000000000000000000000000007
#
# We only print the skeleton so keys are never echoed and accidental mainnet spam is harder.
cat <<EOF
# Dry guidance (not executed automatically beyond this point in v0 stub):
cast create \\
  --rpc-url '$RPC' \\
  --private-key \"\${$KEY_ENV_NAME}\" \\
  --chain $CHAIN_ID \\
  \$(cat '$BIN') \\
  ${PF_XLAYER_CTOR_ARGS:-<constructor-abi-encoded-or-empty>}

# After deploy, point templates/evm-dapp-ui at:
#   VITE_CHAIN_ID=$CHAIN_ID
#   VITE_RPC_URL=$RPC
#   VITE_CONTRACT_ADDRESS=<deployed>
EOF

echo "PF-XLAYER: stub completed (print-only). Set PF_XLAYER_EXECUTE=1 in a future revision to run cast." >&2
if [[ "${PF_XLAYER_EXECUTE:-}" == "1" ]]; then
  echo "PF-XLAYER-REFUSED: execute path not enabled in this revision (print-only safety)." >&2
  exit 2
fi

exit 0
