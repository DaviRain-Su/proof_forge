#!/usr/bin/env bash
# ProofShip rwa-share-v1 — X Layer testnet acceptance run (engineering lane).
#
# Mirrors scripts/anvil-check.sh against the LIVE deployed contract.
# Every scenario lands on-chain (tx hashes printed) — this is the recorded
# evidence trail for the product walkthrough.
#
# Key discipline: key lives ONLY in the env var you name; never in files/argv.
#
# Usage:
#   PF_XLAYER_CONFIRM=yes PF_XLAYER_PRIVATE_KEY_ENV=PF_XLAYER_KEY \
#     scripts/testnet-acceptance.sh <contract-address> <recipient-address>
#
# Scenarios (7 txs):
#   1. views pinned (issuedTotal=0, policy=maxPerTx)
#   2. owner issue(owner, 100000)
#   3. owner setAllow(recipient, 1)
#   4. owner transfer(recipient, 40000) ×2 (windowSpent=80000)
#   5. negative: transfer 40000 more → exceeds windowCap (120000>100000) → reverts ON-CHAIN
#   6. negative: transfer 60000 > maxPerTx → reverts ON-CHAIN
#   7. negative: transfer to non-allowlisted stranger → reverts ON-CHAIN
#   8. final state pinned (negatives changed nothing)
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
proj="$(cd "$here/.." && pwd)"

die() { echo "testnet-acceptance: FAIL: $*" >&2; exit 1; }

[[ "${PF_XLAYER_CONFIRM:-}" == "yes" ]] || die "set PF_XLAYER_CONFIRM=yes"
KEY_ENV_NAME="${PF_XLAYER_PRIVATE_KEY_ENV:-}"
[[ -n "$KEY_ENV_NAME" ]] || die "set PF_XLAYER_PRIVATE_KEY_ENV to the env var NAME holding the key"
[[ -n "${!KEY_ENV_NAME:-}" ]] || die "env '$KEY_ENV_NAME' is empty"

ADDR="${1:?usage: testnet-acceptance.sh <contract> <recipient> [stranger]}"
RECIPIENT="${2:?missing recipient address}"
STRANGER="${3:-0x90F79bf6EB2c4f870365E785982E1f101E93b906}"

cast_bin="${FOUNDRY_BIN:-${PROOF_FORGE_TOOL_ROOT:-$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64}}/cast"
[[ -x "$cast_bin" ]] || cast_bin="$HOME/.foundry/bin/cast"
[[ -x "$cast_bin" ]] || die "cast not found"

RPC="${PF_XLAYER_RPC:-https://testrpc.xlayer.tech/terigon}"
CHAIN_ID=1952

# Principal ABI words (ADR-0025): len=20 + 8 LE words.
words() {
  /usr/bin/python3 -I -S -c "
addr = '''$1'''.strip().lower().removeprefix('0x')
assert len(addr) == 40, 'bad address'
b = bytes.fromhex(addr)
print(20, int.from_bytes(b[0:8],'little'), int.from_bytes(b[8:16],'little'), int.from_bytes(b[16:20],'little'), 0,0,0,0,0)
"
}

to_dec() { /usr/bin/python3 -I -S -c "print(int('$1',16)) if '$1'.startswith('0x') else print('$1'.split()[0])"; }

expect_view() { # <sig> <expected-dec> <label> [words...]
  local sig="$1" expected="$2" label="$3"; shift 3
  local got
  got="$("$cast_bin" call --rpc-url "$RPC" "$ADDR" "$sig" "$@" 2>/dev/null || echo "CALL-FAILED")"
  local dec; dec="$(to_dec "$got")"
  [[ "$dec" == "$expected" ]] || die "$label: expected $expected, got '$got'"
  echo "  view $label = $dec ✓" >&2
}

send_tx() { # <label> <sig> [args...] — prints tx hash, dies on failure
  local label="$1" sig="$2"; shift 2
  local out hash
  out="$("$cast_bin" send --json --rpc-url "$RPC" --private-key "${!KEY_ENV_NAME}" \
    "$ADDR" "$sig" "$@" 2>&1)" || { echo "$out" >&2; die "$label: send failed"; }
  hash="$(echo "$out" | /usr/bin/python3 -I -S -c 'import json,sys; print(json.load(sys.stdin)["transactionHash"])')"
  echo "  tx $label → $hash ✓" >&2
}

