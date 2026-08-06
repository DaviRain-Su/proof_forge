#!/usr/bin/env bash
# ADR-0031 S2 / ADR-0030 E3: BlockHeightCheck (context.blockHeight → number())
# Anvil engineering gate. Real local_runtime evidence only (not formal C-3 /
# Reference↔Anvil closure).
#
# Scenarios:
#   1. deploy BlockHeightCheck
#   2. view height() via eth_call == cast block-number (pinned immediately)
#   3. entry stamp() mines a block; get() == receipt.blockNumber
#   4. post-stamp view height() still matches cast block-number
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
    echo "evm-blockheight-anvil: explicit skip: missing $tool (optional; not pass)" >&2
    exit 0
  fi
done

die() { echo "evm-blockheight-anvil: FAIL: $*" >&2; exit 1; }

# Keep the product profile, artifact tree, and Anvil hardfork aligned with the
# parent differential harness. Empty means the historical default profile.
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
echo "evm-blockheight-anvil: building proof-forge-next (lake build proof_forge_next)" >&2
lake build proof_forge_next || die "lake build proof_forge_next failed"
if [[ ! -x "$cli" ]]; then
  echo "evm-blockheight-anvil: explicit skip: product CLI missing (optional; not pass)" >&2
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

# --- build artifacts -------------------------------------------------------
height_out="$root/build/v2/blockheightcheck-evm${artifact_suffix}"
rm -rf "$height_out"
if [[ ${#build_profile_args[@]} -gt 0 ]]; then
  lake env "$cli" build Examples/BlockHeightCheck.lean \
    --module Examples.BlockHeightCheck --target evm "${build_profile_args[@]}" \
    -o "$height_out" \
    || die "product build of BlockHeightCheck (evm profile=$evm_profile) failed"
else
  lake env "$cli" build Examples/BlockHeightCheck.lean \
    --module Examples.BlockHeightCheck --target evm -o "$height_out" \
    || die "product build of BlockHeightCheck (evm default profile) failed"
fi
[[ -s "$height_out/BlockHeightCheck.bin" ]] || die "BlockHeightCheck.bin missing"

# --- anvil -----------------------------------------------------------------
port=$((19745 + RANDOM % 1000))
chain_id="${PF_EVM_CHAIN_ID:-31339}"
# Anvil default account #0 (deployer).
pk=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

anvil_log="$(mktemp "${TMPDIR:-/tmp}/pf-blockheight-anvil.XXXXXX.log")"
cleanup() {
  kill "${anvil_pid:-}" 2>/dev/null || true
  wait "${anvil_pid:-}" 2>/dev/null || true
  rm -f "$anvil_log"
}
trap cleanup EXIT

if [[ ${#anvil_extra_args[@]} -gt 0 ]]; then
  "$anvil_path" --host 127.0.0.1 --port "$port" --chain-id "$chain_id" \
    "${anvil_extra_args[@]}" --silent >"$anvil_log" 2>&1 &
else
  "$anvil_path" --host 127.0.0.1 --port "$port" --chain-id "$chain_id" \
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
  echo "evm-blockheight-anvil: explicit skip: anvil failed to start (optional; not pass; see $anvil_log)" >&2
  exit 0
fi

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
  json="$("$cast_path" send --json --rpc-url "$rpc" --private-key "$pk" --create "0x${bytecode}")"
  /usr/bin/python3 -I -S -c 'import json,sys; print(json.load(sys.stdin).get("contractAddress",""))' <<<"$json"
}

# Pin chain height via eth_blockNumber RPC (hex → decimal). Prefer this over
# cast block-number alone so the snapshot is a single RPC round-trip.
rpc_block_number() {
  local raw
  raw="$("$cast_path" rpc --rpc-url "$rpc" eth_blockNumber)"
  # cast rpc may print quoted "0x…" JSON string
  raw="$(echo "$raw" | tr -d '"[:space:]')"
  to_dec "$raw"
}

# --- 1. deploy --------------------------------------------------------------
addr="$(deploy "$height_out/BlockHeightCheck.bin" 'constructor(uint64)' 0)"
[[ -n "$addr" && "$addr" != "null" ]] || die "deploy BlockHeightCheck failed"
echo "evm-blockheight-anvil: BlockHeightCheck=$addr" >&2

got="$("$cast_path" call --rpc-url "$rpc" "$addr" 'get()(uint64)')"
require_uint_equal "$got" "0" "constructor get() must return initial=0"

# --- 2. view height() == eth_blockNumber (pinned immediately) -------------
# eth_call does not mine; after deploy settles, height is stable for us alone.
bn="$(rpc_block_number)"
view_h="$("$cast_path" call --rpc-url "$rpc" "$addr" 'height()(uint64)')"
# Re-pin immediately after eth_call; if Anvil advanced (external), re-read once.
bn_after="$(rpc_block_number)"
if [[ "$(to_dec "$bn")" != "$(to_dec "$bn_after")" ]]; then
  bn="$bn_after"
  view_h="$("$cast_path" call --rpc-url "$rpc" "$addr" 'height()(uint64)')"
  bn_after="$(rpc_block_number)"
  require_uint_equal "$bn" "$(to_dec "$bn_after")" \
    "block height still advancing under sole-client eth_call (unstable host)"
fi
require_uint_equal "$view_h" "$(to_dec "$bn")" \
  "height() must equal eth_blockNumber (NUMBER / context.blockHeight)"
echo "evm-blockheight-anvil: height() == eth_blockNumber ($bn) ok" >&2

# --- 3. stamp() entry: get() == receipt.blockNumber -----------------------
tx_json="$("$cast_path" send --json --rpc-url "$rpc" --private-key "$pk" \
  "$addr" 'stamp()(uint64)')"
tx_hash="$(/usr/bin/python3 -I -S -c 'import json,sys; d=json.load(sys.stdin); print(d.get("transactionHash") or d.get("hash") or "")' <<<"$tx_json")"
[[ -n "$tx_hash" ]] || die "stamp() did not return a transaction hash"
receipt_json="$("$cast_path" receipt --rpc-url "$rpc" --json "$tx_hash")"
receipt_bn="$(/usr/bin/python3 -I -S -c '
import json,sys
r=json.load(sys.stdin)
bn=r.get("blockNumber")
if bn is None:
    raise SystemExit("missing blockNumber")
if isinstance(bn, str):
    print(int(bn, 16) if bn.startswith("0x") else int(bn))
else:
    print(int(bn))
' <<<"$receipt_json")"
[[ -n "$receipt_bn" ]] || die "stamp() receipt missing blockNumber"
stored="$("$cast_path" call --rpc-url "$rpc" "$addr" 'get()(uint64)')"
require_uint_equal "$stored" "$receipt_bn" \
  "get() after stamp() must equal receipt.blockNumber (NUMBER at execute)"
echo "evm-blockheight-anvil: stamp() → get() == receipt.blockNumber ($receipt_bn) ok" >&2

# --- 4. post-stamp view height still tracks eth_blockNumber ----------------
bn2="$(rpc_block_number)"
view_h2="$("$cast_path" call --rpc-url "$rpc" "$addr" 'height()(uint64)')"
require_uint_equal "$view_h2" "$(to_dec "$bn2")" \
  "post-stamp height() must equal eth_blockNumber"
# After stamp mined a block, height should be ≥ the stamped receipt height.
view_h2_dec="$(to_dec "$view_h2")"
if ! /usr/bin/python3 -I -S -c "import sys; sys.exit(0 if int('$view_h2_dec') >= int('$receipt_bn') else 1)"; then
  die "post-stamp height() ($view_h2_dec) < receipt block ($receipt_bn)"
fi
echo "evm-blockheight-anvil: post-stamp height() == eth_blockNumber ($bn2) ok" >&2

echo "evm-blockheight-anvil: ok (deploy + view NUMBER + stamp receipt.blockNumber)" >&2
exit 0
