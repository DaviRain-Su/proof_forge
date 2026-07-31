#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
case "$(uname -s)" in
  Darwin)
    default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64"
    lock_file="$root/toolchains.lock.json"
    ;;
  Linux)
    default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/linux-$(uname -m)"
    lock_file="$root/toolchains-linux-$(uname -m).lock.json"
    ;;
  *)
    echo "evm-smoke: unsupported host platform" >&2
    exit 2
    ;;
esac
foundry_bin="${FOUNDRY_BIN:-${PROOF_FORGE_TOOL_ROOT:-$default_tool_root}}"
anvil="$foundry_bin/anvil"
cast="$foundry_bin/cast"
port="${PF_EVM_PORT:-18545}"
chain_id="${PF_EVM_CHAIN_ID:-31338}"
rpc="http://127.0.0.1:$port"
private_key="${PF_EVM_PRIVATE_KEY:-ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
log="$root/build/v2/anvil.log"

die() {
  echo "evm-smoke: $*" >&2
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
  if [[ "$actual" =~ ^([0-9]+)(\ \[[0-9.eE+-]+\])?$ ]]; then
    canonical="${BASH_REMATCH[1]}"
  else
    die "$message (expected uint output, got '$actual')"
  fi
  require_equal "$canonical" "$expected" "$message"
}

for tool in "$anvil" "$cast"; do
  if [[ ! -x "$tool" ]]; then
    echo "evm-smoke: missing $tool" >&2
    exit 2
  fi
done

expected_hash() {
  /usr/bin/python3 -I -S -c 'import json,sys; data=json.load(open(sys.argv[1], encoding="utf-8")); print(next(tool["executableSha256"] for tool in data["tools"] if tool["id"] == sys.argv[2]))' \
    "$lock_file" "$1"
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

actual_anvil_hash="$(sha256_of "$anvil")"
actual_cast_hash="$(sha256_of "$cast")"
require_equal "$actual_anvil_hash" "$(expected_hash anvil)" "Anvil hash mismatch"
require_equal "$actual_cast_hash" "$(expected_hash cast)" "cast hash mismatch"

if ! "$anvil" --version | grep -Fq '0.3.0 (5a8bd89'; then
  die "unexpected Anvil version"
fi
if ! "$cast" --version | grep -Fq '0.3.0 (5a8bd89'; then
  die "unexpected cast version"
fi

mkdir -p "$root/build/v2"
if "$cast" chain-id --rpc-url "$rpc" >/dev/null 2>&1; then
  die "RPC endpoint $rpc is already occupied"
fi
"$anvil" --host 127.0.0.1 --port "$port" --chain-id "$chain_id" --silent >"$log" 2>&1 &
anvil_pid=$!
cleanup() {
  kill "$anvil_pid" 2>/dev/null || true
  wait "$anvil_pid" 2>/dev/null || true
}
trap cleanup EXIT

anvil_running() {
  local running_jobs
  running_jobs="$(jobs -pr)"
  [[ "$running_jobs" == "$anvil_pid" ]]
}

ready=0
for _ in $(seq 1 50); do
  if ! anvil_running; then
    wait "$anvil_pid" 2>/dev/null || true
    echo "evm-smoke: launched Anvil exited before readiness; see $log" >&2
    exit 1
  fi
  if "$cast" chain-id --rpc-url "$rpc" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.1
done
if [[ "$ready" != 1 ]]; then
  echo "evm-smoke: anvil failed to start; see $log" >&2
  exit 1
fi
if ! anvil_running; then
  echo "evm-smoke: launched Anvil exited after readiness; refusing an incumbent RPC" >&2
  exit 1
fi
require_equal "$($cast chain-id --rpc-url "$rpc")" "$chain_id" \
  "launched Anvil chain identity mismatch"

deploy() {
  local program="$1"
  local initial="$2"
  local artifact bytecode encoded receipt
  case "$program" in
    evm) artifact=Counter ;;
    evm-accumulator) artifact=Accumulator ;;
    evm-arithops) artifact=ArithOps ;;
    *) echo "evm-smoke: unknown program artifact '$program'" >&2; return 2 ;;
  esac
  bytecode="$(tr -d '\n\r ' < "$root/build/v2/$program/$artifact.bin")"
  encoded="$($cast abi-encode 'constructor(uint64)' "$initial")"
  receipt="$($cast send --json --rpc-url "$rpc" --private-key "$private_key" --create "0x${bytecode}${encoded#0x}")"
  /usr/bin/python3 -I -S -c 'import json,sys; print(json.load(sys.stdin)["contractAddress"])' <<<"$receipt"
}

