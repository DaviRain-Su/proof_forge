#!/usr/bin/env bash
# ADR-0030 E2-3: EnvReadJar (pf.assets env-read balanceOfSelf) Anvil engineering gate.
# Real local_runtime evidence only (not formal C-3 / Reference↔Anvil closure).
#
# Scenarios:
#   1. deploy ERC20Mock + EnvReadJar(initial=0)
#   2. native balance: fund the contract with 1 ETH → nativeBalance() == 1e18
#   3. token balance: mint 2000 ERC20 to EnvReadJar → tokenBalance(mock) == 2000
#   4. tip 500 out via tipToken → tokenBalance(mock) == 1500 (drops by 500)
#   5. wire-shape negative: tokenBalance with malformed mint (len≠20) → revert
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
    echo "evm-envread-anvil: explicit skip: missing $tool (optional; not pass)" >&2
    exit 0
  fi
done

cli="$root/.lake/build/bin/proof-forge-next"
echo "evm-envread-anvil: building proof-forge-next (lake build proof_forge_next)" >&2
lake build proof_forge_next || die "lake build proof_forge_next failed"
if [[ ! -x "$cli" ]]; then
  echo "evm-envread-anvil: explicit skip: product CLI missing (optional; not pass)" >&2
  exit 0
fi

die() { echo "evm-envread-anvil: FAIL: $*" >&2; exit 1; }

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
mock_out="$root/build/v2/erc20mock-envread"
rm -rf "$mock_out"
mkdir -p "$mock_out"
"$solc_path" --bin --abi --optimize \
  --input-file "$root/runtime-tests/evm/ERC20Mock.sol" \
  --output-dir "$mock_out" --overwrite \
  || die "locked solc failed on ERC20Mock.sol"
[[ -s "$mock_out/ERC20Mock.bin" ]] || die "ERC20Mock.bin missing after solc"

envread_out="$root/build/v2/envreadjar-evm"
rm -rf "$envread_out"
lake env "$cli" build Examples/EnvReadJar.lean \
  --module Examples.EnvReadJar --target evm -o "$envread_out" \
  || die "product build of EnvReadJar (evm) failed"
[[ -s "$envread_out/EnvReadJar.bin" ]] || die "EnvReadJar.bin missing"

# --- anvil -----------------------------------------------------------------
port=$((19545 + RANDOM % 1000))
chain_id="${PF_EVM_CHAIN_ID:-31339}"
pk=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
dst_eoa=0x70997970C51812dc3A010C7d01b50e0d17dc79C8

anvil_log="$(mktemp "${TMPDIR:-/tmp}/pf-envread-anvil.XXXXXX.log")"
cleanup() {
  kill "${anvil_pid:-}" 2>/dev/null || true
  wait "${anvil_pid:-}" 2>/dev/null || true
  rm -f "$anvil_log"
}
trap cleanup EXIT

"$anvil_path" --host 127.0.0.1 --port "$port" --chain-id "$chain_id" \
  --silent >"$anvil_log" 2>&1 &
anvil_pid=$!
rpc="http://127.0.0.1:$port"
ready=0
for _ in $(seq 1 50); do
  if "$cast_path" chain-id --rpc-url "$rpc" >/dev/null 2>&1; then ready=1; break; fi
  sleep 0.1
done
if [[ "$ready" != 1 ]]; then
  echo "evm-envread-anvil: explicit skip: anvil failed to start (optional; not pass; see $anvil_log)" >&2
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
mock_addr="$(deploy "$mock_out/ERC20Mock.bin" "")"
[[ -n "$mock_addr" && "$mock_addr" != "null" ]] || die "deploy ERC20Mock failed"
jar_addr="$(deploy "$envread_out/EnvReadJar.bin" 'constructor(uint64)' 0)"
[[ -n "$jar_addr" && "$jar_addr" != "null" ]] || die "deploy EnvReadJar failed"
echo "evm-envread-anvil: mock=$mock_addr jar=$jar_addr" >&2

