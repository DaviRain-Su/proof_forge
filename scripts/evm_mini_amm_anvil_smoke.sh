#!/usr/bin/env bash
# ADR-0030 E4: MiniAmm vault-internal constant-product Anvil engineering gate.
# Real local_runtime evidence only (not formal C-3 / Reference↔Anvil closure).
#
# Scenarios (minimal honest):
#   1. product build MiniAmm for evm → .bin + abi
#   2. start anvil (skip-clean if tools missing)
#   3. deploy MiniAmm (init() zero-arg create)
#   4. addLiquidity from default EOA; check getReserve0/1, balanceOf(caller), totalSupply
#   5. swap0to1; check reserves moved and amountOut > 0
#   6. negative: amountIn=0 reverts with state hold
#
# Skip-clean (exit 0) when:
#   - host platform unsupported
#   - anvil/cast unavailable
#   - product CLI or lake unavailable
#   - anvil failed to start
#
# M2 compact Principal Map keeps MiniAmm creation under EIP-3860 (~7KiB).
# Prefer strict Anvil deploy. If strict still rejects (unexpected size regression
# or host gas quirks), restart with engineering-only
#   --disable-code-size-limit + raised --gas-limit
# and continue the runtime matrix — that path is **not** a mainnet claim; logs
# state the override. If even override cannot deploy, hard-fail when tools are
# present rather than fake success.
#
# Hard fail (exit 1) when tools+CLI are present but product build fails or any
# Anvil matrix assertion fails. NEVER fabricate Anvil results.
#
# Optional PF_EVM_PROFILE inheritance (same as TipJar/Caller companions):
#   empty / evm-yul-solc-0.8.34-v1 → build/v2/mini-amm-evm
#   evm-yul-solc-0.8.34-cancun-v1 → build/v2/mini-amm-evm-cancun + anvil --hardfork cancun
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "$(uname -s)" in
  Darwin) default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64" ;;
  Linux) default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/linux-$(uname -m)" ;;
  *)
    echo "evm-mini-amm-anvil: explicit skip: unsupported host (optional leg; not pass)" >&2
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
  echo "evm-mini-amm-anvil: explicit skip: anvil/cast unavailable (optional leg; not pass)" >&2
  echo "evm-mini-amm-anvil: engineering only; not formal Reference↔Anvil" >&2
  exit 0
fi

die() {
  echo "evm-mini-amm-anvil: FAIL: $*" >&2
  exit 1
}

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
    echo "evm-mini-amm-anvil: profile=$evm_profile → anvil --hardfork cancun" >&2
    ;;
  *)
    echo "evm-mini-amm-anvil: explicit skip: unsupported PF_EVM_PROFILE='$evm_profile' (optional; not pass)" >&2
    exit 0
    ;;
esac

