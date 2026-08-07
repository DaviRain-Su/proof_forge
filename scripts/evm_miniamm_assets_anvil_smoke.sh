#!/usr/bin/env bash
# ADR-0030 E4 M5: MiniAmmAssets dual ERC-20 Anvil engineering gate.
# Same product source as Solana Mollusk (`Examples/MiniAmmAssets.lean`).
# Real local_runtime evidence only (not formal C-3 / Reference↔Anvil closure).
#
# Scenarios (honest dual-mint asset path):
#   1. product build MiniAmmAssets for evm → .bin + abi (pf.assets.token.transfer)
#   2. locked solc ERC20Mock ×2 + deploy MiniAmmAssets
#   3. pre-fund AMM with mock0/mock1 (ADR-0033 honesty: no auto-pull on add)
#   4. addLiquidity → LP map + reserves
#   5. swap0to1 → ERC-20 transfer mint1→dst; reserves + off-program balances
#   6. slippage minOut fail → full state + token balance hold
#   7. removeLiquidity → dual ERC-20 transfer mint0+mint1→dst
#
# Skip-clean (exit 0) when anvil/cast/solc/CLI unavailable.
# Hard fail when tools present but build/assert fails. NEVER fabricate results.
#
# Optional PF_EVM_PROFILE (default / cancun) matches MiniAmm companion.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "$(uname -s)" in
  Darwin) default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64" ;;
  Linux) default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/linux-$(uname -m)" ;;
  *)
    echo "evm-miniamm-assets-anvil: explicit skip: unsupported host (optional; not pass)" >&2
    exit 0
    ;;
esac

foundry_bin="${FOUNDRY_BIN:-${PROOF_FORGE_TOOL_ROOT:-$default_tool_root}}"
anvil_path="$foundry_bin/anvil"
cast_path="$foundry_bin/cast"
solc_path="$foundry_bin/solc"
if [[ ! -x "${anvil_path:-}" ]] && command -v anvil >/dev/null 2>&1; then
  anvil_path="$(command -v anvil)"
fi
if [[ ! -x "${cast_path:-}" ]] && command -v cast >/dev/null 2>&1; then
  cast_path="$(command -v cast)"
fi
if [[ ! -x "${solc_path:-}" ]] && command -v solc >/dev/null 2>&1; then
  solc_path="$(command -v solc)"
fi
if [[ ! -x "${anvil_path:-}" || ! -x "${cast_path:-}" || ! -x "${solc_path:-}" ]]; then
  echo "evm-miniamm-assets-anvil: explicit skip: anvil/cast/solc unavailable (optional; not pass)" >&2
  exit 0
fi

die() {
  echo "evm-miniamm-assets-anvil: FAIL: $*" >&2
  exit 1
}

evm_profile="${PF_EVM_PROFILE:-}"
build_profile_args=()
artifact_suffix=""
anvil_extra_args=()
expected_profile_wire="evm-yul-solc-0.8.34-v1"
case "$evm_profile" in
  "")
    :
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
    echo "evm-miniamm-assets-anvil: profile=$evm_profile → anvil --hardfork cancun" >&2
    ;;
  *)
    echo "evm-miniamm-assets-anvil: explicit skip: unsupported PF_EVM_PROFILE='$evm_profile' (optional; not pass)" >&2
    exit 0
    ;;
esac

amm_out_rel="build/v2/miniamm-assets-evm${artifact_suffix}"
amm_out="$root/$amm_out_rel"
amm_bin="${MINIAMM_ASSETS_BIN:-$amm_out/MiniAmmAssets.bin}"
amm_abi="$amm_out/MiniAmmAssets.abi.json"
amm_yul="$amm_out/MiniAmmAssets.yul"

