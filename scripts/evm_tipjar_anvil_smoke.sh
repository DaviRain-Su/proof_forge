#!/usr/bin/env bash
# Engineering TipJar native deposit/transfer smoke on Anvil (ADR-0029 B2).
# Covers pf.assets.native.deposit exact callvalue + native.transfer full-gas
# CALL + Principal wire shape gate + payable discipline + failure propagate.
#
# Engineering only: not formal Reference↔Anvil (C-3). Not OZ/family credit.
# NEVER fabricate Anvil results.
#
# Skip-clean (exit 0) when:
#   - host platform unsupported
#   - anvil/cast unavailable
#   - product CLI or lake unavailable
#   - anvil failed to start
#
# Hard fail (exit 1) when tools+CLI are present but product build fails or any
# Anvil matrix assertion fails.
#
# Optional PF_EVM_PROFILE inheritance (same as Token companion):
#   empty / evm-yul-solc-0.8.34-v1 → build/v2/tipjar-evm
#   evm-yul-solc-0.8.34-cancun-v1 → build/v2/tipjar-evm-cancun + anvil --hardfork cancun
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "$(uname -s)" in
  Darwin) default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64" ;;
  Linux) default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/linux-$(uname -m)" ;;
  *)
    echo "evm-tipjar-anvil: explicit skip: unsupported host (optional leg; not pass)" >&2
    exit 0
    ;;
esac

foundry_bin="${FOUNDRY_BIN:-${PROOF_FORGE_TOOL_ROOT:-$default_tool_root}}"
anvil_path="$foundry_bin/anvil"
cast_path="$foundry_bin/cast"
# Prefer FOUNDRY_BIN co-located tools; only fall back to PATH when missing.
if [[ ! -x "${anvil_path:-}" ]] && command -v anvil >/dev/null 2>&1; then
  anvil_path="$(command -v anvil)"
fi
if [[ ! -x "${cast_path:-}" ]] && command -v cast >/dev/null 2>&1; then
  cast_path="$(command -v cast)"
fi
if [[ ! -x "${anvil_path:-}" || ! -x "${cast_path:-}" ]]; then
  echo "evm-tipjar-anvil: explicit skip: anvil/cast unavailable (optional leg; not pass)" >&2
  echo "evm-tipjar-anvil: engineering only; not formal Reference↔Anvil" >&2
  exit 0
fi

evm_profile="${PF_EVM_PROFILE:-}"
build_profile_args=()
artifact_suffix=""
anvil_extra_args=()
expected_profile_wire="evm-yul-solc-0.8.34-v1"
case "$evm_profile" in
  "")
    : # default product profile
    ;;
  "evm-yul-solc-0.8.34-v1")
    build_profile_args+=(--profile "$evm_profile")
    expected_profile_wire="evm-yul-solc-0.8.34-v1"
    ;;
  "evm-yul-solc-0.8.34-cancun-v1")
    build_profile_args+=(--profile "$evm_profile")
    artifact_suffix="-cancun"
    anvil_extra_args+=(--hardfork cancun)
    expected_profile_wire="evm-yul-solc-0.8.34-cancun-v1"
    echo "evm-tipjar-anvil: profile=$evm_profile → anvil --hardfork cancun" >&2
    ;;
  *)
    echo "evm-tipjar-anvil: explicit skip: unsupported PF_EVM_PROFILE='$evm_profile' (optional; not pass)" >&2
    exit 0
    ;;
esac

tipjar_out_rel="build/v2/tipjar-evm${artifact_suffix}"
tipjar_out="$root/$tipjar_out_rel"
tipjar_bin="${TIPJAR_BIN:-$tipjar_out/TipJar.bin}"
tipjar_abi="$tipjar_out/TipJar.abi.json"