expect_revert_onchain() { # <label> <sig> [args...] — explicit gas-limit so the revert is MINED (status 0x0)
  local label="$1" sig="$2"; shift 2
  local out hash status
  set +e
  out="$("$cast_bin" send --json --gas-limit 400000 --rpc-url "$RPC" \
    --private-key "${!KEY_ENV_NAME}" "$ADDR" "$sig" "$@" 2>&1)"
  set -e
  hash="$(echo "$out" | /usr/bin/python3 -I -S -c 'import json,sys; print(json.load(sys.stdin)["transactionHash"])' 2>/dev/null || true)"
  [[ -n "$hash" ]] || { echo "$out" >&2; die "$label: could not send revert tx"; }
  status="$("$cast_bin" receipt --rpc-url "$RPC" "$hash" status 2>/dev/null || echo "?")"
  [[ "$status" == "0x0" || "$status" == "0" ]] || die "$label: expected on-chain revert, status=$status"
  echo "  tx $label → $hash (reverted on-chain, status=0) ✓" >&2
}

OWNER="$("$cast_bin" wallet address --private-key "${!KEY_ENV_NAME}")"
echo "testnet-acceptance: contract=$ADDR owner=$OWNER rpc=$RPC" >&2

# shellcheck disable=SC2207
OWNER_WORDS=($(words "$OWNER"))
# shellcheck disable=SC2207
RECIPIENT_WORDS=($(words "$RECIPIENT"))
# shellcheck disable=SC2207
STRANGER_WORDS=($(words "$STRANGER"))

P9='uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64'

echo "== 1. views ==" >&2
expect_view 'issuedTotal()(uint64)' 0 issuedTotal
expect_view 'policy()(uint64)' 50000 policy-maxPerTx

echo "== 2. issue(owner, 100000) ==" >&2
send_tx issue "issue(${P9},uint64)(uint64)" "${OWNER_WORDS[@]}" 100000
expect_view "balanceOf(${P9})(uint64)" 100000 balanceOf-owner "${OWNER_WORDS[@]}"
expect_view 'issuedTotal()(uint64)' 100000 issuedTotal

echo "== 3. setAllow(recipient, 1) ==" >&2
send_tx setAllow "setAllow(${P9},uint64)(uint64)" "${RECIPIENT_WORDS[@]}" 1

echo "== 4. transfer(recipient, 40000) ×2 ==" >&2
send_tx transfer-1 "transfer(${P9},uint64)(uint64)" "${RECIPIENT_WORDS[@]}" 40000
send_tx transfer-2 "transfer(${P9},uint64)(uint64)" "${RECIPIENT_WORDS[@]}" 40000
expect_view "balanceOf(${P9})(uint64)" 80000 balanceOf-recipient "${RECIPIENT_WORDS[@]}"
expect_view "balanceOf(${P9})(uint64)" 20000 balanceOf-owner "${OWNER_WORDS[@]}"

echo "== 5. negative: window cap (80000+40000 > 100000) ==" >&2
expect_revert_onchain neg-window "transfer(${P9},uint64)(uint64)" "${RECIPIENT_WORDS[@]}" 40000

echo "== 6. negative: per-tx cap (60000 > 50000) ==" >&2
expect_revert_onchain neg-per-tx "transfer(${P9},uint64)(uint64)" "${RECIPIENT_WORDS[@]}" 60000

echo "== 7. negative: non-allowlisted stranger ==" >&2
expect_revert_onchain neg-allowlist "transfer(${P9},uint64)(uint64)" "${STRANGER_WORDS[@]}" 1000

echo "== 8. negatives changed nothing ==" >&2
expect_view "balanceOf(${P9})(uint64)" 20000 balanceOf-owner-final "${OWNER_WORDS[@]}"
expect_view "balanceOf(${P9})(uint64)" 80000 balanceOf-recipient-final "${RECIPIENT_WORDS[@]}"
expect_view 'issuedTotal()(uint64)' 100000 issuedTotal-final

echo "testnet-acceptance: ok (2 positive flows + 3 on-chain reverts, all on X Layer 1952)" >&2
