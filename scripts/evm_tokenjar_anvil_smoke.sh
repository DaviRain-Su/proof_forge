#!/usr/bin/env bash
# ADR-0030 E1a: TokenJar (pf.assets.token.transfer) Anvil engineering gate.
# Real local_runtime evidence only (not formal C-3 / Reference↔Anvil closure).
#
# Scenarios (runtime-tests/evm/SCENARIOS.md):
#   1. deploy ERC20Mock + TokenJar(initial=0)
#   2. happy path: mint 2000 to TokenJar; tipToken 1000 → dst +1000, jar −1000,
#      tips == 1000
#   3. insufficient contract balance → revert (state holds)
#   4. returnFalse mode + over-amount → false return → revert (state holds)
#   5. noReturn mode (USDT-style) → success path
#   6. wire-shape negatives: mint len≠20 / dst high-limb nonzero → revert
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
    echo "evm-tokenjar-anvil: explicit skip: missing $tool (optional; not pass)" >&2
    exit 0
  fi
done

cli="$root/.lake/build/bin/proof-forge-next"
echo "evm-tokenjar-anvil: building proof-forge-next (lake build proof_forge_next)" >&2
lake build proof_forge_next || die "lake build proof_forge_next failed"
if [[ ! -x "$cli" ]]; then
  echo "evm-tokenjar-anvil: explicit skip: product CLI missing (optional; not pass)" >&2
  exit 0
fi

die() { echo "evm-tokenjar-anvil: FAIL: $*" >&2; exit 1; }

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
mock_out="$root/build/v2/erc20mock"
rm -rf "$mock_out"
mkdir -p "$mock_out"
"$solc_path" --bin --abi --optimize \
  --input-file "$root/runtime-tests/evm/ERC20Mock.sol" \
  --output-dir "$mock_out" --overwrite \
  || die "locked solc failed on ERC20Mock.sol"
[[ -s "$mock_out/ERC20Mock.bin" ]] || die "ERC20Mock.bin missing after solc"

tokenjar_out="$root/build/v2/tokenjar-evm"
rm -rf "$tokenjar_out"
lake env "$cli" build Examples/TokenJar.lean \
  --module Examples.TokenJar --target evm -o "$tokenjar_out" \
  || die "product build of TokenJar (evm) failed"
[[ -s "$tokenjar_out/TokenJar.bin" ]] || die "TokenJar.bin missing"

# --- anvil -----------------------------------------------------------------
port=$((19545 + RANDOM % 1000))
chain_id="${PF_EVM_CHAIN_ID:-31339}"
pk=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
dst_eoa=0x70997970C51812dc3A010C7d01b50e0d17dc79C8

anvil_log="$(mktemp "${TMPDIR:-/tmp}/pf-tokenjar-anvil.XXXXXX.log")"
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
  echo "evm-tokenjar-anvil: explicit skip: anvil failed to start (optional; not pass; see $anvil_log)" >&2
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
jar_addr="$(deploy "$tokenjar_out/TokenJar.bin" 'constructor(uint64)' 0)"
[[ -n "$jar_addr" && "$jar_addr" != "null" ]] || die "deploy TokenJar failed"
echo "evm-tokenjar-anvil: mock=$mock_addr jar=$jar_addr" >&2

got="$("$cast_path" call --rpc-url "$rpc" "$jar_addr" 'get()(uint64)')"
require_uint_equal "$got" "0" "constructor get() must return initial=0"

# --- 2. happy path -----------------------------------------------------------
"$cast_path" send --rpc-url "$rpc" --private-key "$pk" "$mock_addr" \
  'mint(address,uint256)' "$jar_addr" 2000 >/dev/null \
  || die "mint to TokenJar failed"
jar_tok="$("$cast_path" call --rpc-url "$rpc" "$mock_addr" 'balanceOf(address)(uint256)' "$jar_addr")"
require_uint_equal "$jar_tok" "2000" "mint: TokenJar token balance must be 2000"

