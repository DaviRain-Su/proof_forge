#!/usr/bin/env bash
# EXT-CRYPTO EVM: deploy the real product-built EcdsaRecoverCheck artifact and
# pin ecrecover precompile 0x01 against a cast-signed known vector (Anvil
# account #0). Engineering host-optional companion only: not formal C-3,
# EXT-CRYPTO completion, or Anvil lossless OutcomeWire evidence.
#
# Skip-clean (exit 0) when locked anvil/cast/solc or the product CLI are
# unavailable. When tools are present, every build/runtime assertion is hard.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

skip_clean() {
  echo "evm-ecdsa-recover-anvil: explicit skip: $* (optional; not pass)" >&2
  exit 0
}

die() {
  echo "evm-ecdsa-recover-anvil: FAIL: $*" >&2
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
echo "evm-ecdsa-recover-anvil: building proof-forge-next (lake build proof_forge_next)" >&2
lake build proof_forge_next || die "lake build proof_forge_next failed"
[[ -x "$cli" ]] || skip_clean "product CLI missing after lake build"

out="$root/build/v2/ecdsa-recover-check-evm${artifact_suffix}"
rm -rf "$out"
if [[ ${#build_profile_args[@]} -gt 0 ]]; then
  lake env "$cli" build Examples/EcdsaRecoverCheck.lean \
    --module Examples.EcdsaRecoverCheck --target evm "${build_profile_args[@]}" \
    -o "$out" \
    || die "product build of EcdsaRecoverCheck (evm profile=$evm_profile) failed"
else
  lake env "$cli" build Examples/EcdsaRecoverCheck.lean \
    --module Examples.EcdsaRecoverCheck --target evm -o "$out" \
    || die "product build of EcdsaRecoverCheck (evm default profile) failed"
fi

yul="$out/EcdsaRecoverCheck.yul"
bin="$out/EcdsaRecoverCheck.bin"
abi="$out/EcdsaRecoverCheck.abi.json"
[[ -s "$yul" ]] || die "product EcdsaRecoverCheck.yul missing"
[[ -s "$bin" ]] || die "product EcdsaRecoverCheck.bin missing"
[[ -s "$abi" ]] || die "product EcdsaRecoverCheck.abi.json missing"
grep -Fq 'staticcall(gas(), 0x1, 0, 128, 0, 32)' "$yul" \
  || die "product Yul is missing exact ecrecover STATICCALL"
grep -Fq 'eq(returndatasize(), 32)' "$yul" \
  || die "product Yul is missing Solidity-ecrecover short-returndata → zero word"
grep -Fq '"name":"recover"' "$abi" \
  || die "product ABI is missing recover"
grep -Fq '"type":"uint256"' "$abi" \
  || die "product ABI is missing UInt256 spelling"

hashed_pf_crypto="$("$cast_path" keccak 'pf.crypto')" \
  || die "cast keccak pf.crypto failed"
hashed_pf_crypto="${hashed_pf_crypto##*0x}"
hashed_pf_crypto="${hashed_pf_crypto: -40}"
[[ ${#hashed_pf_crypto} -eq 40 ]] \
  || die "unexpected cast keccak output for pf.crypto"
if grep -Fiq "call(gas(), 0x${hashed_pf_crypto}" "$yul"; then
  die "product Yul contains forbidden hashed pf.crypto CALL target"
fi
echo "evm-ecdsa-recover-anvil: product Yul/bin provenance + precompile shape ok" >&2

# Anvil account #0; message hash is an arbitrary fixed 32-byte word.
pk=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
expected_signer="$("$cast_path" wallet address --private-key "$pk")" \
  || die "cast wallet address failed"
hash=0x456e9aea5e197a1f1af7a3e5180ac62c77a538785a0b76e52878357befa1eb5b
sig="$("$cast_path" wallet sign --private-key "$pk" --no-hash "$hash")" \
  || die "cast wallet sign failed"
sig_hex="${sig#0x}"
r="0x${sig_hex:0:64}"
s="0x${sig_hex:64:64}"
v_byte="${sig_hex:128:2}"
v_dec=$((16#$v_byte))
[[ "$v_dec" == "27" || "$v_dec" == "28" ]] \
  || die "unexpected signature v byte 0x${v_byte} (want 27/28)"
expected_word="$(/usr/bin/python3 -I -S -c \
  'import sys; a=int(sys.argv[1],16); print(f"0x{a:064x}")' \
  "${expected_signer}")"

word_hex() {
  local raw="$1"
  /usr/bin/python3 -I -S -c '
import sys
token = sys.argv[1].strip().split()[0]
try:
    value = int(token, 0)
except ValueError as exc:
    raise SystemExit(f"invalid uint256 output {sys.argv[1]!r}: {exc}")
if value < 0 or value >= 1 << 256:
    raise SystemExit(f"uint256 output out of range: {value}")
print(f"0x{value:064x}")
' "$raw"
}

require_word_equal() {
  local actual_raw="$1" expected="$2" message="$3" actual
  actual="$(word_hex "$actual_raw")" \
    || die "$message (cannot decode raw output '$actual_raw')"
  [[ "$actual" == "$expected" ]] \
    || die "$message (expected '$expected', got '$actual'; raw '$actual_raw')"
}

port=$((20855 + RANDOM % 1000))
anvil_log="$(mktemp "${TMPDIR:-/tmp}/pf-ecdsa-recover-anvil.XXXXXX.log")"
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
    || die "deploying product EcdsaRecoverCheck.bin failed"
  /usr/bin/python3 -I -S -c \
    'import json,sys; print(json.load(sys.stdin).get("contractAddress", ""))' \
    <<<"$json"
}

send_recover() {
  local json tx_hash
  json="$("$cast_path" send --json --rpc-url "$rpc" --private-key "$pk" \
    "$addr" 'recover(uint256,uint256,uint256,uint256)(uint256)' \
    "$hash" "$v_dec" "$r" "$s")" \
    || die "recover(...) transaction failed"
  tx_hash="$(/usr/bin/python3 -I -S -c \
    'import json,sys; d=json.load(sys.stdin); print(d.get("transactionHash") or d.get("hash") or "")' \
    <<<"$json")"
  [[ -n "$tx_hash" ]] || die "recover(...) returned no transaction hash"
  "$cast_path" receipt --rpc-url "$rpc" "$tx_hash" >/dev/null \
    || die "recover(...) receipt failed"
}

addr="$(deploy_product)"
[[ -n "$addr" && "$addr" != "null" ]] || die "product deployment returned no address"
echo "evm-ecdsa-recover-anvil: EcdsaRecoverCheck=$addr signer=$expected_signer" >&2

call_out="$("$cast_path" call --rpc-url "$rpc" "$addr" \
  'recover(uint256,uint256,uint256,uint256)(uint256)' \
  "$hash" "$v_dec" "$r" "$s")" \
  || die "eth_call recover(...) failed"
require_word_equal "$call_out" "$expected_word" \
  "recover(known vector) must equal left-padded signer address"
send_recover
stored="$("$cast_path" call --rpc-url "$rpc" "$addr" 'get()(uint256)')" \
  || die "get() after recover failed"
require_word_equal "$stored" "$expected_word" \
  "get() after recover must return the stored address word"

# Bad v yields empty precompile returndata → product returns the zero word
# (Solidity ecrecover), not a hashed CALL fallback or auto-revert.
bad_v=0
zero_word=0x0000000000000000000000000000000000000000000000000000000000000000
fail_out="$("$cast_path" call --rpc-url "$rpc" "$addr" \
  'recover(uint256,uint256,uint256,uint256)(uint256)' \
  "$hash" "$bad_v" "$r" "$s")" \
  || die "eth_call recover(bad v) failed"
require_word_equal "$fail_out" "$zero_word" \
  "recover(bad v) must return zero word (no auto-revert)"

echo "evm-ecdsa-recover-anvil: ok (real product artifact + precompile 0x01 known vector; engineering only)" >&2
exit 0
