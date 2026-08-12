#!/usr/bin/env bash
# ADR-0031 S3: ChainIdCheck (context.chainId → chainid() / CHAINID)
# Anvil engineering gate. Real local_runtime evidence only (not formal C-3 /
# Reference↔Anvil closure).
#
# Scenarios:
#   1. deploy ChainIdCheck on Anvil with known --chain-id
#   2. view chainId() via eth_call == cast chain-id / eth_chainId
#   3. entry stamp(); get() == same chain id (stable across blocks)
#   4. post-stamp view chainId() still matches
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
    echo "evm-chainid-anvil: explicit skip: missing $tool (optional; not pass)" >&2
    exit 0
  fi
done

die() { echo "evm-chainid-anvil: FAIL: $*" >&2; exit 1; }

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
echo "evm-chainid-anvil: building proof-forge-next (lake build proof_forge_next)" >&2
lake build proof_forge_next || die "lake build proof_forge_next failed"
if [[ ! -x "$cli" ]]; then
  echo "evm-chainid-anvil: explicit skip: product CLI missing (optional; not pass)" >&2
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
chainid_out="$root/build/v2/chainidcheck-evm${artifact_suffix}"
rm -rf "$chainid_out"
if [[ ${#build_profile_args[@]} -gt 0 ]]; then
  lake env "$cli" build Examples/ChainIdCheck.lean \
    --module Examples.ChainIdCheck --target evm "${build_profile_args[@]}" \
    -o "$chainid_out" \
    || die "product build of ChainIdCheck (evm profile=$evm_profile) failed"
else
  lake env "$cli" build Examples/ChainIdCheck.lean \
    --module Examples.ChainIdCheck --target evm -o "$chainid_out" \
    || die "product build of ChainIdCheck (evm default profile) failed"
fi
[[ -s "$chainid_out/ChainIdCheck.bin" ]] || die "ChainIdCheck.bin missing"

# --- anvil -----------------------------------------------------------------
port=$((19745 + RANDOM % 1000))
chain_id="${PF_EVM_CHAIN_ID:-31339}"
# Anvil default account #0 (deployer).
pk=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

anvil_log="$(mktemp "${TMPDIR:-/tmp}/pf-chainid-anvil.XXXXXX.log")"
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
  echo "evm-chainid-anvil: explicit skip: anvil failed to start (optional; not pass; see $anvil_log)" >&2
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
rpc_block_chainid() {
  local raw
  raw="$("$cast_path" rpc --rpc-url "$rpc" eth_blockNumber)"
  # cast rpc may print quoted "0x…" JSON string
  raw="$(echo "$raw" | tr -d '"[:space:]')"
  to_dec "$raw"
}

# --- 1. deploy --------------------------------------------------------------
addr="$(deploy "$chainid_out/ChainIdCheck.bin" 'constructor(uint64)' 0)"
[[ -n "$addr" && "$addr" != "null" ]] || die "deploy ChainIdCheck failed"
echo "evm-chainid-anvil: ChainIdCheck=$addr" >&2

got="$("$cast_path" call --rpc-url "$rpc" "$addr" 'get()(uint64)')"
require_uint_equal "$got" "0" "constructor get() must return initial=0"

# --- 2. view chainId() == eth_chainId / cast chain-id -----------------------
rpc_chain_id() {
  local raw
  raw="$("$cast_path" chain-id --rpc-url "$rpc")"
  to_dec "$raw"
}

cid="$(rpc_chain_id)"
require_uint_equal "$cid" "$(to_dec "$chain_id")" \
  "anvil cast chain-id must equal configured --chain-id"

view_c="$("$cast_path" call --rpc-url "$rpc" "$addr" 'chainId()(uint64)')"
require_uint_equal "$view_c" "$cid" \
  "chainId() must equal eth/cast chain-id (CHAINID / context.chainId)"
echo "evm-chainid-anvil: chainId() == cast chain-id ($cid) ok" >&2

# --- 3. stamp() entry: get() == chain id (stable; not block-dependent) ------
tx_json="$("$cast_path" send --json --rpc-url "$rpc" --private-key "$pk" \
  "$addr" 'stamp()(uint64)')"
tx_hash="$(/usr/bin/python3 -I -S -c 'import json,sys; d=json.load(sys.stdin); print(d.get("transactionHash") or d.get("hash") or "")' <<<"$tx_json")"
[[ -n "$tx_hash" ]] || die "stamp() did not return a transaction hash"
# Wait for receipt so state is settled.
"$cast_path" receipt --rpc-url "$rpc" "$tx_hash" >/dev/null
stored="$("$cast_path" call --rpc-url "$rpc" "$addr" 'get()(uint64)')"
require_uint_equal "$stored" "$cid" \
  "get() after stamp() must equal chain id (CHAINID at execute)"
echo "evm-chainid-anvil: stamp() → get() == chain-id ($cid) ok" >&2

# --- 4. post-stamp view still tracks chain id --------------------------------
view_c2="$("$cast_path" call --rpc-url "$rpc" "$addr" 'chainId()(uint64)')"
require_uint_equal "$view_c2" "$cid" \
  "post-stamp chainId() must equal cast chain-id"
# Mine an empty block (send 0-value self-tx) and re-check stability.
"$cast_path" rpc --rpc-url "$rpc" anvil_mine 1 >/dev/null 2>&1 || true
view_c3="$("$cast_path" call --rpc-url "$rpc" "$addr" 'chainId()(uint64)')"
require_uint_equal "$view_c3" "$cid" \
  "chainId() must stay stable after mining"
echo "evm-chainid-anvil: post-mine chainId() still $cid ok" >&2

echo "evm-chainid-anvil: ok (deploy + view CHAINID + stamp + stability)" >&2
exit 0
