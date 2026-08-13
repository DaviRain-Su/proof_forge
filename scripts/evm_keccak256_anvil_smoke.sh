#!/usr/bin/env bash
# ADR-0031 SYS-S5-EVM: deploy the real product-built Keccak256Check artifact and
# pin the EVM native keccak256 opcode over one 32-byte word against two known 32-byte word vectors.
# Engineering host-optional companion only: not formal C-3, EXT-CRYPTO
# completion, or Anvil lossless OutcomeWire evidence.
#
# Skip-clean (exit 0) when locked anvil/cast/solc or the product CLI are
# unavailable. When tools are present, every build/runtime assertion is hard.
# No hand-written caller or fabricated result is permitted.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

skip_clean() {
  echo "evm-keccak256-anvil: explicit skip: $* (optional; not pass)" >&2
  exit 0
}

die() {
  echo "evm-keccak256-anvil: FAIL: $*" >&2
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
echo "evm-keccak256-anvil: building proof-forge-next (lake build proof_forge_next)" >&2
lake build proof_forge_next || die "lake build proof_forge_next failed"
[[ -x "$cli" ]] || skip_clean "product CLI missing after lake build"

out="$root/build/v2/keccak256check-evm${artifact_suffix}"
rm -rf "$out"
if [[ ${#build_profile_args[@]} -gt 0 ]]; then
  lake env "$cli" build Examples/Keccak256Check.lean \
    --module Examples.Keccak256Check --target evm "${build_profile_args[@]}" \
    -o "$out" \
    || die "product build of Keccak256Check (evm profile=$evm_profile) failed"
else
  lake env "$cli" build Examples/Keccak256Check.lean \
    --module Examples.Keccak256Check --target evm -o "$out" \
    || die "product build of Keccak256Check (evm default profile) failed"
fi

yul="$out/Keccak256Check.yul"
bin="$out/Keccak256Check.bin"
abi="$out/Keccak256Check.abi.json"
[[ -s "$yul" ]] || die "product Keccak256Check.yul missing"
[[ -s "$bin" ]] || die "product Keccak256Check.bin missing"
[[ -s "$abi" ]] || die "product Keccak256Check.abi.json missing"
grep -Fq 'keccak256(0, 32)' "$yul" \
  || die "product Yul is missing exact native keccak256(0, 32)"
grep -Fq '"name":"hashWord"' "$abi" \
  || die "product ABI is missing hashWord"
grep -Fq '"type":"uint256"' "$abi" \
  || die "product ABI is missing UInt256 spelling"

# Defense against regression to generic AddressBearing lowering. "cast keccak"
# is used only to derive the forbidden hashed target for this assertion.
hashed_pf_crypto="$("$cast_path" keccak 'pf.crypto')" \
  || die "cast keccak pf.crypto failed"
hashed_pf_crypto="${hashed_pf_crypto##*0x}"
hashed_pf_crypto="${hashed_pf_crypto: -40}"
[[ ${#hashed_pf_crypto} -eq 40 ]] \
  || die "unexpected cast keccak output for pf.crypto"
if grep -Fiq "call(gas(), 0x${hashed_pf_crypto}" "$yul"; then
  die "product Yul contains forbidden hashed pf.crypto CALL target"
fi
if grep -Fq 'staticcall(gas(), 0x2, 0, 32, 32, 32)' "$yul"; then
  die "product Yul still emits SHA-256 precompile STATICCALL for keccak256"
fi
echo "evm-keccak256-anvil: product Yul/bin provenance + native keccak256 shape ok" >&2

expected_zero="0x290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e563"
# keccak256 of (1).to_bytes(32, "big"), computed once and pinned.
expected_one="0xb10e2d527612073b26eecdfd717e6a320cf44b4afac2b0732d9fcbe2b7fa0cf6"

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

port=$((20845 + RANDOM % 1000))
pk=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
anvil_log="$(mktemp "${TMPDIR:-/tmp}/pf-keccak256-anvil.XXXXXX.log")"
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
    || die "deploying product Keccak256Check.bin failed"
  /usr/bin/python3 -I -S -c \
    'import json,sys; print(json.load(sys.stdin).get("contractAddress", ""))' \
    <<<"$json"
}

send_hash_word() {
  local input="$1" json tx_hash
  json="$("$cast_path" send --json --rpc-url "$rpc" --private-key "$pk" \
    "$addr" 'hashWord(uint256)(uint256)' "$input")" \
    || die "hashWord($input) transaction failed"
  tx_hash="$(/usr/bin/python3 -I -S -c \
    'import json,sys; d=json.load(sys.stdin); print(d.get("transactionHash") or d.get("hash") or "")' \
    <<<"$json")"
  [[ -n "$tx_hash" ]] || die "hashWord($input) returned no transaction hash"
  "$cast_path" receipt --rpc-url "$rpc" "$tx_hash" >/dev/null \
    || die "hashWord($input) receipt failed"
}

addr="$(deploy_product)"
[[ -n "$addr" && "$addr" != "null" ]] || die "product deployment returned no address"
echo "evm-keccak256-anvil: Keccak256Check=$addr" >&2

zero_call="$("$cast_path" call --rpc-url "$rpc" "$addr" \
  'hashWord(uint256)(uint256)' 0)" \
  || die "eth_call hashWord(0) failed"
require_word_equal "$zero_call" "$expected_zero" \
  "hashWord(0) must equal keccak256 of 32 zero bytes"
send_hash_word 0
stored_zero="$("$cast_path" call --rpc-url "$rpc" "$addr" 'get()(uint256)')" \
  || die "get() after hashWord(0) failed"
require_word_equal "$stored_zero" "$expected_zero" \
  "get() after hashWord(0) must return the stored digest"
echo "evm-keccak256-anvil: hashWord(0) + persisted get() known vector ok" >&2

one_call="$("$cast_path" call --rpc-url "$rpc" "$addr" \
  'hashWord(uint256)(uint256)' 1)" \
  || die "eth_call hashWord(1) failed"
require_word_equal "$one_call" "$expected_one" \
  "hashWord(1) must equal keccak256 of 32-byte big-endian 1"
echo "evm-keccak256-anvil: hashWord(1) known vector ok" >&2

echo "evm-keccak256-anvil: ok (real product artifact + native keccak256 known vectors; engineering only)" >&2
exit 0