# shellcheck disable=SC2207
mint_words=($(principal_words_from_addr "$mock_addr"))
# shellcheck disable=SC2207
dst_words=($(principal_words_from_addr "$dst_eoa"))
[[ ${#mint_words[@]} -eq 9 && ${#dst_words[@]} -eq 9 ]] || die "principal leaves wrong"

tip_sig='tipToken(uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64)'
tip_call() { # tip_call <amount> [extra cast args...]
  local amount="$1"; shift
  "$cast_path" send --json --rpc-url "$rpc" --private-key "$pk" "$@" \
    "$jar_addr" "$tip_sig" \
    "${mint_words[@]}" "${dst_words[@]}" "$amount"
}

tip_json="$(tip_call 1000)" || die "tipToken(1000) tx failed"
require_equal "$?" "0" "tipToken happy path exit"
dst_tok="$("$cast_path" call --rpc-url "$rpc" "$mock_addr" 'balanceOf(address)(uint256)' "$dst_eoa")"
require_uint_equal "$dst_tok" "1000" "happy: dst token balance must be 1000"
jar_tok="$("$cast_path" call --rpc-url "$rpc" "$mock_addr" 'balanceOf(address)(uint256)' "$jar_addr")"
require_uint_equal "$jar_tok" "1000" "happy: TokenJar token balance must be 1000"
got="$("$cast_path" call --rpc-url "$rpc" "$jar_addr" 'get()(uint64)')"
require_uint_equal "$got" "1000" "happy: tips must be 1000"
echo "evm-tokenjar-anvil: happy path ok (dst +1000, jar -1000, tips 1000)" >&2

# --- 3. insufficient balance → revert ---------------------------------------
if tip_call 5000 >/dev/null 2>&1; then
  die "tipToken(5000) with balance 1000 must revert (insufficient)"
fi
got="$("$cast_path" call --rpc-url "$rpc" "$jar_addr" 'get()(uint64)')"
require_uint_equal "$got" "1000" "insufficient: tips must hold 1000"
jar_tok="$("$cast_path" call --rpc-url "$rpc" "$mock_addr" 'balanceOf(address)(uint256)' "$jar_addr")"
require_uint_equal "$jar_tok" "1000" "insufficient: jar token balance must hold 1000"
echo "evm-tokenjar-anvil: insufficient-balance revert ok" >&2

# --- 4. false return → revert ------------------------------------------------
"$cast_path" send --rpc-url "$rpc" --private-key "$pk" "$mock_addr" \
  'setReturnFalseMode(bool)' true >/dev/null || die "setReturnFalseMode failed"
# balance 1000 < 1500 → mock returns false → TokenJar predicate must revert.
if tip_call 1500 >/dev/null 2>&1; then
  die "tipToken(1500) with false-return must revert"
fi
got="$("$cast_path" call --rpc-url "$rpc" "$jar_addr" 'get()(uint64)')"
require_uint_equal "$got" "1000" "false-return: tips must hold 1000"
"$cast_path" send --rpc-url "$rpc" --private-key "$pk" "$mock_addr" \
  'setReturnFalseMode(bool)' false >/dev/null || die "reset returnFalseMode failed"
echo "evm-tokenjar-anvil: false-return revert ok" >&2

# --- 5. USDT-style no-return → success ---------------------------------------
"$cast_path" send --rpc-url "$rpc" --private-key "$pk" "$mock_addr" \
  'setNoReturnMode(bool)' true >/dev/null || die "setNoReturnMode failed"
tip_call 500 >/dev/null || die "tipToken(500) in noReturn mode must succeed"
"$cast_path" send --rpc-url "$rpc" --private-key "$pk" "$mock_addr" \
  'setNoReturnMode(bool)' false >/dev/null || die "reset noReturnMode failed"
dst_tok="$("$cast_path" call --rpc-url "$rpc" "$mock_addr" 'balanceOf(address)(uint256)' "$dst_eoa")"
require_uint_equal "$dst_tok" "1500" "noReturn: dst must be 1500"
got="$("$cast_path" call --rpc-url "$rpc" "$jar_addr" 'get()(uint64)')"
require_uint_equal "$got" "1500" "noReturn: tips must be 1500"
echo "evm-tokenjar-anvil: USDT-style no-return success ok" >&2

# --- 6. wire-shape negatives --------------------------------------------------
# mint len=21 (first word 21 instead of 20)
if "$cast_path" send --json --rpc-url "$rpc" --private-key "$pk" \
    "$jar_addr" "$tip_sig" \
    21 "${mint_words[@]:1}" "${dst_words[@]}" 100 >/dev/null 2>&1; then
  die "tipToken with mint len=21 must revert"
fi
# dst high limb nonzero (w3 = 1)
if "$cast_path" send --json --rpc-url "$rpc" --private-key "$pk" \
    "$jar_addr" "$tip_sig" \
    "${mint_words[@]}" 20 "${dst_words[@]:1:3}" 1 0 0 0 0 100 >/dev/null 2>&1; then
  die "tipToken with dst high-limb nonzero must revert"
fi
got="$("$cast_path" call --rpc-url "$rpc" "$jar_addr" 'get()(uint64)')"
require_uint_equal "$got" "1500" "wire-shape negatives: tips must hold 1500"
echo "evm-tokenjar-anvil: wire-shape negatives ok" >&2

echo "evm-tokenjar-anvil: ok (deploy + happy + insufficient + false-return + no-return + wire-shape)" >&2
exit 0
