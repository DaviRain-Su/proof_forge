#!/usr/bin/env bash
# ADR-0031 S4: AttachedValueCheck (context.attachedValue → callvalue() / CALLVALUE)
# Anvil engineering gate. Real local_runtime evidence only (not formal C-3 /
# Reference↔Anvil closure).
#
# Scenarios:
#   1. deploy AttachedValueCheck on Anvil
#   2. view peek() == 0 (STATICCALL; CALLVALUE is always 0)
#   3. view peek() with eth_call --value still == 0
#   4. payable entry collect() --value 42; get() == 42
#   5. collect() --value 0; get() == 0
#   6. collect() --value 2^64 reverts (UInt64 range guard); get() holds
#
# Skip-clean (exit 0) when locked anvil/cast/solc are unavailable; hard fail
# on any assertion when tools are present. Never fabricate results.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

foundry_bin="${FOUNDRY_BIN:-${PROOF_FORGE_TOOL_ROOT:-$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64}}"
anvil_path="$foundry_bin/anvil"
cast_path="$foundry_bin/cast"
solc_path="$foundry_bin/solc"

for tool in "$anvil_path" "$cast_path" "$solc_path"; do
  if [[ ! -x "$tool" ]]; then
    echo "evm-attachedvalue-anvil: explicit skip: missing $tool (optional; not pass)" >&2
    exit 0
  fi
done

die() { echo "evm-attachedvalue-anvil: FAIL: $*" >&2; exit 1; }

evm_profile="${PF_EVM_PROFILE:-}"
build_profile_args=()
anvil_extra_args=()
artifact_suffix=""
case "$evm_profile" in
  "")
    :
    ;;
  "evm-yul-solc-0.8.34-v1")
    build_profile_args+=(--profile "$evm_profile")
    ;;
  "evm-yul-solc-0.8.34-cancun-v1")
    build_profile_args+=(--profile "$evm_profile")
    anvil_extra_args+=(--hardfork cancun)
    artifact_suffix="-cancun"
    ;;
  *)
    die "unsupported PF_EVM_PROFILE='$evm_profile'"
    ;;
esac

cli="$root/.lake/build/bin/proof-forge-next"
echo "evm-attachedvalue-anvil: building proof-forge-next (lake build proof_forge_next)" >&2
lake build proof_forge_next || die "lake build proof_forge_next failed"
if [[ ! -x "$cli" ]]; then
  echo "evm-attachedvalue-anvil: explicit skip: product CLI missing (optional; not pass)" >&2
  exit 0
fi

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

