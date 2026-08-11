#!/usr/bin/env bash
# ProofShip rwa-share-v1 — local-chain acceptance on Anvil (engineering evidence, not formal).
#
# Scenario (ctor: supply=1000000, perTx=50000, windowCap=100000, window=1000 blocks):
#   1. deploy RwaShareRegistry; views pinned
#   2. owner issue(holder,100000) → issued/balance updated
#   3. negative: non-owner issue → revert
#   4. owner setAllow(recipient,1); isAllowed pinned (recipient=true, stranger=false)
#   5. holder transfer(recipient,40000) ×2 → balances + windowSpent accumulate
#   6. negative: third 40000 transfer exceeds windowCap (120000 > 100000) → revert
#   7. negative: 60000 > maxPerTx → revert
#   8. negative: transfer to non-allowlisted stranger → revert (NotAllowed)
#   9. negatives leave state unchanged
#
# Skip-clean (exit 0) when locked anvil/cast are unavailable; hard fail otherwise.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$root"
proj="proofship/rwa-share-v1"

foundry_bin="${FOUNDRY_BIN:-${PROOF_FORGE_TOOL_ROOT:-$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64}}"
anvil_path="$foundry_bin/anvil"
cast_path="$foundry_bin/cast"
if [[ ! -x "$anvil_path" || ! -x "$cast_path" ]]; then
  foundry_bin="$HOME/.foundry/bin"
  anvil_path="$foundry_bin/anvil"
  cast_path="$foundry_bin/cast"
fi
for tool in "$anvil_path" "$cast_path"; do
  if [[ ! -x "$tool" ]]; then
    echo "rwa-share-anvil: explicit skip: missing $tool (optional; not pass)" >&2
    exit 0
  fi
done

die() { echo "rwa-share-anvil: FAIL: $*" >&2; exit 1; }

require_equal() {
  local actual="$1" expected="$2" message="$3"
  [[ "$actual" == "$expected" ]] || die "$message (expected '$expected', got '$actual')"
}

to_dec() {
  local x="$1"
  if [[ "$x" =~ ^0x[0-9a-fA-F]+$ ]]; then
    /usr/bin/python3 -I -S -c "print(int('$x', 16))" 2>/dev/null || echo "$x"
  elif [[ "$x" =~ ^([0-9]+)(\ \[[0-9.eE+-]+\])?$ ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo "$x"
  fi
}

require_uint_equal() {
  local actual="$1" expected="$2" message="$3" canonical
  canonical="$(to_dec "$actual")"
  [[ -n "$canonical" ]] || die "$message (empty uint output, raw='$actual')"
  require_equal "$canonical" "$expected" "$message"
}

require_bool_true() {
  local actual="$1" message="$2" norm
  norm="$(echo "$actual" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  case "$norm" in
    true|0x1|0x01|0x0000000000000000000000000000000000000000000000000000000000000001|1) ;;
    *) die "$message (expected true, got '$actual')" ;;
  esac
}

require_bool_false() {
  local actual="$1" message="$2" norm
  norm="$(echo "$actual" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  case "$norm" in
    false|0x0|0x00|0x0000000000000000000000000000000000000000000000000000000000000000|0) ;;
    *) die "$message (expected false, got '$actual')" ;;
  esac
}

# Pack a 20-byte network-order address into Principal ABI leaves (ADR-0025):
# len=20, w0/w1 = LE first/next 8 bytes, w2 = LE last 4 (high 32 zero), w3..w7=0.
principal_words_from_addr() {
  local addr="$1"
  /usr/bin/python3 -I -S -c "
addr = '''$addr'''.strip().lower().removeprefix('0x')
if len(addr) != 40:
    raise SystemExit(f'bad address length: {addr!r}')
body = bytes.fromhex(addr)
w0 = int.from_bytes(body[0:8], 'little')
w1 = int.from_bytes(body[8:16], 'little')
w2 = int.from_bytes(body[16:20], 'little')
print(20, w0, w1, w2, 0, 0, 0, 0, 0)
"
}