got="$("$cast_path" call --rpc-url "$rpc" "$jar_addr" 'get()(uint64)')"
require_uint_equal "$got" "0" "constructor get() must return initial=0"

# --- 2. native balance (SELFBALANCE) -----------------------------------------
# Fund the contract with 1 ETH via the payable acceptNative entry.
# acceptNative(amount) calls pf.assets.native.deposit(amount) which requires
# exact callvalue==amount; send 1 ETH and call with amount=1e18.
one_eth="1000000000000000000"
"$cast_path" send --rpc-url "$rpc" --private-key "$pk" --value 1ether \
  "$jar_addr" 'acceptNative(uint64)' "$one_eth" >/dev/null \
  || die "acceptNative(1 ETH) failed"
# nativeBalance() should return 1e18 (1000000000000000000).
native_bal="$("$cast_path" call --rpc-url "$rpc" "$jar_addr" 'nativeBalance()(uint64)')"
require_uint_equal "$native_bal" "1000000000000000000" "nativeBalance() must return 1 ETH (1e18)"
echo "evm-envread-anvil: native SELFBALANCE ok (1 ETH)" >&2

# --- 3. token balance (STATICCALL balanceOf) ---------------------------------
# Mint 2000 ERC20 to EnvReadJar.
"$cast_path" send --rpc-url "$rpc" --private-key "$pk" "$mock_addr" \
  'mint(address,uint256)' "$jar_addr" 2000 >/dev/null \
  || die "mint to EnvReadJar failed"
# tokenBalance(mock) should return 2000.
# shellcheck disable=SC2207
mint_words=($(principal_words_from_addr "$mock_addr"))
[[ ${#mint_words[@]} -eq 9 ]] || die "mint principal leaves wrong"
token_bal_sig='tokenBalance(uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64)(uint64)'
token_bal="$("$cast_path" call --rpc-url "$rpc" "$jar_addr" "$token_bal_sig" "${mint_words[@]}")"
require_uint_equal "$token_bal" "2000" "tokenBalance(mock) must return 2000"
echo "evm-envread-anvil: token STATICCALL balanceOf ok (2000)" >&2

# --- 4. tip 500 out → tokenBalance drops by 500 ------------------------------
# shellcheck disable=SC2207
dst_words=($(principal_words_from_addr "$dst_eoa"))
[[ ${#dst_words[@]} -eq 9 ]] || die "dst principal leaves wrong"
tip_sig='tipToken(uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64)'
tip_call() { # tip_call <amount> [extra cast args...]
  local amount="$1"; shift
  "$cast_path" send --json --rpc-url "$rpc" --private-key "$pk" "$@" \
    "$jar_addr" "$tip_sig" \
    "${mint_words[@]}" "${dst_words[@]}" "$amount"
}
tip_call 500 >/dev/null || die "tipToken(500) tx failed"
token_bal_after="$("$cast_path" call --rpc-url "$rpc" "$jar_addr" "$token_bal_sig" "${mint_words[@]}")"
require_uint_equal "$token_bal_after" "1500" "tokenBalance(mock) must drop by 500 to 1500"
got="$("$cast_path" call --rpc-url "$rpc" "$jar_addr" 'get()(uint64)')"
require_uint_equal "$got" "500" "tips must be 500 after tipToken(500)"
echo "evm-envread-anvil: tip 500 → tokenBalance drops by 500 ok" >&2

# --- 5. wire-shape negative: malformed mint (len=21) → revert ---------------
if "$cast_path" call --rpc-url "$rpc" "$jar_addr" "$token_bal_sig" \
    21 "${mint_words[@]:1}" >/dev/null 2>&1; then
  die "tokenBalance with mint len=21 must revert"
fi
echo "evm-envread-anvil: wire-shape negative (malformed mint) ok" >&2

echo "evm-envread-anvil: ok (deploy + native SELFBALANCE + token STATICCALL + tip-drop + wire-shape)" >&2
exit 0