#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
OUT="$ROOT/build/evm-direct"
RPC_PORT=${PROOF_FORGE_EVM_DIRECT_ERC4626_PORT:-18545}
RPC_URL="http://127.0.0.1:$RPC_PORT"
VAULT=0x0000000000000000000000000000000000004626
ASSET=0x0000000000000000000000000000000000001000
ACTOR=0x0000000000000000000000000000000000002000
KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

find_tool() {
  local name=$1
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
  elif [[ -x "$HOME/.foundry/bin/$name" ]]; then
    printf '%s\n' "$HOME/.foundry/bin/$name"
  else
    echo "missing required tool: $name" >&2
    exit 1
  fi
}

ANVIL=$(find_tool anvil)
CAST=$(find_tool cast)

cd "$ROOT"
lake build ProofForge.Contract.ERC4626.EvmSurface Examples.Product.Canonical.ERC4626Vault
lake env lean --run Tests/Canonical/EvmDirectERC4626.lean
mkdir -p "$OUT"
solc --strict-assembly --optimize --bin "$OUT/ERC4626.yul" > "$OUT/ERC4626.optimized.txt"
awk '/Binary representation:/{getline; print; exit}' "$OUT/ERC4626.optimized.txt" > "$OUT/ERC4626.bin"

python3 - "$OUT/ERC4626.bin" <<'PY'
from pathlib import Path
import sys

runtime = Path(sys.argv[1]).read_text().strip()
size = len(runtime) // 2
if not runtime or size > 24_576:
    raise SystemExit(f"direct ERC4626 runtime violates EIP-170: {size} bytes")
print(f"direct ERC4626 optimized runtime: {size} bytes")
PY

"$ANVIL" --silent --port "$RPC_PORT" > "$OUT/anvil.log" 2>&1 &
ANVIL_PID=$!
cleanup() {
  kill "$ANVIL_PID" >/dev/null 2>&1 || true
  wait "$ANVIL_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

for _ in $(seq 1 50); do
  if "$CAST" block-number --rpc-url "$RPC_URL" >/dev/null 2>&1; then break; fi
  sleep 0.1
done
"$CAST" block-number --rpc-url "$RPC_URL" >/dev/null

runtime=$(tr -d '\n' < "$OUT/ERC4626.bin")
"$CAST" rpc --rpc-url "$RPC_URL" anvil_setCode "$VAULT" "0x$runtime" >/dev/null
"$CAST" send --rpc-url "$RPC_URL" --private-key "$KEY" "$VAULT" \
  'init(address,address,uint256,address)' "$ASSET" "$VAULT" 0 \
  0x0000000000000000000000000000000000000000 >/dev/null

[[ $("$CAST" call --rpc-url "$RPC_URL" "$VAULT" 'asset()(address)') == "$ASSET" ]]
[[ $("$CAST" call --rpc-url "$RPC_URL" "$VAULT" 'totalAssets()(uint256)' | awk '{print $1}') == 0 ]]
[[ $("$CAST" call --rpc-url "$RPC_URL" "$VAULT" 'maxDeposit(address)(uint256)' "$ACTOR" | awk '{print $1}') == 18446744073709551615 ]]

if "$CAST" send --rpc-url "$RPC_URL" --private-key "$KEY" "$VAULT" \
    'init(address,address,uint256,address)' "$ASSET" "$VAULT" 0 \
    0x0000000000000000000000000000000000000000 >/dev/null 2>&1; then
  echo "direct ERC4626 accepted repeated initialization" >&2
  exit 1
fi

echo "evm-direct-erc4626-smoke: ok"