# --- build -------------------------------------------------------------------
cli="$root/.lake/build/bin/proof-forge-next"
[[ -x "$cli" ]] || die "product CLI missing (run just build first)"
rm -rf "$proj/out-evm"  # product build fails closed on pre-existing output dir
"$cli" build src/RwaShareRegistry.lean --module RwaShareRegistry \
  --root "$proj" --target evm -o out-evm >/dev/null \
  || die "product build of RwaShareRegistry (evm) failed"
[[ -s "$proj/out-evm/RwaShareRegistry.bin" ]] || die "RwaShareRegistry.bin missing"

# --- anvil -------------------------------------------------------------------
port=$((20645 + RANDOM % 1000))
chain_id="${PF_EVM_CHAIN_ID:-31339}"
# Anvil default accounts.
owner_pk=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
owner=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
holder_pk=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
holder=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
recipient=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
stranger=0x90F79bf6EB2c4f870365E785982E1f101E93b906

anvil_log="$(mktemp "${TMPDIR:-/tmp}/rwa-share-anvil.XXXXXX.log")"
cleanup() {
  kill "${anvil_pid:-}" 2>/dev/null || true
  wait "${anvil_pid:-}" 2>/dev/null || true
  rm -f "$anvil_log"
}
trap cleanup EXIT

"$anvil_path" --host 127.0.0.1 --port "$port" --chain-id "$chain_id" \
  --silent >"$anvil_log" 2>&1 &
anvil_pid=$!
rpc="http://127.0.0.1:$port"
ready=0
for _ in $(seq 1 50); do
  if "$cast_path" chain-id --rpc-url "$rpc" >/dev/null 2>&1; then ready=1; break; fi
  sleep 0.1
done
[[ "$ready" == 1 ]] || die "anvil failed to start (see $anvil_log)"

deploy() { # deploy <bin-file> <ctor-sig> [ctor-args...]
  local binfile="$1" sig="$2"; shift 2
  local bytecode encoded
  bytecode="$(tr -d '\n\r ' < "$binfile")"
  [[ -n "$bytecode" ]] || die "empty bytecode: $binfile"
  if [[ -n "$sig" ]]; then
    encoded="$("$cast_path" abi-encode "$sig" "$@")"
    bytecode="${bytecode}${encoded#0x}"
  fi
  local json
  json="$("$cast_path" send --json --rpc-url "$rpc" --private-key "$owner_pk" --create "0x${bytecode}")"
  /usr/bin/python3 -I -S -c 'import json,sys; print(json.load(sys.stdin).get("contractAddress",""))' <<<"$json"
}

# --- 1. deploy ---------------------------------------------------------------
addr="$(deploy "$proj/out-evm/RwaShareRegistry.bin" \
  'constructor(uint64,uint64,uint64)' 1000000 50000 100000)"
[[ -n "$addr" && "$addr" != "null" ]] || die "deploy RwaShareRegistry failed"
echo "rwa-share-anvil: RwaShareRegistry=$addr" >&2