amm_tree_matches_profile() {
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

if ! amm_tree_matches_profile "$amm_bin"; then
  echo "evm-miniamm-assets-anvil: building MiniAmmAssets EVM → $amm_out_rel (profile=$expected_profile_wire)..." >&2
  amm_cli=""
  if [[ -n "${PROOF_FORGE_CLI:-}" && -x "${PROOF_FORGE_CLI}" ]]; then
    amm_cli="$PROOF_FORGE_CLI"
  elif [[ -x "$root/.lake/build/bin/proof-forge-next" ]]; then
    amm_cli="$root/.lake/build/bin/proof-forge-next"
  elif command -v proof-forge-next >/dev/null 2>&1; then
    amm_cli="$(command -v proof-forge-next)"
  fi
  if [[ -n "$amm_cli" ]] && command -v lake >/dev/null 2>&1; then
    rm -rf "$amm_out"
    build_log="$(mktemp "${TMPDIR:-/tmp}/pf-miniamm-assets-build.XXXXXX.log")"
    lake_root="${PF_LAKE_ROOT:-$root}"
    set +e
    if [[ ${#build_profile_args[@]} -gt 0 ]]; then
      (cd "$lake_root" && lake env bash -c 'cd "$1"; shift; exec "$@"' _ "$root" \
        "$amm_cli" build Examples/MiniAmmAssets.lean --module Examples.MiniAmmAssets --target evm \
        "${build_profile_args[@]}" -o "$amm_out_rel") >"$build_log" 2>&1
      build_rc=$?
    else
      (cd "$lake_root" && lake env bash -c 'cd "$1"; shift; exec "$@"' _ "$root" \
        "$amm_cli" build Examples/MiniAmmAssets.lean --module Examples.MiniAmmAssets --target evm \
        -o "$amm_out_rel") >"$build_log" 2>&1
      build_rc=$?
    fi
    set -e
    if [[ "$build_rc" -ne 0 ]]; then
      echo "evm-miniamm-assets-anvil: MiniAmmAssets EVM build failed (hard when tools present)" >&2
      tail -40 "$build_log" >&2 || true
      rm -f "$build_log"
      exit 1
    fi
    rm -f "$build_log"
  else
    echo "evm-miniamm-assets-anvil: explicit skip: product CLI or lake unavailable (optional; not pass)" >&2
    exit 0
  fi
  amm_bin="$amm_out/MiniAmmAssets.bin"
  amm_abi="$amm_out/MiniAmmAssets.abi.json"
  amm_yul="$amm_out/MiniAmmAssets.yul"
  [[ -f "$amm_bin" ]] || die "MiniAmmAssets.bin missing after build"
  if ! amm_tree_matches_profile "$amm_bin"; then
    die "MiniAmmAssets tree failed post-build profile validation"
  fi
fi

[[ -f "$amm_abi" ]] || die "missing MiniAmmAssets.abi.json"
[[ -f "$amm_yul" ]] || die "missing MiniAmmAssets.yul"
for name in addLiquidity swap0to1 swap1to0 removeLiquidity balanceOf getReserve0 getReserve1 getTotalSupply; do
  if ! grep -q "\"name\":\"$name\"" "$amm_abi" && ! grep -q "\"name\": \"$name\"" "$amm_abi"; then
    die "MiniAmmAssets.abi.json missing $name"
  fi
done
grep -q '0xa9059cbb' "$amm_yul" || die "Yul must emit ERC-20 transfer selector"
grep -q 'tokenAddr' "$amm_yul" || die "Yul must bind dynamic token callee"
grep -q '0, 68, 0, 32)' "$amm_yul" || die "Yul must use 68-byte transfer calldata"

bin_size="$(wc -c < "$amm_bin" | tr -d ' ')"
echo "evm-miniamm-assets-anvil: dual ERC-20 smoke (profile=$expected_profile_wire; bin=${bin_size}B hex); not formal" >&2
export FOUNDRY_BIN="$(cd "$(dirname "$anvil_path")" && pwd)"

# --- ERC20Mock (locked solc) ------------------------------------------------
mock_out="$root/build/v2/erc20mock-miniamm-assets${artifact_suffix}"
rm -rf "$mock_out"
mkdir -p "$mock_out"
"$solc_path" --bin --abi --optimize \
  --input-file "$root/runtime-tests/evm/ERC20Mock.sol" \
  --output-dir "$mock_out" --overwrite \
  || die "locked solc failed on ERC20Mock.sol"
[[ -s "$mock_out/ERC20Mock.bin" ]] || die "ERC20Mock.bin missing"

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

require_equal() {
  local actual="$1" expected="$2" message="$3"
  [[ "$actual" == "$expected" ]] || die "$message (expected '$expected', got '$actual')"
}

require_uint_equal() {
  local actual="$1" expected="$2" message="$3" canonical
  canonical="$(to_dec "$actual")"
  [[ -n "$canonical" ]] || die "$message (empty uint output, raw='$actual')"
  require_equal "$canonical" "$expected" "$message"
}

# Pack 20-byte address → Principal 9 leaves (hex words; cast-safe).
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
print(20, hex(w0), hex(w1), hex(w2), 0, 0, 0, 0, 0)
"
}

json_field() {
  local json="$1" field="$2"
  /usr/bin/python3 -I -S -c 'import json,sys
try:
  d=json.load(sys.stdin)
  v=d.get(sys.argv[1],"")
  print("" if v is None else v)
except Exception:
  print("")' "$field" <<<"$json"
}

send_status() {
  local json
  set +e
  json="$("$cast_path" send --json "$@" 2>/dev/null)"
  local rc=$?
  set -e
  if [[ "$rc" -ne 0 || -z "$json" ]]; then
    echo ""
    return 0
  fi
  json_field "$json" status
}

require_send_ok() {
  local message="$1"; shift
  local status
  status="$(send_status "$@")"
  [[ "$status" == "0x1" || "$status" == "1" ]] || die "$message (receipt status='$status')"
}

require_send_revert() {
  local message="$1"; shift
  local status
  status="$(send_status "$@")"
  if [[ "$status" == "0x1" || "$status" == "1" ]]; then
    die "$message (tx succeeded with status=$status)"
  fi
}

port=$((19645 + RANDOM % 1000))
chain_id="${PF_EVM_CHAIN_ID:-31341}"
pk=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
eoa=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
dst_eoa=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
eng_gas_limit="${PF_MINIAMM_ASSETS_ANVIL_GAS_LIMIT:-500000000}"

anvil_log="$(mktemp "${TMPDIR:-/tmp}/pf-miniamm-assets-anvil.XXXXXX.log")"
create_err="$(mktemp "${TMPDIR:-/tmp}/pf-miniamm-assets-create.XXXXXX.err")"
cleanup() {
  kill "${anvil_pid:-}" 2>/dev/null || true
  wait "${anvil_pid:-}" 2>/dev/null || true
  rm -f "$anvil_log" "$create_err"
}
trap cleanup EXIT

start_anvil() {
  kill "${anvil_pid:-}" 2>/dev/null || true
  wait "${anvil_pid:-}" 2>/dev/null || true
  : >"$anvil_log"
  if ((${#anvil_extra_args[@]})); then
    "$anvil_path" --host 127.0.0.1 --port "$port" --chain-id "$chain_id" \
      "${anvil_extra_args[@]}" "$@" --silent >"$anvil_log" 2>&1 &
  else
    "$anvil_path" --host 127.0.0.1 --port "$port" --chain-id "$chain_id" \
      "$@" --silent >"$anvil_log" 2>&1 &
  fi
  anvil_pid=$!
  local ready=0
  for _ in $(seq 1 50); do
    if "$cast_path" chain-id --rpc-url "$rpc" >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 0.1
  done
  [[ "$ready" == 1 ]]
}

rpc="http://127.0.0.1:$port"
if ! start_anvil; then
  echo "evm-miniamm-assets-anvil: explicit skip: anvil failed to start (optional; not pass; see $anvil_log)" >&2
  exit 0
fi

deploy_bin() {
  # deploy_bin <binfile> [gas_limit]
  local binfile="$1"
  local gas_limit="${2:-}"
  local bytecode encoded json
  bytecode="$(tr -d '\n\r ' < "$binfile")"
  [[ -n "$bytecode" ]] || die "empty bytecode $binfile"
  set +e
  if [[ -n "$gas_limit" ]]; then
    json="$("$cast_path" send --json --rpc-url "$rpc" --private-key "$pk" \
      --gas-limit "$gas_limit" --create "0x${bytecode}" 2>"$create_err")"
  else
    json="$("$cast_path" send --json --rpc-url "$rpc" --private-key "$pk" \
      --create "0x${bytecode}" 2>"$create_err")"
  fi
  local rc=$?
  set -e
  if [[ "$rc" -ne 0 || -z "$json" ]]; then
    echo ""
    return 0
  fi
  json_field "$json" contractAddress
}

# --- 1. Deploy dual mocks + AMM ---------------------------------------------
mock0="$(deploy_bin "$mock_out/ERC20Mock.bin")"
[[ -n "$mock0" && "$mock0" != "null" ]] || die "deploy mock0 failed"
mock1="$(deploy_bin "$mock_out/ERC20Mock.bin")"
[[ -n "$mock1" && "$mock1" != "null" ]] || die "deploy mock1 failed"
[[ "$mock0" != "$mock1" ]] || die "mock0/mock1 must be distinct addresses"

amm_addr="$(deploy_bin "$amm_bin")"
deploy_mode="strict-eip-limits"
if [[ -z "$amm_addr" || "$amm_addr" == "null" ]]; then
  if grep -qiE 'initcode|max code|code size|oversized|max initcode|out of gas' "$create_err" 2>/dev/null \
      || grep -qiE 'initcode|max code|code size|oversized|max initcode' "$anvil_log" 2>/dev/null; then
    echo "evm-miniamm-assets-anvil: note: strict Anvil rejected create (bin=${bin_size}B hex)" >&2
    echo "evm-miniamm-assets-anvil: restarting with --disable-code-size-limit --gas-limit $eng_gas_limit (engineering only; NOT mainnet claim)" >&2
    if ! start_anvil --disable-code-size-limit --gas-limit "$eng_gas_limit"; then
      echo "evm-miniamm-assets-anvil: explicit skip: engineering Anvil failed to start" >&2
      exit 0
    fi
    # Redeploy mocks on fresh chain.
    mock0="$(deploy_bin "$mock_out/ERC20Mock.bin" "$eng_gas_limit")"
    mock1="$(deploy_bin "$mock_out/ERC20Mock.bin" "$eng_gas_limit")"
    [[ -n "$mock0" && "$mock0" != "null" && -n "$mock1" && "$mock1" != "null" ]] \
      || die "redeploy mocks under engineering Anvil failed"
    amm_addr="$(deploy_bin "$amm_bin" "$eng_gas_limit")"
    deploy_mode="engineering-code-size-override"
  fi
fi
[[ -n "$amm_addr" && "$amm_addr" != "null" ]] || die "deploy MiniAmmAssets failed (see $create_err)"
echo "evm-miniamm-assets-anvil: mock0=$mock0 mock1=$mock1 amm=$amm_addr mode=$deploy_mode" >&2

require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$amm_addr" 'getReserve0()(uint64)')" "0" "fresh r0"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$amm_addr" 'getReserve1()(uint64)')" "0" "fresh r1"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$amm_addr" 'getTotalSupply()(uint64)')" "0" "fresh supply"

# shellcheck disable=SC2207
eoa_words=($(principal_words_from_addr "$eoa"))
# shellcheck disable=SC2207
dst_words=($(principal_words_from_addr "$dst_eoa"))
# shellcheck disable=SC2207
mint0_words=($(principal_words_from_addr "$mock0"))
# shellcheck disable=SC2207
mint1_words=($(principal_words_from_addr "$mock1"))
[[ ${#eoa_words[@]} -eq 9 && ${#dst_words[@]} -eq 9 ]] || die "principal leaf count"
[[ ${#mint0_words[@]} -eq 9 && ${#mint1_words[@]} -eq 9 ]] || die "mint principal leaf count"

bal_sig='balanceOf(uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64)(uint64)'
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$amm_addr" "$bal_sig" "${eoa_words[@]}")" "0" \
  "fresh LP balanceOf(caller)"

# --- 2. Pre-fund vault + addLiquidity ---------------------------------------
amount0=1000
amount1=2000
"$cast_path" send --rpc-url "$rpc" --private-key "$pk" "$mock0" \
  'mint(address,uint256)' "$amm_addr" "$amount0" >/dev/null \
  || die "mint mock0 to AMM failed"
"$cast_path" send --rpc-url "$rpc" --private-key "$pk" "$mock1" \
  'mint(address,uint256)' "$amm_addr" "$amount1" >/dev/null \
  || die "mint mock1 to AMM failed"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$mock0" 'balanceOf(address)(uint256)' "$amm_addr")" \
  "$amount0" "pre-fund mock0 on AMM"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$mock1" 'balanceOf(address)(uint256)' "$amm_addr")" \
  "$amount1" "pre-fund mock1 on AMM"

require_send_ok "addLiquidity($amount0,$amount1) failed" \
  --rpc-url "$rpc" --private-key "$pk" \
  "$amm_addr" 'addLiquidity(uint64,uint64)' "$amount0" "$amount1"

require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$amm_addr" 'getReserve0()(uint64)')" "$amount0" "r0 after add"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$amm_addr" 'getReserve1()(uint64)')" "$amount1" "r1 after add"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$amm_addr" 'getTotalSupply()(uint64)')" "$amount0" "supply after first mint"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" --from "$eoa" "$amm_addr" "$bal_sig" "${eoa_words[@]}")" \
  "$amount0" "LP balanceOf(caller) after add"
# addLiquidity is vault-internal: ERC-20 balances unchanged by the call.
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$mock0" 'balanceOf(address)(uint256)' "$amm_addr")" \
  "$amount0" "add must not move mock0 (pre-fund honesty)"
echo "evm-miniamm-assets-anvil: addLiquidity ok LP=$amount0 r0=$amount0 r1=$amount1" >&2

# --- 3. swap0to1 pays mint1 to dst ------------------------------------------
# amountOut = 100 * 2000 / (1000+100) = 181
amount_in=100
expected_out=181
expected_r0=1100
expected_r1=1819
min_out_ok=181
min_out_fail=182

# Declared amountIn honesty: pre-fund extra mint0 into AMM (no pull).
"$cast_path" send --rpc-url "$rpc" --private-key "$pk" "$mock0" \
  'mint(address,uint256)' "$amm_addr" "$amount_in" >/dev/null \
  || die "pre-fund amountIn mint0 failed"

# swap0to1(mint1,to,amountIn,minOut) — 20×uint64
swap0_sig='swap0to1(uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64)(uint64)'

sim_out="$("$cast_path" call --rpc-url "$rpc" --from "$eoa" "$amm_addr" \
  "$swap0_sig" "${mint1_words[@]}" "${dst_words[@]}" "$amount_in" "$min_out_ok")"
require_uint_equal "$sim_out" "$expected_out" "swap0to1 eth_call amountOut"

dst_tok_before="$("$cast_path" call --rpc-url "$rpc" "$mock1" 'balanceOf(address)(uint256)' "$dst_eoa")"
require_uint_equal "$dst_tok_before" "0" "dst mint1 before swap"

require_send_ok "swap0to1 failed" \
  --rpc-url "$rpc" --private-key "$pk" \
  "$amm_addr" "$swap0_sig" "${mint1_words[@]}" "${dst_words[@]}" "$amount_in" "$min_out_ok"

require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$amm_addr" 'getReserve0()(uint64)')" "$expected_r0" "r0 after swap"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$amm_addr" 'getReserve1()(uint64)')" "$expected_r1" "r1 after swap"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$mock1" 'balanceOf(address)(uint256)' "$dst_eoa")" \
  "$expected_out" "dst mint1 after swap (ERC-20 transfer)"
# AMM mint1: pre-fund 2000 − out 181 = 1819
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$mock1" 'balanceOf(address)(uint256)' "$amm_addr")" \
  "$expected_r1" "AMM mint1 after swap"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$amm_addr" 'getTotalSupply()(uint64)')" "$amount0" \
  "swap must not change totalSupply"
echo "evm-miniamm-assets-anvil: swap0to1 ok out=$expected_out dst_mint1=$expected_out" >&2

# --- 4. Slippage reverts; token + reserves hold -----------------------------
require_send_revert "swap0to1 minOut fail must revert" \
  --rpc-url "$rpc" --private-key "$pk" \
  "$amm_addr" "$swap0_sig" "${mint1_words[@]}" "${dst_words[@]}" "$amount_in" "$min_out_fail"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$amm_addr" 'getReserve0()(uint64)')" "$expected_r0" \
  "slippage hold r0"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$amm_addr" 'getReserve1()(uint64)')" "$expected_r1" \
  "slippage hold r1"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$mock1" 'balanceOf(address)(uint256)' "$dst_eoa")" \
  "$expected_out" "slippage hold dst mint1"
echo "evm-miniamm-assets-anvil: slippage revert + full hold ok" >&2

# --- 5. removeLiquidity dual ERC-20 transfer --------------------------------
# LP burn 250 of 1000; out0 = 250*1100/1000 = 275; out1 = 250*1819/1000 = 454
lp=250
out0=275
out1=454
# removeLiquidity(mint0,mint1,to,lp) — 28×uint64
remove_sig='removeLiquidity(uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64)(uint64)'

dst0_before="$("$cast_path" call --rpc-url "$rpc" "$mock0" 'balanceOf(address)(uint256)' "$dst_eoa")"
require_uint_equal "$dst0_before" "0" "dst mint0 before remove"

require_send_ok "removeLiquidity($lp) failed" \
  --rpc-url "$rpc" --private-key "$pk" \
  "$amm_addr" "$remove_sig" \
  "${mint0_words[@]}" "${mint1_words[@]}" "${dst_words[@]}" "$lp"

require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$amm_addr" 'getTotalSupply()(uint64)')" \
  "$((amount0 - lp))" "supply after remove"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$amm_addr" 'getReserve0()(uint64)')" \
  "$((expected_r0 - out0))" "r0 after remove"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$amm_addr" 'getReserve1()(uint64)')" \
  "$((expected_r1 - out1))" "r1 after remove"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" --from "$eoa" "$amm_addr" "$bal_sig" "${eoa_words[@]}")" \
  "$((amount0 - lp))" "LP after remove"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$mock0" 'balanceOf(address)(uint256)' "$dst_eoa")" \
  "$out0" "dst mint0 after remove (dual transfer)"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$mock1" 'balanceOf(address)(uint256)' "$dst_eoa")" \
  "$((expected_out + out1))" "dst mint1 after remove (prior swap + dual)"
echo "evm-miniamm-assets-anvil: removeLiquidity dual transfer ok out0=$out0 out1=$out1" >&2

echo "evm-miniamm-assets-anvil: ok M5 dual ERC-20 on $amm_addr (mode=$deploy_mode)" >&2
echo "evm-miniamm-assets-anvil: same source as Solana Mollusk miniamm_assets; engineering only; not formal C-3"