tipjar_tree_matches_profile() {
  local bin="$1"
  local dir
  dir="$(dirname "$bin")"
  local evidence="$dir/evidence.json"
  local manifest="$dir/manifest.json"
  [[ -f "$bin" ]] || return 1
  if [[ "$expected_profile_wire" == "evm-yul-solc-0.8.34-cancun-v1" ]]; then
    [[ -f "$evidence" ]] && grep -q 'evm-version=cancun' "$evidence" || return 1
    [[ -f "$manifest" ]] || return 1
    grep -q "\"codegenProfile\": \"$expected_profile_wire\"" "$manifest" ||
      grep -q "\"codegenProfile\":\"$expected_profile_wire\"" "$manifest" || return 1
  else
    if [[ -f "$evidence" ]] && grep -q 'evm-version=cancun' "$evidence"; then
      return 1
    fi
    if [[ -f "$manifest" ]] && grep -q 'evm-yul-solc-0.8.34-cancun-v1' "$manifest"; then
      return 1
    fi
  fi
  return 0
}

if ! tipjar_tree_matches_profile "$tipjar_bin"; then
  echo "evm-tipjar-anvil: building TipJar EVM artifact → $tipjar_out_rel (profile=$expected_profile_wire)..." >&2
  tipjar_cli=""
  if [[ -n "${PROOF_FORGE_CLI:-}" && -x "${PROOF_FORGE_CLI}" ]]; then
    tipjar_cli="$PROOF_FORGE_CLI"
  elif [[ -x "$root/.lake/build/bin/proof-forge-next" ]]; then
    tipjar_cli="$root/.lake/build/bin/proof-forge-next"
  elif command -v proof-forge-next >/dev/null 2>&1; then
    tipjar_cli="$(command -v proof-forge-next)"
  fi
  if [[ -n "$tipjar_cli" ]] && command -v lake >/dev/null 2>&1; then
    # Product CLI refuses non-empty existing -o dirs (PF-OUTPUT-COLLISION).
    rm -rf "$tipjar_out"
    build_log="$(mktemp "${TMPDIR:-/tmp}/pf-tipjar-build.XXXXXX.log")"
    lake_root="${PF_LAKE_ROOT:-$root}"
    set +e
    if [[ ${#build_profile_args[@]} -gt 0 ]]; then
      (cd "$lake_root" && lake env bash -c 'cd "$1"; shift; exec "$@"' _ "$root" \
        "$tipjar_cli" build Examples/TipJar.lean --module Examples.TipJar --target evm \
        "${build_profile_args[@]}" -o "$tipjar_out_rel") >"$build_log" 2>&1
      build_rc=$?
    else
      (cd "$lake_root" && lake env bash -c 'cd "$1"; shift; exec "$@"' _ "$root" \
        "$tipjar_cli" build Examples/TipJar.lean --module Examples.TipJar --target evm \
        -o "$tipjar_out_rel") >"$build_log" 2>&1
      build_rc=$?
    fi
    set -e
    if [[ "$build_rc" -ne 0 ]]; then
      echo "evm-tipjar-anvil: TipJar EVM build failed (hard when tools present; profile=$expected_profile_wire)" >&2
      tail -40 "$build_log" >&2 || true
      rm -f "$build_log"
      exit 1
    fi
    rm -f "$build_log"
  else
    echo "evm-tipjar-anvil: explicit skip: product CLI or lake unavailable (optional leg; not pass)" >&2
    exit 0
  fi
  tipjar_bin="$tipjar_out/TipJar.bin"
  tipjar_abi="$tipjar_out/TipJar.abi.json"
  [[ -f "$tipjar_bin" ]] || {
    echo "evm-tipjar-anvil: TipJar.bin missing after successful build (hard)" >&2
    exit 1
  }
  if ! tipjar_tree_matches_profile "$tipjar_bin"; then
    echo "evm-tipjar-anvil: TipJar tree failed post-build profile validation (hard)" >&2
    exit 1
  fi
fi

[[ -f "$tipjar_abi" ]] || {
  echo "evm-tipjar-anvil: missing TipJar.abi.json (hard)" >&2
  exit 1
}
# Payable surface pin (product ABI).
if ! grep -q '"stateMutability":"payable"' "$tipjar_abi" \
  && ! grep -q '"stateMutability": "payable"' "$tipjar_abi"; then
  echo "evm-tipjar-anvil: TipJar.abi.json missing payable tip (hard)" >&2
  exit 1
fi
if ! grep -q '"name":"tip"' "$tipjar_abi" && ! grep -q '"name": "tip"' "$tipjar_abi"; then
  echo "evm-tipjar-anvil: TipJar.abi.json missing tip entry (hard)" >&2
  exit 1
fi

echo "evm-tipjar-anvil: engineering TipJar deposit/transfer smoke (profile=$expected_profile_wire); not formal" >&2
export FOUNDRY_BIN="$(cd "$(dirname "$anvil_path")" && pwd)"

# Normalize cast output to decimal when possible.
to_dec() {
  local x="$1"
  x="${x//$'\n'/}"
  x="${x// /}"
  if [[ -z "$x" ]]; then echo ""; return; fi
  if [[ "$x" == 0x* || "$x" == 0X* ]]; then
    /usr/bin/python3 -I -S -c "print(int('$x', 16))" 2>/dev/null || echo "$x"
  elif [[ "$x" =~ ^([0-9]+)(\ \[[0-9.eE+-]+\])?$ ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo "$x"
  fi
}

die() {
  echo "evm-tipjar-anvil: FAIL: $*" >&2
  exit 1
}

require_equal() {
  local actual="$1"
  local expected="$2"
  local message="$3"
  [[ "$actual" == "$expected" ]] || die "$message (expected '$expected', got '$actual')"
}

require_uint_equal() {
  local actual="$1"
  local expected="$2"
  local message="$3"
  local canonical
  canonical="$(to_dec "$actual")"
  [[ -n "$canonical" ]] || die "$message (empty uint output, raw='$actual')"
  require_equal "$canonical" "$expected" "$message"
}

# Pack EOA 20-byte network-order address into TipJar Principal ABI leaves:
#   dst_len=20, w0/w1 = LE-packed first/next 8 body bytes,
#   w2 = LE-packed last 4 body bytes (high 32 bits 0), w3..w7 = 0.
# Mirrors EmitIRV1 nativeTransfer: LE body words → network-order CALL address.
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

port=$((18545 + RANDOM % 1000))
chain_id="${PF_EVM_CHAIN_ID:-31338}"
# Anvil default key / account 0
pk=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
deployer=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
# Anvil account 1 — tip destination EOA
dst_eoa=0x70997970C51812dc3A010C7d01b50e0d17dc79C8

anvil_log="$(mktemp "${TMPDIR:-/tmp}/pf-tipjar-anvil.XXXXXX.log")"
cleanup_tipjar() {
  kill "${anvil_pid:-}" 2>/dev/null || true
  wait "${anvil_pid:-}" 2>/dev/null || true
  rm -f "$anvil_log"
}
trap cleanup_tipjar EXIT

if ((${#anvil_extra_args[@]})); then
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
  if "$cast_path" chain-id --rpc-url "$rpc" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.1
done
if [[ "$ready" != 1 ]]; then
  echo "evm-tipjar-anvil: explicit skip: anvil failed to start (optional; not pass; see $anvil_log)" >&2
  exit 0
fi

# ---------------------------------------------------------------------------
# a. Deploy TipJar(initial=7)
# ---------------------------------------------------------------------------
bytecode="$(tr -d '\n\r ' < "$tipjar_bin")"
[[ -n "$bytecode" ]] || die "TipJar.bin empty"
encoded="$("$cast_path" abi-encode 'constructor(uint64)' 7)"
deploy_json="$("$cast_path" send --json --rpc-url "$rpc" --private-key "$pk" \
  --create "0x${bytecode}${encoded#0x}")"
addr="$(/usr/bin/python3 -I -S -c 'import json,sys; print(json.load(sys.stdin).get("contractAddress",""))' <<<"$deploy_json")"
[[ -n "$addr" && "$addr" != "null" ]] || die "deploy TipJar failed (no contractAddress)"
deploy_tx="$(/usr/bin/python3 -I -S -c 'import json,sys; print(json.load(sys.stdin).get("transactionHash",""))' <<<"$deploy_json")"
echo "evm-tipjar-anvil: deployed TipJar at $addr (tx=$deploy_tx initial=7)" >&2

got="$("$cast_path" call --rpc-url "$rpc" "$addr" 'get()(uint64)')"
require_uint_equal "$got" "7" "constructor get() must return initial"

# Snapshot balances before tip.
dst_bal_before="$(to_dec "$("$cast_path" balance --rpc-url "$rpc" "$dst_eoa")")"
contract_bal_before="$(to_dec "$("$cast_path" balance --rpc-url "$rpc" "$addr")")"
require_equal "$contract_bal_before" "0" "fresh TipJar balance must be 0"

# Principal leaves for dst_eoa.
# shellcheck disable=SC2207
dst_words=($(principal_words_from_addr "$dst_eoa"))
[[ ${#dst_words[@]} -eq 9 ]] || die "principal_words_from_addr produced ${#dst_words[@]} fields"

tip_sig='tip(uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64)(uint64)'
tip_sig_send='tip(uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64)'
amount=1000

# ---------------------------------------------------------------------------
# b. tip(dst_eoa, 1000) with --value 1000
# ---------------------------------------------------------------------------
tip_json="$("$cast_path" send --json --rpc-url "$rpc" --private-key "$pk" --value "$amount" \
  "$addr" "$tip_sig_send" \
  "${dst_words[0]}" "${dst_words[1]}" "${dst_words[2]}" "${dst_words[3]}" \
  "${dst_words[4]}" "${dst_words[5]}" "${dst_words[6]}" "${dst_words[7]}" \
  "${dst_words[8]}" "$amount")"
tip_tx="$(/usr/bin/python3 -I -S -c 'import json,sys; print(json.load(sys.stdin).get("transactionHash",""))' <<<"$tip_json")"
tip_status="$(/usr/bin/python3 -I -S -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' <<<"$tip_json")"
tip_gas="$(/usr/bin/python3 -I -S -c 'import json,sys; d=json.load(sys.stdin); print(d.get("gasUsed", d.get("cumulativeGasUsed","")))' <<<"$tip_json")"
[[ "$tip_status" == "0x1" || "$tip_status" == "1" ]] || die "tip success expected status=1 got $tip_status (tx=$tip_tx)"
echo "evm-tipjar-anvil: tip ok tx=$tip_tx gasUsed=$tip_gas amount=$amount" >&2

dst_bal_after="$(to_dec "$("$cast_path" balance --rpc-url "$rpc" "$dst_eoa")")"
contract_bal_after="$(to_dec "$("$cast_path" balance --rpc-url "$rpc" "$addr")")"
dst_delta="$(/usr/bin/python3 -I -S -c "print(int('$dst_bal_after') - int('$dst_bal_before'))")"
require_equal "$dst_delta" "$amount" "dst EOA balance must increase by tip amount"
require_equal "$contract_bal_after" "0" "contract balance must net 0 after deposit+transfer"

got="$("$cast_path" call --rpc-url "$rpc" "$addr" 'get()(uint64)')"
require_uint_equal "$got" "1007" "get() after tip must be initial+amount (7+1000)"
echo "evm-tipjar-anvil: balances ok dst_delta=$dst_delta contract=$contract_bal_after get=1007" >&2

# ---------------------------------------------------------------------------
# c. Negative: --value 999 tip(..., amount=1000) → callvalue exact-eq revert
# ---------------------------------------------------------------------------
if "$cast_path" send --rpc-url "$rpc" --private-key "$pk" --value 999 \
    "$addr" "$tip_sig_send" \
    "${dst_words[0]}" "${dst_words[1]}" "${dst_words[2]}" "${dst_words[3]}" \
    "${dst_words[4]}" "${dst_words[5]}" "${dst_words[6]}" "${dst_words[7]}" \
    "${dst_words[8]}" 1000 >/dev/null 2>&1; then
  die "tip with callvalue!=amount unexpectedly succeeded"
fi
got="$("$cast_path" call --rpc-url "$rpc" "$addr" 'get()(uint64)')"
require_uint_equal "$got" "1007" "callvalue mismatch must leave tips unchanged"
echo "evm-tipjar-anvil: neg callvalue mismatch reverts (state held)" >&2

# ---------------------------------------------------------------------------
# d. Negative: dst len=21 → Principal wire shape gate revert
# ---------------------------------------------------------------------------
if "$cast_path" send --rpc-url "$rpc" --private-key "$pk" --value 1 \
    "$addr" "$tip_sig_send" \
    21 "${dst_words[1]}" "${dst_words[2]}" "${dst_words[3]}" \
    "${dst_words[4]}" "${dst_words[5]}" "${dst_words[6]}" "${dst_words[7]}" \
    "${dst_words[8]}" 1 >/dev/null 2>&1; then
  die "tip with dst_len=21 unexpectedly succeeded"
fi
# High limb nonzero (w3 != 0) while len=20
if "$cast_path" send --rpc-url "$rpc" --private-key "$pk" --value 1 \
    "$addr" "$tip_sig_send" \
    20 "${dst_words[1]}" "${dst_words[2]}" "${dst_words[3]}" \
    1 0 0 0 0 1 >/dev/null 2>&1; then
  die "tip with high Principal limb nonzero unexpectedly succeeded"
fi
got="$("$cast_path" call --rpc-url "$rpc" "$addr" 'get()(uint64)')"
require_uint_equal "$got" "1007" "wire-shape negatives must leave tips unchanged"
echo "evm-tipjar-anvil: neg Principal wire shape reverts (len=21 + high-limb)" >&2

# ---------------------------------------------------------------------------
# e. Negative: view get() with value → non-payable / callvalue!=0 revert
#    (eth_call with --value exercises the view guard without mining)
# ---------------------------------------------------------------------------
if "$cast_path" call --rpc-url "$rpc" --value 1 "$addr" 'get()(uint64)' >/dev/null 2>&1; then
  die "view get() with value unexpectedly succeeded"
fi
# init path is constructor-only; also pin nonpayable constructor accepts no value
# via a second create attempt with value (independent of state).
if "$cast_path" send --rpc-url "$rpc" --private-key "$pk" --value 1 --create \
    "0x${bytecode}${encoded#0x}" >/dev/null 2>&1; then
  die "nonpayable constructor unexpectedly accepted value"
fi
echo "evm-tipjar-anvil: neg non-payable view/constructor with value reverts" >&2

# ---------------------------------------------------------------------------
# f. dst = always-revert receiver contract → transfer CALL fails → tip reverts
# ---------------------------------------------------------------------------
# Initcode returns runtime PUSH1 0 PUSH1 0 REVERT (0x60006000fd).
revert_initcode=0x6005600c60003960056000f360006000fd
recv_json="$("$cast_path" send --json --rpc-url "$rpc" --private-key "$pk" \
  --create "$revert_initcode")"
recv_addr="$(/usr/bin/python3 -I -S -c 'import json,sys; print(json.load(sys.stdin).get("contractAddress",""))' <<<"$recv_json")"
[[ -n "$recv_addr" && "$recv_addr" != "null" ]] || die "deploy always-revert receiver failed"
# shellcheck disable=SC2207
recv_words=($(principal_words_from_addr "$recv_addr"))
if "$cast_path" send --rpc-url "$rpc" --private-key "$pk" --value 50 \
    "$addr" "$tip_sig_send" \
    "${recv_words[0]}" "${recv_words[1]}" "${recv_words[2]}" "${recv_words[3]}" \
    "${recv_words[4]}" "${recv_words[5]}" "${recv_words[6]}" "${recv_words[7]}" \
    "${recv_words[8]}" 50 >/dev/null 2>&1; then
  die "tip to always-revert receiver unexpectedly succeeded"
fi
got="$("$cast_path" call --rpc-url "$rpc" "$addr" 'get()(uint64)')"
require_uint_equal "$got" "1007" "failed transfer must leave tips unchanged"
contract_bal_final="$(to_dec "$("$cast_path" balance --rpc-url "$rpc" "$addr")")"
require_equal "$contract_bal_final" "0" "failed tip must not leave value in TipJar"
echo "evm-tipjar-anvil: neg transfer-to-reverting-receiver propagates (state held)" >&2

echo "evm-tipjar-anvil: ok deploy+tip+balances+callvalue/wire/nonpayable/transfer-fail on $addr" >&2
echo "evm-tipjar-anvil: engineering only; not formal Reference↔Anvil; no OZ/family credit"