counter="$(deploy evm 7)"
before="$($cast call --rpc-url "$rpc" "$counter" 'get()(uint64)')"
require_uint_equal "$before" "7" "Counter constructor state mismatch"
counter_simulated="$($cast call --rpc-url "$rpc" "$counter" 'increment(uint64)(uint64)' 5)"
require_uint_equal "$counter_simulated" "12" "Counter increment return mismatch"
require_uint_equal "$($cast call --rpc-url "$rpc" "$counter" 'get()(uint64)')" "7" \
  "Counter eth_call unexpectedly committed state"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" --value 2 \
    "$counter" 'increment(uint64)' 5 >/dev/null 2>&1; then
  echo "evm-smoke: nonpayable increment unexpectedly accepted value" >&2
  exit 1
fi
"$cast" send --rpc-url "$rpc" --private-key "$private_key" "$counter" 'increment(uint64)' 5 >/dev/null
after="$($cast call --rpc-url "$rpc" "$counter" 'get()(uint64)')"
require_uint_equal "$after" "12" "Counter increment state mismatch"
balance="$($cast balance --rpc-url "$rpc" "$counter")"
require_equal "$balance" "0" "Counter accepted native value"

bytecode="$(tr -d '\n\r ' < "$root/build/v2/evm/Counter.bin")"
encoded="$($cast abi-encode 'constructor(uint64)' 7)"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" --value 1 --create \
    "0x${bytecode}${encoded#0x}" >/dev/null 2>&1; then
  echo "evm-smoke: nonpayable constructor unexpectedly accepted value" >&2
  exit 1
fi

max_counter="$(deploy evm 18446744073709551615)"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$max_counter" 'increment(uint64)' 1 >/dev/null 2>&1; then
  echo "evm-smoke: overflow transaction unexpectedly succeeded" >&2
  exit 1
fi
preserved="$($cast call --rpc-url "$rpc" "$max_counter" 'get()(uint64)')"
require_uint_equal "$preserved" "18446744073709551615" "Counter overflow changed state"

accumulator="$(deploy evm-accumulator 7)"
accumulator_before="$($cast call --rpc-url "$rpc" "$accumulator" 'current()(uint64)')"
require_uint_equal "$accumulator_before" "7" "Accumulator constructor state mismatch"
accumulator_simulated="$($cast call --rpc-url "$rpc" "$accumulator" 'add(uint64)(uint64)' 5)"
require_uint_equal "$accumulator_simulated" "12" "Accumulator add return mismatch"
require_uint_equal "$($cast call --rpc-url "$rpc" "$accumulator" 'current()(uint64)')" "7" \
  "Accumulator eth_call unexpectedly committed state"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$accumulator" 'add(uint64)' 5 >/dev/null
accumulator_after="$($cast call --rpc-url "$rpc" "$accumulator" 'current()(uint64)')"
require_uint_equal "$accumulator_after" "12" "Accumulator add state mismatch"
max_accumulator="$(deploy evm-accumulator 18446744073709551615)"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$max_accumulator" 'add(uint64)' 1 >/dev/null 2>&1; then
  echo "evm-smoke: Accumulator overflow transaction unexpectedly succeeded" >&2
  exit 1
fi
accumulator_preserved="$($cast call --rpc-url "$rpc" "$max_accumulator" 'current()(uint64)')"
require_uint_equal "$accumulator_preserved" "18446744073709551615" \
  "Accumulator overflow changed state"

# ArithOps differential: masked bitNot (`~x = 2^64-1-x`) and checkedMul
# overflow (scale with count = UInt64.max and factor = 2 must revert; the
# previous Yul round-trip div guard could never fire and silently admitted
# 2^32 * 2^32 = 2^64).
arith="$(deploy evm-arithops 7)"
bits_zero="$($cast call --rpc-url "$rpc" "$arith" 'bits(uint64)(uint64)' 0)"
require_uint_equal "$bits_zero" "18446744073709551615" "ArithOps bits(0) must be UInt64.max (masked bitNot)"
bits_five="$($cast call --rpc-url "$rpc" "$arith" 'bits(uint64)(uint64)' 5)"
require_uint_equal "$bits_five" "18446744073709551610" "ArithOps bits(5) must be UInt64.max - 5"
scale_ok="$($cast call --rpc-url "$rpc" "$arith" 'scale(uint64,uint64)(uint64)' 3 2)"
require_uint_equal "$scale_ok" "11" "ArithOps scale(3,2) mismatch"
max_arith="$(deploy evm-arithops 18446744073709551615)"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$max_arith" 'scale(uint64,uint64)' 2 1 >/dev/null 2>&1; then
  echo "evm-smoke: checkedMul overflow transaction unexpectedly succeeded" >&2
  exit 1
fi

echo "evm-smoke: ok (Counter + generic Accumulator init/add/read/overflow rollback + ArithOps mul overflow/masked bitNot)"