# shellcheck disable=SC2207
holder_words=($(principal_words_from_addr "$holder"))
# shellcheck disable=SC2207
recipient_words=($(principal_words_from_addr "$recipient"))
# shellcheck disable=SC2207
stranger_words=($(principal_words_from_addr "$stranger"))
[[ ${#holder_words[@]} -eq 9 && ${#recipient_words[@]} -eq 9 && ${#stranger_words[@]} -eq 9 ]] \
  || die "principal leaves wrong"

p9_sig='uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64'
issue_sig="issue(${p9_sig},uint64)(uint64)"
set_allow_sig="setAllow(${p9_sig},uint64)(uint64)"
transfer_sig="transfer(${p9_sig},uint64)(uint64)"
balance_of_sig="balanceOf(${p9_sig})(uint64)"
is_allowed_sig="isAllowed(${p9_sig})(bool)"

require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$addr" 'issuedTotal()(uint64)')" \
  "0" "fresh issuedTotal"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$addr" 'policy()(uint64)')" \
  "50000" "fresh policy=maxPerTx"

# --- 2. owner issue ----------------------------------------------------------
"$cast_path" send --rpc-url "$rpc" --private-key "$owner_pk" "$addr" \
  "$issue_sig" "${holder_words[@]}" 100000 >/dev/null \
  || die "owner issue(holder,100000) failed"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$addr" 'issuedTotal()(uint64)')" \
  "100000" "issuedTotal after issue"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$addr" "$balance_of_sig" "${holder_words[@]}")" \
  "100000" "balanceOf(holder) after issue"
echo "rwa-share-anvil: owner issue ok" >&2

# --- 3. negative: non-owner issue ---------------------------------------------
if "$cast_path" send --rpc-url "$rpc" --private-key "$holder_pk" "$addr" \
    "$issue_sig" "${holder_words[@]}" 1 >/dev/null 2>&1; then
  die "non-owner issue unexpectedly succeeded"
fi
echo "rwa-share-anvil: neg non-owner issue reverts" >&2

# --- 4. allowlist --------------------------------------------------------------
"$cast_path" send --rpc-url "$rpc" --private-key "$owner_pk" "$addr" \
  "$set_allow_sig" "${recipient_words[@]}" 1 >/dev/null \
  || die "owner setAllow(recipient,1) failed"
require_bool_true "$("$cast_path" call --rpc-url "$rpc" "$addr" "$is_allowed_sig" "${recipient_words[@]}")" \
  "isAllowed(recipient)"
require_bool_false "$("$cast_path" call --rpc-url "$rpc" "$addr" "$is_allowed_sig" "${stranger_words[@]}")" \
  "isAllowed(stranger)"
echo "rwa-share-anvil: allowlist ok" >&2

# --- 5. holder → recipient transfers (positive) --------------------------------
"$cast_path" send --rpc-url "$rpc" --private-key "$holder_pk" "$addr" \
  "$transfer_sig" "${recipient_words[@]}" 40000 >/dev/null \
  || die "transfer #1 failed"
"$cast_path" send --rpc-url "$rpc" --private-key "$holder_pk" "$addr" \
  "$transfer_sig" "${recipient_words[@]}" 40000 >/dev/null \
  || die "transfer #2 failed"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$addr" "$balance_of_sig" "${holder_words[@]}")" \
  "20000" "balanceOf(holder) after two transfers"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$addr" "$balance_of_sig" "${recipient_words[@]}")" \
  "80000" "balanceOf(recipient) after two transfers"
echo "rwa-share-anvil: transfers 2x40000 ok (windowSpent=80000)" >&2

# --- 6. negative: window cap (80000+40000 > 100000) -----------------------------
if "$cast_path" send --rpc-url "$rpc" --private-key "$holder_pk" "$addr" \
    "$transfer_sig" "${recipient_words[@]}" 40000 >/dev/null 2>&1; then
  die "window-cap-exceeding transfer unexpectedly succeeded"
fi
echo "rwa-share-anvil: neg window cap reverts" >&2

# --- 7. negative: per-tx cap (60000 > 50000) ------------------------------------
if "$cast_path" send --rpc-url "$rpc" --private-key "$holder_pk" "$addr" \
    "$transfer_sig" "${recipient_words[@]}" 60000 >/dev/null 2>&1; then
  die "per-tx-cap-exceeding transfer unexpectedly succeeded"
fi
echo "rwa-share-anvil: neg per-tx cap reverts" >&2

# --- 8. negative: non-allowlisted recipient -------------------------------------
if "$cast_path" send --rpc-url "$rpc" --private-key "$holder_pk" "$addr" \
    "$transfer_sig" "${stranger_words[@]}" 1000 >/dev/null 2>&1; then
  die "non-allowlisted transfer unexpectedly succeeded"
fi
echo "rwa-share-anvil: neg non-allowlisted transfer reverts" >&2

# --- 9. negatives leave state unchanged -----------------------------------------
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$addr" "$balance_of_sig" "${holder_words[@]}")" \
  "20000" "holder balance unchanged after negatives"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$addr" "$balance_of_sig" "${recipient_words[@]}")" \
  "80000" "recipient balance unchanged after negatives"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$addr" 'issuedTotal()(uint64)')" \
  "100000" "issuedTotal unchanged"

echo "rwa-share-anvil: ok (deploy + issue + allowlist + 2 transfers + 3 negative paths)" >&2
exit 0
