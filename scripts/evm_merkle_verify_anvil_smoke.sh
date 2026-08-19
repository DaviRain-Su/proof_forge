#!/usr/bin/env bash
# CAP-X-MERKLE-EVM-ANVIL: deploy the real product-built MerkleVerifyCheck
# artifact and pin OpenZeppelin sorted-pair keccak256(0, 64) D=2 verify
# against vectors computed with locked `cast keccak` (not Python hashlib).
# Engineering host-optional companion only: not formal C-3, EXT-CRYPTO
# completion, ICS-23/positional proof, or Anvil lossless OutcomeWire evidence.
#
# Skip-clean (exit 0) when locked anvil/cast/solc or the product CLI are
# unavailable. When tools are present, every build/runtime assertion is hard.
# No hand-written caller or fabricated result is permitted.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

skip_clean() {
  echo "evm-merkle-verify-anvil: explicit skip: $* (optional; not pass)" >&2
  exit 0
}

die() {
  echo "evm-merkle-verify-anvil: FAIL: $*" >&2
  exit 1
}

case "$(uname -s)" in
  Darwin) default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64" ;;
  Linux) default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/linux-$(uname -m)" ;;
  *) skip_clean "unsupported host platform $(uname -s)" ;;
esac

foundry_bin="${FOUNDRY_BIN:-${PROOF_FORGE_TOOL_ROOT:-$default_tool_root}}"
anvil_path="$foundry_bin/anvil"
cast_path="$foundry_bin/cast"
solc_path="$foundry_bin/solc"

for tool in "$anvil_path" "$cast_path" "$solc_path"; do
  [[ -x "$tool" ]] || skip_clean "missing $tool"
done

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
echo "evm-merkle-verify-anvil: building proof-forge-next (lake build proof_forge_next)" >&2
flock /tmp/pf-honesty-lake.lock bash -c 'lake build proof_forge_next' \
  || die "lake build proof_forge_next failed"
[[ -x "$cli" ]] || skip_clean "product CLI missing after lake build"

