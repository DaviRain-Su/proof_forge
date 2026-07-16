#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.foundry/bin:$PATH"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOLC_OUT="$ROOT/build/canonical/evm/solc"
PORT="${PROOF_FORGE_CANONICAL_ANVIL_PORT:-18546}"
RPC="http://127.0.0.1:$PORT"
PRIVATE_KEY="${PROOF_FORGE_ANVIL_PRIVATE_KEY:-ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"

for tool in anvil cast jq; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "$tool is required for canonical EVM runtime parity" >&2
    exit 1
  }
done

extract_bin() {
  awk '/Binary representation:/{getline; print; exit}' "$1"
}

word() {
  printf '%064x' "$1"
}

require_equal() {
  if [[ "$2" != "$3" ]]; then
    echo "runtime parity mismatch for $1" >&2
    echo "legacy: $2" >&2
    echo "core:   $3" >&2
    exit 1
  fi
}

set_code() {
  local address="$1"
  local artifact="$2"
  local bytecode
  bytecode="$(extract_bin "$artifact")"
  [[ -n "$bytecode" ]] || {
    echo "missing binary representation in $artifact" >&2
    exit 1
  }
  cast rpc --rpc-url "$RPC" anvil_setCode "$address" "0x$bytecode" >/dev/null
}

paired_send() {
  local legacy_address="$1"
  local core_address="$2"
  local data="$3"
  local receipt_prefix="$4"
  local legacy_hash core_hash nonce

  cast rpc --rpc-url "$RPC" anvil_setAutomine false >/dev/null
  nonce="$(cast nonce --rpc-url "$RPC" "$SENDER")"
  legacy_hash="$(cast send --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --async \
    --nonce "$nonce" "$legacy_address" "$data")"
  core_hash="$(cast send --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --async \
    --nonce "$((nonce + 1))" "$core_address" "$data")"
  cast rpc --rpc-url "$RPC" evm_mine >/dev/null
  cast rpc --rpc-url "$RPC" anvil_setAutomine true >/dev/null

  cast receipt --rpc-url "$RPC" --json "$legacy_hash" > "$receipt_prefix-legacy.json"
  cast receipt --rpc-url "$RPC" --json "$core_hash" > "$receipt_prefix-core.json"
}

ANVIL_LOG="$ROOT/build/canonical/evm/anvil.log"
anvil --silent --port "$PORT" >"$ANVIL_LOG" 2>&1 &
ANVIL_PID=$!
trap 'kill "$ANVIL_PID" 2>/dev/null || true' EXIT

for _ in $(seq 1 50); do
  if cast block-number --rpc-url "$RPC" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
cast block-number --rpc-url "$RPC" >/dev/null
SENDER="$(cast wallet address --private-key "$PRIVATE_KEY")"

COUNTER_LEGACY="0x1000000000000000000000000000000000000001"
COUNTER_CORE="0x1000000000000000000000000000000000000002"
VAULT_LEGACY="0x2000000000000000000000000000000000000001"
VAULT_CORE="0x2000000000000000000000000000000000000002"

set_code "$COUNTER_LEGACY" "$SOLC_OUT/legacy-counter.txt"
set_code "$COUNTER_CORE" "$SOLC_OUT/core-counter.txt"
set_code "$VAULT_LEGACY" "$SOLC_OUT/legacy-value-vault.txt"
set_code "$VAULT_CORE" "$SOLC_OUT/core-value-vault.txt"

RECEIPTS="$ROOT/build/canonical/evm/receipts"
mkdir -p "$RECEIPTS"

paired_send "$COUNTER_LEGACY" "$COUNTER_CORE" "0x8129fc1c" "$RECEIPTS/counter-init"
paired_send "$COUNTER_LEGACY" "$COUNTER_CORE" "0xd09de08a" "$RECEIPTS/counter-increment"
require_equal "Counter.get return" \
  "$(cast call --rpc-url "$RPC" --data 0x6d4ce63c "$COUNTER_LEGACY")" \
  "$(cast call --rpc-url "$RPC" --data 0x6d4ce63c "$COUNTER_CORE")"
require_equal "Counter slot 0" \
  "$(cast storage --rpc-url "$RPC" "$COUNTER_LEGACY" 0)" \
  "$(cast storage --rpc-url "$RPC" "$COUNTER_CORE" 0)"

MAX_U64_SLOT="0x$(printf '%048x' 0)ffffffffffffffff"
cast rpc --rpc-url "$RPC" anvil_setStorageAt "$COUNTER_LEGACY" 0x0 "$MAX_U64_SLOT" >/dev/null
cast rpc --rpc-url "$RPC" anvil_setStorageAt "$COUNTER_CORE" 0x0 "$MAX_U64_SLOT" >/dev/null
if cast call --rpc-url "$RPC" --data 0xd09de08a "$COUNTER_LEGACY" >/dev/null 2>&1; then
  echo "legacy Counter overflow did not revert" >&2
  exit 1
fi
if cast call --rpc-url "$RPC" --data 0xd09de08a "$COUNTER_CORE" >/dev/null 2>&1; then
  echo "core Counter overflow did not revert" >&2
  exit 1
fi

paired_send "$VAULT_LEGACY" "$VAULT_CORE" \
  "0x8129fc1c$(word 100)" "$RECEIPTS/vault-init"
paired_send "$VAULT_LEGACY" "$VAULT_CORE" \
  "0xd09de08a$(word 25)" "$RECEIPTS/vault-deposit"

for action in vault-init vault-deposit; do
  require_equal "$action events" \
    "$(jq -c '[.logs[] | {topics, data}]' "$RECEIPTS/$action-legacy.json")" \
    "$(jq -c '[.logs[] | {topics, data}]' "$RECEIPTS/$action-core.json")"
done
require_equal "ValueVault balance return" \
  "$(cast call --rpc-url "$RPC" --data 0xf8a8fd6d "$VAULT_LEGACY")" \
  "$(cast call --rpc-url "$RPC" --data 0xf8a8fd6d "$VAULT_CORE")"
require_equal "ValueVault net return" \
  "$(cast call --rpc-url "$RPC" --data 0x1a381be1 "$VAULT_LEGACY")" \
  "$(cast call --rpc-url "$RPC" --data 0x1a381be1 "$VAULT_CORE")"
for slot in 0 1; do
  require_equal "ValueVault slot $slot" \
    "$(cast storage --rpc-url "$RPC" "$VAULT_LEGACY" "$slot")" \
    "$(cast storage --rpc-url "$RPC" "$VAULT_CORE" "$slot")"
done

RELEASE_TOO_MUCH="0xb214faa5$(word 1000)"
if cast call --rpc-url "$RPC" --data "$RELEASE_TOO_MUCH" "$VAULT_LEGACY" >/dev/null 2>&1; then
  echo "legacy ValueVault invalid release did not revert" >&2
  exit 1
fi
if cast call --rpc-url "$RPC" --data "$RELEASE_TOO_MUCH" "$VAULT_CORE" >/dev/null 2>&1; then
  echo "core ValueVault invalid release did not revert" >&2
  exit 1
fi

echo "evm-canonical-runtime-parity: ok"