amm_out_rel="build/v2/mini-amm-evm${artifact_suffix}"
amm_out="$root/$amm_out_rel"
amm_bin="${MINI_AMM_BIN:-$amm_out/MiniAmm.bin}"
amm_abi="$amm_out/MiniAmm.abi.json"

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
  echo "evm-mini-amm-anvil: building MiniAmm EVM artifact → $amm_out_rel (profile=$expected_profile_wire)..." >&2
  amm_cli=""
  if [[ -n "${PROOF_FORGE_CLI:-}" && -x "${PROOF_FORGE_CLI}" ]]; then
    amm_cli="$PROOF_FORGE_CLI"
  elif [[ -x "$root/.lake/build/bin/proof-forge-next" ]]; then
    amm_cli="$root/.lake/build/bin/proof-forge-next"
  elif command -v proof-forge-next >/dev/null 2>&1; then
    amm_cli="$(command -v proof-forge-next)"
  fi
  if [[ -n "$amm_cli" ]] && command -v lake >/dev/null 2>&1; then
    # Product CLI refuses non-empty existing -o dirs (PF-OUTPUT-COLLISION).
    rm -rf "$amm_out"
    build_log="$(mktemp "${TMPDIR:-/tmp}/pf-mini-amm-build.XXXXXX.log")"
    lake_root="${PF_LAKE_ROOT:-$root}"
    set +e
    if [[ ${#build_profile_args[@]} -gt 0 ]]; then
      (cd "$lake_root" && lake env bash -c 'cd "$1"; shift; exec "$@"' _ "$root" \
        "$amm_cli" build Examples/MiniAmm.lean --module Examples.MiniAmm --target evm \
        "${build_profile_args[@]}" -o "$amm_out_rel") >"$build_log" 2>&1
      build_rc=$?
    else
      (cd "$lake_root" && lake env bash -c 'cd "$1"; shift; exec "$@"' _ "$root" \
        "$amm_cli" build Examples/MiniAmm.lean --module Examples.MiniAmm --target evm \
        -o "$amm_out_rel") >"$build_log" 2>&1
      build_rc=$?
    fi
    set -e
    if [[ "$build_rc" -ne 0 ]]; then
      echo "evm-mini-amm-anvil: MiniAmm EVM build failed (hard when tools present; profile=$expected_profile_wire)" >&2
      tail -40 "$build_log" >&2 || true
      rm -f "$build_log"
      exit 1
    fi
    rm -f "$build_log"
  else
    echo "evm-mini-amm-anvil: explicit skip: product CLI or lake unavailable (optional leg; not pass)" >&2
    exit 0
  fi
  amm_bin="$amm_out/MiniAmm.bin"
  amm_abi="$amm_out/MiniAmm.abi.json"
  [[ -f "$amm_bin" ]] || die "MiniAmm.bin missing after successful build"
  if ! amm_tree_matches_profile "$amm_bin"; then
    die "MiniAmm tree failed post-build profile validation"
  fi
fi

[[ -f "$amm_abi" ]] || die "missing MiniAmm.abi.json"
# Surface pin: M0 entries/views must appear in product ABI.
for name in addLiquidity swap0to1 swap1to0 removeLiquidity balanceOf getReserve0 getReserve1 getTotalSupply; do
  if ! grep -q "\"name\":\"$name\"" "$amm_abi" && ! grep -q "\"name\": \"$name\"" "$amm_abi"; then
    die "MiniAmm.abi.json missing $name"
  fi
done

bin_size="$(wc -c < "$amm_bin" | tr -d ' ')"
echo "evm-mini-amm-anvil: engineering MiniAmm vault smoke (profile=$expected_profile_wire; bin=${bin_size}B); not formal" >&2
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

require_uint_gt() {
  local actual="$1" bound="$2" message="$3" canonical
  canonical="$(to_dec "$actual")"
  [[ -n "$canonical" ]] || die "$message (empty uint output, raw='$actual')"
  /usr/bin/python3 -I -S -c "import sys; sys.exit(0 if int('$canonical') > int('$bound') else 1)" \
    || die "$message (got $canonical, need > $bound)"
}

# Pack a 20-byte network-order address into Principal ABI leaves as hex words.
# cast's decimal parser rejects UInt64 limbs above signed-i64 max; hex is exact.
# Layout: len=20, w0/w1 = LE first/next 8 body bytes, w2 = LE last 4, w3..w7=0.
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
print(20, hex(w0), hex(w1), hex(w2), 0, 0, 0, 0, 0)
"
}

json_field() {
  # Extract a top-level JSON string/number field; empty on parse failure.
  local json="$1" field="$2"
  /usr/bin/python3 -I -S -c 'import json,sys
try:
  d=json.load(sys.stdin)
  v=d.get(sys.argv[1],"")
  print("" if v is None else v)
except Exception:
  print("")' "$field" <<<"$json"
}

# cast send often exits 0 even when receipt status is 0x0 — check status explicitly.
send_status() {
  # Usage: send_status <cast-send-args...>
  # Prints receipt status (0x0/0x1) or empty; stderr suppressed (revert noise).
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
  # Revert may surface as status=0x0 (mined failure) or empty (RPC error / cast non-zero).
  if [[ "$status" == "0x1" || "$status" == "1" ]]; then
    die "$message (tx succeeded with status=$status)"
  fi
}

port=$((18545 + RANDOM % 1000))
chain_id="${PF_EVM_CHAIN_ID:-31340}"
# Anvil default key / account 0 (deployer + LP caller for positive path).
pk=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
eoa=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
# Engineering gas budget for oversized Principal-Map creation bytecode.
eng_gas_limit="${PF_MINI_AMM_ANVIL_GAS_LIMIT:-500000000}"

anvil_log="$(mktemp "${TMPDIR:-/tmp}/pf-mini-amm-anvil.XXXXXX.log")"
create_err="$(mktemp "${TMPDIR:-/tmp}/pf-mini-amm-create.XXXXXX.err")"
cleanup_amm() {
  kill "${anvil_pid:-}" 2>/dev/null || true
  wait "${anvil_pid:-}" 2>/dev/null || true
  rm -f "$anvil_log" "$create_err"
}
trap cleanup_amm EXIT

start_anvil() {
  # Args forwarded after fixed host/port/chain-id.
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
  echo "evm-mini-amm-anvil: explicit skip: anvil failed to start (optional; not pass; see $anvil_log)" >&2
  exit 0
fi

# ---------------------------------------------------------------------------
# 1. Deploy MiniAmm (zero-arg init — no constructor ABI encoding)
# ---------------------------------------------------------------------------
bytecode="$(tr -d '\n\r ' < "$amm_bin")"
[[ -n "$bytecode" ]] || die "MiniAmm.bin empty"

try_deploy() {
  # Optional first arg: cast --gas-limit value (empty = cast default).
  local json rc addr_try
  set +e
  if [[ -n "${1:-}" ]]; then
    json="$("$cast_path" send --json --rpc-url "$rpc" --private-key "$pk" \
      --gas-limit "$1" --create "0x${bytecode}" 2>"$create_err")"
  else
    json="$("$cast_path" send --json --rpc-url "$rpc" --private-key "$pk" \
      --create "0x${bytecode}" 2>"$create_err")"
  fi
  rc=$?
  set -e
  if [[ "$rc" -ne 0 || -z "$json" ]]; then
    echo ""
    return 0
  fi
  addr_try="$(json_field "$json" contractAddress)"
  echo "$addr_try"
}

addr="$(try_deploy)"
deploy_mode="strict-eip-limits"
if [[ -z "$addr" || "$addr" == "null" ]]; then
  if grep -qiE 'initcode|max code|code size|oversized|max initcode|out of gas' "$create_err" 2>/dev/null \
      || grep -qiE 'initcode|max code|code size|oversized|max initcode' "$anvil_log" 2>/dev/null; then
    echo "evm-mini-amm-anvil: note: strict Anvil rejected create (EIP-3860/code-size/gas; bin=${bin_size}B hex)" >&2
    echo "evm-mini-amm-anvil: restarting Anvil with --disable-code-size-limit --gas-limit $eng_gas_limit (engineering only; NOT mainnet/EIP-3860 deploy claim)" >&2
    if ! start_anvil --disable-code-size-limit --gas-limit "$eng_gas_limit"; then
      echo "evm-mini-amm-anvil: explicit skip: engineering Anvil failed to start (optional; not pass)" >&2
      exit 0
    fi
    addr="$(try_deploy "$eng_gas_limit")"
    deploy_mode="engineering-code-size-override"
  fi
fi
if [[ -z "$addr" || "$addr" == "null" ]]; then
  echo "evm-mini-amm-anvil: deploy failed (hard; bin=${bin_size}B; mode attempted; see $create_err and $anvil_log)" >&2
  tail -20 "$create_err" >&2 || true
  exit 1
fi
echo "evm-mini-amm-anvil: deployed MiniAmm at $addr (bin=${bin_size}B hex; mode=$deploy_mode; eoa=$eoa)" >&2

# Fresh vault: all zeros.
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$addr" 'getReserve0()(uint64)')" "0" \
  "fresh getReserve0 must be 0"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$addr" 'getReserve1()(uint64)')" "0" \
  "fresh getReserve1 must be 0"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$addr" 'getTotalSupply()(uint64)')" "0" \
  "fresh getTotalSupply must be 0"

# shellcheck disable=SC2207
eoa_words=($(principal_words_from_addr "$eoa"))
[[ ${#eoa_words[@]} -eq 9 ]] || die "eoa principal leaves wrong count ${#eoa_words[@]}"

bal_sig='balanceOf(uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64)(uint64)'
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$addr" "$bal_sig" "${eoa_words[@]}")" "0" \
  "fresh balanceOf(caller) must be 0"

# ---------------------------------------------------------------------------
# 2. addLiquidity(1000, 2000) from default EOA — first deposit mints LP=amount0
# ---------------------------------------------------------------------------
amount0=1000
amount1=2000
# First deposit: LP = amount0 (no sqrt); reserves += amounts; totalSupply += LP.
require_send_ok "addLiquidity($amount0,$amount1) failed" \
  --rpc-url "$rpc" --private-key "$pk" \
  "$addr" 'addLiquidity(uint64,uint64)' "$amount0" "$amount1"

require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$addr" 'getReserve0()(uint64)')" "$amount0" \
  "after addLiquidity getReserve0"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$addr" 'getReserve1()(uint64)')" "$amount1" \
  "after addLiquidity getReserve1"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$addr" 'getTotalSupply()(uint64)')" "$amount0" \
  "after first addLiquidity totalSupply must equal amount0 (LP mint formula)"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" --from "$eoa" "$addr" "$bal_sig" "${eoa_words[@]}")" \
  "$amount0" "after addLiquidity balanceOf(caller) must equal minted LP"
echo "evm-mini-amm-anvil: addLiquidity ok r0=$amount0 r1=$amount1 supply=$amount0 bal(caller)=$amount0" >&2

# ---------------------------------------------------------------------------
# 3. swap0to1(100, minOut=181): amountOut = amountIn * r1 / (r0 + amountIn)
#    100 * 2000 / (1000 + 100) = 200000 / 1100 = 181 (UInt64 integer div)
# ---------------------------------------------------------------------------
amount_in=100
expected_out=181
expected_r0=1100
expected_r1=1819
min_out_ok=181
min_out_fail=182

# Simulate return via eth_call first (state unchanged on call).
sim_out="$("$cast_path" call --rpc-url "$rpc" --from "$eoa" "$addr" \
  'swap0to1(uint64,uint64)(uint64)' "$amount_in" "$min_out_ok")"
require_uint_equal "$sim_out" "$expected_out" "swap0to1 eth_call amountOut"
require_uint_gt "$sim_out" "0" "amountOut must be > 0"

require_send_ok "swap0to1($amount_in,$min_out_ok) failed" \
  --rpc-url "$rpc" --private-key "$pk" \
  "$addr" 'swap0to1(uint64,uint64)' "$amount_in" "$min_out_ok"

require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$addr" 'getReserve0()(uint64)')" "$expected_r0" \
  "after swap0to1 getReserve0"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$addr" 'getReserve1()(uint64)')" "$expected_r1" \
  "after swap0to1 getReserve1"
# LP supply and caller balance unchanged by vault-internal swap.
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$addr" 'getTotalSupply()(uint64)')" "$amount0" \
  "swap must not change totalSupply"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" --from "$eoa" "$addr" "$bal_sig" "${eoa_words[@]}")" \
  "$amount0" "swap must not change balanceOf(caller)"
echo "evm-mini-amm-anvil: swap0to1 ok amountOut=$expected_out r0=$expected_r0 r1=$expected_r1" >&2

# ---------------------------------------------------------------------------
# 4. True slippage fail: minOut=182 > out=181 reverts; state holds (post-swap3)
# ---------------------------------------------------------------------------
require_send_revert "swap0to1 minOut=182 unexpectedly succeeded" \
  --rpc-url "$rpc" --private-key "$pk" \
  "$addr" 'swap0to1(uint64,uint64)' "$amount_in" "$min_out_fail"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$addr" 'getReserve0()(uint64)')" "$expected_r0" \
  "slippage fail must leave reserve0 unchanged"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$addr" 'getReserve1()(uint64)')" "$expected_r1" \
  "slippage fail must leave reserve1 unchanged"
echo "evm-mini-amm-anvil: neg swap0to1 amountOutMin fail reverts (state held)" >&2

# ---------------------------------------------------------------------------
# 5. Negative: amountIn=0 reverts; reserves hold
# ---------------------------------------------------------------------------
require_send_revert "swap0to1(0,*) unexpectedly succeeded" \
  --rpc-url "$rpc" --private-key "$pk" \
  "$addr" 'swap0to1(uint64,uint64)' 0 0
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$addr" 'getReserve0()(uint64)')" "$expected_r0" \
  "swap0to1(0) must leave reserve0 unchanged"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$addr" 'getReserve1()(uint64)')" "$expected_r1" \
  "swap0to1(0) must leave reserve1 unchanged"
echo "evm-mini-amm-anvil: neg swap0to1(0) reverts (state held)" >&2

# Optional: amount0=0 on addLiquidity also reverts.
require_send_revert "addLiquidity(0,1) unexpectedly succeeded" \
  --rpc-url "$rpc" --private-key "$pk" \
  "$addr" 'addLiquidity(uint64,uint64)' 0 1
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$addr" 'getReserve0()(uint64)')" "$expected_r0" \
  "addLiquidity(0,1) must leave reserve0 unchanged"

# ---------------------------------------------------------------------------
# 6. reverse swap1to0(181, minOut=99) → 99; restores toward initial pool
# ---------------------------------------------------------------------------
rev_in=181
rev_out=99
rev_r0=1001
rev_r1=2000
require_send_ok "swap1to0($rev_in,99) failed" \
  --rpc-url "$rpc" --private-key "$pk" \
  "$addr" 'swap1to0(uint64,uint64)' "$rev_in" 99
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$addr" 'getReserve0()(uint64)')" "$rev_r0" \
  "after swap1to0 getReserve0"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$addr" 'getReserve1()(uint64)')" "$rev_r1" \
  "after swap1to0 getReserve1"
echo "evm-mini-amm-anvil: swap1to0 ok amountOut=$rev_out" >&2

# ---------------------------------------------------------------------------
# 7. removeLiquidity half of LP (500) — amount0 out + reserve shrink
# ---------------------------------------------------------------------------
# After first add only would be clean; after swaps supplies still 1000 LP.
require_send_ok "removeLiquidity(500) failed" \
  --rpc-url "$rpc" --private-key "$pk" \
  "$addr" 'removeLiquidity(uint64)' 500
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" "$addr" 'getTotalSupply()(uint64)')" "500" \
  "after remove 500 totalSupply"
require_uint_equal "$("$cast_path" call --rpc-url "$rpc" --from "$eoa" "$addr" "$bal_sig" "${eoa_words[@]}")" \
  "500" "after remove balanceOf(caller)"
echo "evm-mini-amm-anvil: removeLiquidity(500) ok" >&2

echo "evm-mini-amm-anvil: ok M0 vectors on $addr (mode=$deploy_mode)" >&2
echo "evm-mini-amm-anvil: engineering only; not formal Reference↔Anvil; not EIP-3860 mainnet deploy claim"