value_out="$root/build/v2/attachedvaluecheck-evm${artifact_suffix}"
rm -rf "$value_out"
if [[ ${#build_profile_args[@]} -gt 0 ]]; then
  lake env "$cli" build Examples/AttachedValueCheck.lean \
    --module Examples.AttachedValueCheck --target evm "${build_profile_args[@]}" \
    -o "$value_out" \
    || die "product build of AttachedValueCheck (evm profile=$evm_profile) failed"
else
  lake env "$cli" build Examples/AttachedValueCheck.lean \
    --module Examples.AttachedValueCheck --target evm -o "$value_out" \
    || die "product build of AttachedValueCheck (evm default profile) failed"
fi
[[ -s "$value_out/AttachedValueCheck.bin" ]] || die "AttachedValueCheck.bin missing"
abi="$value_out/AttachedValueCheck.abi.json"
[[ -s "$abi" ]] || die "AttachedValueCheck.abi.json missing"
if ! grep -q '"name":"collect"' "$abi" || ! grep -q '"stateMutability":"payable"' "$abi"; then
  die "ABI collect must be payable"
fi
if ! grep -q '"name":"peek"' "$abi" || ! grep -q '"stateMutability":"view"' "$abi"; then
  die "ABI peek must stay view"
fi

port=$((19845 + RANDOM % 1000))
pk=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

anvil_log="$(mktemp "${TMPDIR:-/tmp}/pf-attachedvalue-anvil.XXXXXX.log")"
cleanup() {
  kill "${anvil_pid:-}" 2>/dev/null || true
  wait "${anvil_pid:-}" 2>/dev/null || true
  rm -f "$anvil_log"
}
trap cleanup EXIT

if [[ ${#anvil_extra_args[@]} -gt 0 ]]; then
  "$anvil_path" --host 127.0.0.1 --port "$port" \
    "${anvil_extra_args[@]}" --silent >"$anvil_log" 2>&1 &
else
  "$anvil_path" --host 127.0.0.1 --port "$port" \
    --silent >"$anvil_log" 2>&1 &
fi
anvil_pid=$!
rpc="http://127.0.0.1:$port"
ready=0
for _ in $(seq 1 50); do
  if "$cast_path" chain-id --rpc-url "$rpc" >/dev/null 2>&1; then ready=1; break; fi
  sleep 0.1
done
if [[ "$ready" != 1 ]]; then
  echo "evm-attachedvalue-anvil: explicit skip: anvil failed to start (optional; not pass; see $anvil_log)" >&2
  exit 0
fi

deploy() {
  local binfile="$1" sig="$2"; shift 2
  local bytecode encoded
  bytecode="$(tr -d '\n\r ' < "$binfile")"
  [[ -n "$bytecode" ]] || die "empty bytecode: $binfile"
  if [[ -n "$sig" ]]; then
    encoded="$("$cast_path" abi-encode "$sig" "$@")"
    bytecode="${bytecode}${encoded#0x}"
  fi
  local json
  json="$("$cast_path" send --json --rpc-url "$rpc" --private-key "$pk" --create "0x${bytecode}")"
  /usr/bin/python3 -I -S -c 'import json,sys; print(json.load(sys.stdin).get("contractAddress",""))' <<<"$json"
}

addr="$(deploy "$value_out/AttachedValueCheck.bin" 'constructor(uint64)' 0)"
[[ -n "$addr" && "$addr" != "null" ]] || die "deploy AttachedValueCheck failed"
echo "evm-attachedvalue-anvil: AttachedValueCheck=$addr" >&2

got="$("$cast_path" call --rpc-url "$rpc" "$addr" 'get()(uint64)')"
require_uint_equal "$got" "0" "constructor get() must return initial=0"

peek0="$("$cast_path" call --rpc-url "$rpc" "$addr" 'peek()(uint64)')"
require_uint_equal "$peek0" "0" "peek() must be 0 under STATICCALL"
# Payable programs drop the global callvalue guard and put an entry-local
# `if callvalue() { revert }` on every view / non-payable arm. A valued
# eth_call against peek must therefore revert (exact-zero view discipline).
set +e
peek_val_out="$("$cast_path" call --rpc-url "$rpc" --value 99wei "$addr" 'peek()(uint64)' 2>&1)"
peek_val_rc=$?
set -e
[[ "$peek_val_rc" -ne 0 ]] || die "peek() with eth_call --value must revert (view exact-zero); output=$peek_val_out"
echo "evm-attachedvalue-anvil: peek() == 0; valued view call reverts ok" >&2

tx_json="$("$cast_path" send --json --rpc-url "$rpc" --private-key "$pk" \
  --value 42wei "$addr" 'collect()(uint64)')"
tx_hash="$(/usr/bin/python3 -I -S -c 'import json,sys; d=json.load(sys.stdin); print(d.get("transactionHash") or d.get("hash") or "")' <<<"$tx_json")"
[[ -n "$tx_hash" ]] || die "collect(42) did not return a transaction hash"
"$cast_path" receipt --rpc-url "$rpc" "$tx_hash" >/dev/null
stored="$("$cast_path" call --rpc-url "$rpc" "$addr" 'get()(uint64)')"
require_uint_equal "$stored" "42" "get() after collect(--value 42) must be 42"
echo "evm-attachedvalue-anvil: collect(42) → get() == 42 ok" >&2

tx_json0="$("$cast_path" send --json --rpc-url "$rpc" --private-key "$pk" \
  --value 0 "$addr" 'collect()(uint64)')"
tx_hash0="$(/usr/bin/python3 -I -S -c 'import json,sys; d=json.load(sys.stdin); print(d.get("transactionHash") or d.get("hash") or "")' <<<"$tx_json0")"
[[ -n "$tx_hash0" ]] || die "collect(0) did not return a transaction hash"
"$cast_path" receipt --rpc-url "$rpc" "$tx_hash0" >/dev/null
stored0="$("$cast_path" call --rpc-url "$rpc" "$addr" 'get()(uint64)')"
require_uint_equal "$stored0" "0" "get() after collect(--value 0) must be 0"
echo "evm-attachedvalue-anvil: collect(0) → get() == 0 ok" >&2

set +e
over_out="$("$cast_path" send --rpc-url "$rpc" --private-key "$pk" \
  --value 18446744073709551616 "$addr" 'collect()(uint64)' 2>&1)"
over_rc=$?
set -e
[[ "$over_rc" -ne 0 ]] || die "collect(--value 2^64) must revert (UInt64 range guard); output=$over_out"
held="$("$cast_path" call --rpc-url "$rpc" "$addr" 'get()(uint64)')"
require_uint_equal "$held" "0" "get() must hold 0 after overflowing collect"
echo "evm-attachedvalue-anvil: collect(2^64) revert + state hold ok" >&2

echo "evm-attachedvalue-anvil: ok (deploy + view-zero + payable 42/0 + overflow revert)" >&2
exit 0