out="$root/build/v2/merkle-verify-check-evm${artifact_suffix}"
rm -rf "$out"
if [[ ${#build_profile_args[@]} -gt 0 ]]; then
  flock /tmp/pf-honesty-lake.lock bash -c \
    'cli="$1"; out="$2"; shift 2
     lake env "$cli" build Examples/MerkleVerifyCheck.lean \
       --module Examples.MerkleVerifyCheck --target evm "$@" -o "$out"' \
    _ "$cli" "$out" "${build_profile_args[@]}" \
    || die "product build of MerkleVerifyCheck (evm profile=$evm_profile) failed"
else
  flock /tmp/pf-honesty-lake.lock bash -c \
    'lake env "$1" build Examples/MerkleVerifyCheck.lean \
       --module Examples.MerkleVerifyCheck --target evm -o "$2"' \
    _ "$cli" "$out" \
    || die "product build of MerkleVerifyCheck (evm default profile) failed"
fi

yul="$out/MerkleVerifyCheck.yul"
bin="$out/MerkleVerifyCheck.bin"
abi="$out/MerkleVerifyCheck.abi.json"
[[ -s "$yul" ]] || die "product MerkleVerifyCheck.yul missing"
[[ -s "$bin" ]] || die "product MerkleVerifyCheck.bin missing"
[[ -s "$abi" ]] || die "product MerkleVerifyCheck.abi.json missing"

keccak64_count="$(grep -Fo 'keccak256(0, 64)' "$yul" | wc -l | tr -d ' ')"
[[ "$keccak64_count" -ge 2 ]] \
  || die "product Yul must emit >=2 keccak256(0, 64) (D=2), got ${keccak64_count}"
grep -Fq 'lt(' "$yul" \
  || die "product Yul is missing lt( sorted-pair mux"
grep -Fq 'mstore(0,' "$yul" \
  || die "product Yul is missing mstore(0,"
grep -Fq 'mstore(32,' "$yul" \
  || die "product Yul is missing mstore(32,"
grep -Fq 'mstore(64,' "$yul" \
  || die "product Yul is missing mstore(64,"
grep -Fq 'eq(mload(64),' "$yul" \
  || die "product Yul is missing eq(mload(64),"
if grep -Fq 'staticcall(gas(), 0x2' "$yul"; then
  die "product Yul contains forbidden SHA-256 precompile STATICCALL"
fi
grep -Fq '"name":"verify"' "$abi" \
  || die "product ABI is missing verify"
grep -Fq '"type":"bool"' "$abi" \
  || die "product ABI is missing Bool spelling"

hashed_pf_crypto="$("$cast_path" keccak 'pf.crypto')" \
  || die "cast keccak pf.crypto failed"
hashed_pf_crypto="${hashed_pf_crypto##*0x}"
hashed_pf_crypto="${hashed_pf_crypto: -40}"
[[ ${#hashed_pf_crypto} -eq 40 ]] \
  || die "unexpected cast keccak output for pf.crypto"
if grep -Fiq "call(gas(), 0x${hashed_pf_crypto}" "$yul"; then
  die "product Yul contains forbidden hashed pf.crypto CALL target"
fi
echo "evm-merkle-verify-anvil: product Yul/bin provenance + sorted-pair keccak shape ok" >&2

# OpenZeppelin sorted-pair: pair(a,b)=keccak256(min||max). Use locked cast
# keccak over 64 raw bytes. Python hashlib is SHA3-256, not EVM keccak.
pad32() {
  local raw="${1#0x}"
  raw="$(printf '%s' "$raw" | tr 'A-F' 'a-f')"
  printf '%064s' "$raw" | tr ' ' '0'
}

hex_lt() {
  /usr/bin/python3 -I -S -c '
import sys
a = int(sys.argv[1], 16)
b = int(sys.argv[2], 16)
raise SystemExit(0 if a < b else 1)
' "$1" "$2"
}

sorted_pair() {
  local a="$1" b="$2" min max out
  if hex_lt "$a" "$b"; then
    min="$(pad32 "$a")"
    max="$(pad32 "$b")"
  else
    min="$(pad32 "$b")"
    max="$(pad32 "$a")"
  fi
  out="$("$cast_path" keccak "0x${min}${max}")" \
    || die "cast keccak sorted-pair failed"
  printf '%s' "0x$(pad32 "$out")"
}

xor1() {
  /usr/bin/python3 -I -S -c '
import sys
value = int(sys.argv[1], 16) ^ 1
print(f"0x{value:064x}")
' "$1"
}

require_bool() {
  local raw="$1" expected="$2" message="$3" token
  token="$(printf '%s' "$raw" | tr -d '\n\r' | awk '{print $1}')"
  case "$token" in
    true|false) ;;
    *) die "$message (cannot decode bool '$raw')" ;;
  esac
  [[ "$token" == "$expected" ]] \
    || die "$message (expected '$expected', got '$token'; raw '$raw')"
}

leaf=1
s0=2
s1=3
layer0="$(sorted_pair "$leaf" "$s0")"
root="$(sorted_pair "$layer0" "$s1")"
bad_root="$(xor1 "$root")"
wrong_s1=4

echo "evm-merkle-verify-anvil: D=2 leaf=$leaf s0=$s0 s1=$s1 root=$root" >&2

port=$((20865 + RANDOM % 1000))
pk=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
anvil_log="$(mktemp "${TMPDIR:-/tmp}/pf-merkle-verify-anvil.XXXXXX.log")"
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
  if "$cast_path" chain-id --rpc-url "$rpc" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.1
done
[[ "$ready" == 1 ]] \
  || skip_clean "anvil failed to start; see $anvil_log"

deploy_product() {
  local bytecode json
  bytecode="$(tr -d '\n\r ' < "$bin")"
  bytecode="${bytecode#0x}"
  [[ -n "$bytecode" ]] || die "product bytecode is empty"
  json="$("$cast_path" send --json --rpc-url "$rpc" --private-key "$pk" \
    --create "0x${bytecode}")" \
    || die "deploying product MerkleVerifyCheck.bin failed"
  /usr/bin/python3 -I -S -c \
    'import json,sys; print(json.load(sys.stdin).get("contractAddress", ""))' \
    <<<"$json"
}

send_verify() {
  local root_arg="$1" leaf_arg="$2" s0_arg="$3" s1_arg="$4" json tx_hash
  json="$("$cast_path" send --json --rpc-url "$rpc" --private-key "$pk" \
    "$addr" 'verify(uint256,uint256,uint256,uint256)(bool)' \
    "$root_arg" "$leaf_arg" "$s0_arg" "$s1_arg")" \
    || die "verify($root_arg,$leaf_arg,$s0_arg,$s1_arg) transaction failed"
  tx_hash="$(/usr/bin/python3 -I -S -c \
    'import json,sys; d=json.load(sys.stdin); print(d.get("transactionHash") or d.get("hash") or "")' \
    <<<"$json")"
  [[ -n "$tx_hash" ]] || die "verify(...) returned no transaction hash"
  "$cast_path" receipt --rpc-url "$rpc" "$tx_hash" >/dev/null \
    || die "verify(...) receipt failed"
}

addr="$(deploy_product)"
[[ -n "$addr" && "$addr" != "null" ]] || die "product deployment returned no address"
echo "evm-merkle-verify-anvil: MerkleVerifyCheck=$addr" >&2

true_call="$("$cast_path" call --rpc-url "$rpc" "$addr" \
  'verify(uint256,uint256,uint256,uint256)(bool)' \
  "$root" "$leaf" "$s0" "$s1")" \
  || die "eth_call verify(good) failed"
require_bool "$true_call" "true" "verify(leaf,s0,s1) against computed root must be true"
send_verify "$root" "$leaf" "$s0" "$s1"
stored_true="$("$cast_path" call --rpc-url "$rpc" "$addr" 'get()(bool)')" \
  || die "get() after verify(good) failed"
require_bool "$stored_true" "true" \
  "get() after verify(good) must persist true"
echo "evm-merkle-verify-anvil: true vector + persisted get() ok" >&2

# leaf/s0 swap remains true (sorted-pair commutative at layer 0).
swap_call="$("$cast_path" call --rpc-url "$rpc" "$addr" \
  'verify(uint256,uint256,uint256,uint256)(bool)' \
  "$root" "$s0" "$leaf" "$s1")" \
  || die "eth_call verify(leaf/s0 swapped) failed"
require_bool "$swap_call" "true" \
  "verify(s0,leaf,s1) must still be true (sorted-pair commutative)"
echo "evm-merkle-verify-anvil: leaf/s0 swap commutative true ok" >&2

# False paths must return false, not revert.
bad_root_call="$("$cast_path" call --rpc-url "$rpc" "$addr" \
  'verify(uint256,uint256,uint256,uint256)(bool)' \
  "$bad_root" "$leaf" "$s0" "$s1")" \
  || die "eth_call verify(root xor 1) failed (must return false, not revert)"
require_bool "$bad_root_call" "false" "verify(root xor 1) must be false"

wrong_sib_call="$("$cast_path" call --rpc-url "$rpc" "$addr" \
  'verify(uint256,uint256,uint256,uint256)(bool)' \
  "$root" "$leaf" "$s0" "$wrong_s1")" \
  || die "eth_call verify(wrong sibling) failed (must return false, not revert)"
require_bool "$wrong_sib_call" "false" "verify(wrong s1) must be false"
send_verify "$root" "$leaf" "$s0" "$wrong_s1"
stored_false="$("$cast_path" call --rpc-url "$rpc" "$addr" 'get()(bool)')" \
  || die "get() after verify(wrong sibling) failed"
require_bool "$stored_false" "false" \
  "get() after verify(wrong sibling) must persist false"
echo "evm-merkle-verify-anvil: false-not-revert (root xor 1 + wrong sibling) ok" >&2

echo "evm-merkle-verify-anvil: ok (real product artifact + D=2 sorted-pair keccak; engineering only)" >&2
exit 0
