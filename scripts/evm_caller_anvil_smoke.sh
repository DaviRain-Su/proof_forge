#!/usr/bin/env bash
# ADR-0031 S1 / ADR-0030 E3: CallerCheck (context.caller Principal) Anvil engineering gate.
# Real local_runtime evidence only (not formal C-3 / Reference↔Anvil closure).
#
# Scenarios:
#   1. deploy CallerCheck
#   2. positive: isCaller(EOA Principal words) from that EOA → true (1)
#   3. positive view: isCallerView(EOA Principal words) via eth_call → true
#   4. negative: isCaller(wrong Principal words) from EOA → false (0)
#   5. negative view: isCallerView(wrong Principal) → false
#
# Skip-clean (exit 0) when locked anvil/cast/solc are unavailable; hard fail
# on any assertion. Never fabricate results.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

foundry_bin="${FOUNDRY_BIN:-${PROOF_FORGE_TOOL_ROOT:-$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64}}"
anvil_path="$foundry_bin/anvil"
cast_path="$foundry_bin/cast"
solc_path="$foundry_bin/solc"

for tool in "$anvil_path" "$cast_path" "$solc_path"; do
  if [[ ! -x "$tool" ]]; then
    echo "evm-caller-anvil: explicit skip: missing $tool (optional; not pass)" >&2
    exit 0
  fi
done

die() { echo "evm-caller-anvil: FAIL: $*" >&2; exit 1; }

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
echo "evm-caller-anvil: building proof-forge-next (lake build proof_forge_next)" >&2
lake build proof_forge_next || die "lake build proof_forge_next failed"
if [[ ! -x "$cli" ]]; then
  echo "evm-caller-anvil: explicit skip: product CLI missing (optional; not pass)" >&2
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

# Pack a 20-byte network-order address into Principal ABI leaves:
# len=20, w0/w1 = LE first/next 8 bytes, w2 = LE last 4 (high 32 zero), w3..w7=0.
# Matches ADR-0025 valueBytes = u32le(20)||addr20 and T10 9-leaf layout.
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

# --- build artifacts -------------------------------------------------------
caller_out="$root/build/v2/callercheck-evm${artifact_suffix}"
rm -rf "$caller_out"
if [[ ${#build_profile_args[@]} -gt 0 ]]; then
  lake env "$cli" build Examples/CallerCheck.lean \
    --module Examples.CallerCheck --target evm "${build_profile_args[@]}" \
    -o "$caller_out" \
    || die "product build of CallerCheck (evm profile=$evm_profile) failed"
else
  lake env "$cli" build Examples/CallerCheck.lean \
    --module Examples.CallerCheck --target evm -o "$caller_out" \
    || die "product build of CallerCheck (evm default profile) failed"
fi
[[ -s "$caller_out/CallerCheck.bin" ]] || die "CallerCheck.bin missing"

# --- anvil -----------------------------------------------------------------
port=$((19645 + RANDOM % 1000))
chain_id="${PF_EVM_CHAIN_ID:-31339}"
# Anvil default account #0 (deployer + caller EOA for positive path).
pk=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
eoa=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
# Anvil default account #1 (wrong Principal for negative path).
other_eoa=0x70997970C51812dc3A010C7d01b50e0d17dc79C8

anvil_log="$(mktemp "${TMPDIR:-/tmp}/pf-caller-anvil.XXXXXX.log")"
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
  echo "evm-caller-anvil: explicit skip: anvil failed to start (optional; not pass; see $anvil_log)" >&2
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

# --- 1. deploy --------------------------------------------------------------
addr="$(deploy "$caller_out/CallerCheck.bin" 'constructor(uint64)' 0)"
[[ -n "$addr" && "$addr" != "null" ]] || die "deploy CallerCheck failed"
echo "evm-caller-anvil: CallerCheck=$addr eoa=$eoa" >&2

got="$("$cast_path" call --rpc-url "$rpc" "$addr" 'get()(uint64)')"
require_uint_equal "$got" "0" "constructor get() must return initial=0"

# shellcheck disable=SC2207
eoa_words=($(principal_words_from_addr "$eoa"))
[[ ${#eoa_words[@]} -eq 9 ]] || die "eoa principal leaves wrong"
# shellcheck disable=SC2207
other_words=($(principal_words_from_addr "$other_eoa"))
[[ ${#other_words[@]} -eq 9 ]] || die "other principal leaves wrong"

is_caller_sig='isCaller(uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64)(bool)'
is_caller_view_sig='isCallerView(uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64)(bool)'

# --- 2. positive entry: msg.sender Principal == EOA words → true ----------
# eth_call defaults to from=0x000…0; force --from EOA so CALLER matches.
pos="$("$cast_path" call --rpc-url "$rpc" --from "$eoa" "$addr" \
  "$is_caller_sig" "${eoa_words[@]}")"
# cast may print true/false or 0x01/0x00
pos_norm="$(echo "$pos" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
case "$pos_norm" in
  true|0x1|0x01|0x0000000000000000000000000000000000000000000000000000000000000001|1)
    echo "evm-caller-anvil: isCaller(eoa) from eoa → true ok" >&2
    ;;
  *)
    die "isCaller(eoa) from eoa must be true, got '$pos'"
    ;;
esac

# --- 3. positive view under STATICCALL ------------------------------------
posv="$("$cast_path" call --rpc-url "$rpc" --from "$eoa" "$addr" \
  "$is_caller_view_sig" "${eoa_words[@]}")"
posv_norm="$(echo "$posv" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
case "$posv_norm" in
  true|0x1|0x01|0x0000000000000000000000000000000000000000000000000000000000000001|1)
    echo "evm-caller-anvil: isCallerView(eoa) from eoa → true ok (view-safe CALLER)" >&2
    ;;
  *)
    die "isCallerView(eoa) from eoa must be true, got '$posv'"
    ;;
esac

# --- 4. negative entry: wrong Principal words → false ---------------------
neg="$("$cast_path" call --rpc-url "$rpc" --from "$eoa" "$addr" \
  "$is_caller_sig" "${other_words[@]}")"
neg_norm="$(echo "$neg" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
case "$neg_norm" in
  false|0x0|0x00|0x0000000000000000000000000000000000000000000000000000000000000000|0)
    echo "evm-caller-anvil: isCaller(other) from eoa → false ok" >&2
    ;;
  *)
    die "isCaller(other) from eoa must be false, got '$neg'"
    ;;
esac

# --- 5. negative view -------------------------------------------------------
negv="$("$cast_path" call --rpc-url "$rpc" --from "$eoa" "$addr" \
  "$is_caller_view_sig" "${other_words[@]}")"
negv_norm="$(echo "$negv" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
case "$negv_norm" in
  false|0x0|0x00|0x0000000000000000000000000000000000000000000000000000000000000000|0)
    echo "evm-caller-anvil: isCallerView(other) from eoa → false ok" >&2
    ;;
  *)
    die "isCallerView(other) from eoa must be false, got '$negv'"
    ;;
esac

echo "evm-caller-anvil: ok (deploy + isCaller match/mismatch + view-safe CALLER)" >&2
exit 0
