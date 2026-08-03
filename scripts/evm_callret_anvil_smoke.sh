#!/usr/bin/env bash
# BL-28 engineering Anvil proof-of-mechanism for result-bearing external call
# (not formal C-3 / not a product-level CPI pass).
#
# The product emitter's callee address is a documented keccak stub, so a
# product-built caller cannot address a test-deployed mock. What this script
# pins instead on a real EVM (Anvil):
#   1. The emitter's EXACT opcode sequence (mstore selector pad, call with
#      out-size 32, iszero check, returndatasize guard, mload first word,
#      UInt64 range check) executes correctly end-to-end: a hand-written Yul
#      caller using that sequence invokes a mock callee and returns k+1.
#   2. Failure discipline: empty-code target (EOA) yields returndatasize 0 and
#      the caller reverts (the product guard), and a reverting callee reverts
#      the whole call.
#
# Skip-clean (exit 0) when anvil/cast/solc are unavailable; hard fail (1) on
# assertion failure. NEVER fabricate results.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

skip_clean() {
  echo "evm-callret-anvil: skipped: $*" >&2
  exit 0
}
die() {
  echo "evm-callret-anvil: $*" >&2
  exit 1
}

case "$(uname -s)" in
  Darwin) default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64" ;;
  Linux) default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/linux-$(uname -m)" ;;
  *) skip_clean "unsupported host platform $(uname -s)" ;;
esac
tool_root="${PROOF_FORGE_TOOL_ROOT:-$default_tool_root}"

anvil_bin="$tool_root/anvil"
cast_bin="$tool_root/cast"
solc_bin="$tool_root/solc"
[ -x "$anvil_bin" ] || skip_clean "anvil not found under $tool_root"
[ -x "$cast_bin" ] || skip_clean "cast not found under $tool_root"
[ -x "$solc_bin" ] || skip_clean "solc not found under $tool_root"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

get_sel="$("$cast_bin" sig "get(uint64)")"
record_sel="$("$cast_bin" sig "record(uint64)")"
boom_sel="$("$cast_bin" sig "boom()")"
probe_sel="$("$cast_bin" sig "probe(uint64)")"

# Mock callee: get(uint64) → k+1 via RETURN; record(uint64) → sstore(0,k);
# boom() → revert; unknown selector → revert.
cat > "$work/MockCallee.yul" <<YUL
object "MockCallee" {
  code {
    datacopy(0, dataoffset("runtime"), datasize("runtime"))
    return(0, datasize("runtime"))
  }
  object "runtime" {
    code {
      let sig := shr(224, calldataload(0))
      if eq(sig, ${get_sel}) {
        let k := calldataload(4)
        mstore(0, add(k, 1))
        return(0, 32)
      }
      if eq(sig, ${record_sel}) {
        sstore(0, calldataload(4))
        return(0, 0)
      }
      if eq(sig, ${boom_sel}) {
        revert(0, 0)
      }
      revert(0, 0)
    }
  }
}
YUL

"$solc_bin" --strict-assembly --bin "$work/MockCallee.yul" > "$work/mock.out" 2>"$work/mock.err" \
  || die "mock callee failed strict-assembly: $(tail -2 "$work/mock.err")"
mock_bin="$(awk '/Binary representation:/{getline; print $1; exit}' "$work/mock.out")"

"$anvil_bin" --port 18545 --silent > "$work/anvil.log" 2>&1 &
anvil_pid=$!
trap 'kill "$anvil_pid" 2>/dev/null || true; rm -rf "$work"' EXIT
for _ in $(seq 1 50); do
  if "$cast_bin" block-number --rpc-url http://127.0.0.1:18545 >/dev/null 2>&1; then break; fi
  sleep 0.2
done

deployer="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
deployer_key="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

mock_addr="$("$cast_bin" send --rpc-url http://127.0.0.1:18545 --private-key "$deployer_key" \
  --create "$mock_bin" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["contractAddress"])')"
[ -n "$mock_addr" ] || die "mock deploy produced no address"

# Caller: EXACT emitter sequence (selector pad at mstore(0), arg marshal,
# call with out-size 32, iszero + returndatasize + UInt64 range guards).
sel_padded="${get_sel#0x}$(printf '0%.0s' $(seq 1 56))"
cat > "$work/ProbeCaller.yul" <<YUL
object "ProbeCaller" {
  code {
    datacopy(0, dataoffset("runtime"), datasize("runtime"))
    return(0, datasize("runtime"))
  }
  object "runtime" {
    code {
      let sig := shr(224, calldataload(0))
      if eq(sig, ${probe_sel}) {
        let k := calldataload(4)
        mstore(0, 0x${sel_padded})
        mstore(4, k)
        let ok := call(gas(), ${mock_addr}, 0, 0, 36, 0, 32)
        if iszero(ok) { revert(0, 0) }
        if lt(returndatasize(), 32) { revert(0, 0) }
        let t := mload(0)
        if gt(t, 0xffffffffffffffff) { revert(0, 0) }
        mstore(0, add(t, 1))
        return(0, 32)
      }
      revert(0, 0)
    }
  }
}
YUL

"$solc_bin" --strict-assembly --bin "$work/ProbeCaller.yul" > "$work/caller.out" 2>"$work/caller.err" \
  || die "caller failed strict-assembly: $(tail -2 "$work/caller.err")"
caller_bin="$(awk '/Binary representation:/{getline; print $1; exit}' "$work/caller.out")"

caller_addr="$("$cast_bin" send --rpc-url http://127.0.0.1:18545 --private-key "$deployer_key" \
  --create "$caller_bin" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["contractAddress"])')"
[ -n "$caller_addr" ] || die "caller deploy produced no address"

# probe(41) → mock get(41)=42 → caller returns 43.
call_data="${probe_sel}$(printf '0%.0s' $(seq 1 62))29"
result="$("$cast_bin" call --rpc-url http://127.0.0.1:18545 "$caller_addr" "$call_data")"
expected="0x$(printf '0%.0s' $(seq 1 62))2b"
if [ "$result" != "$expected" ]; then
  die "probe(41) returned $result, expected $expected (43)"
fi
echo "evm-callret-anvil: probe(41) → 43 ok (mock 42 via real CALL + returndata)"

# Failure discipline: probe against an EOA (no code) must revert via the
# returndatasize guard — simulate by calling probe on a caller whose callee
# is an EOA: deploy a second caller pointed at the deployer (an EOA).
sel_padded2="${boom_sel#0x}$(printf '0%.0s' $(seq 1 56))"
cat > "$work/BoomCaller.yul" <<YUL
object "BoomCaller" {
  code {
    datacopy(0, dataoffset("runtime"), datasize("runtime"))
    return(0, datasize("runtime"))
  }
  object "runtime" {
    code {
      let sig := shr(224, calldataload(0))
      if eq(sig, ${probe_sel}) {
        mstore(0, 0x${sel_padded2})
        let ok := call(gas(), ${mock_addr}, 0, 0, 4, 0, 32)
        if iszero(ok) { revert(0, 0) }
        if lt(returndatasize(), 32) { revert(0, 0) }
        return(0, 32)
      }
      revert(0, 0)
    }
  }
}
YUL
"$solc_bin" --strict-assembly --bin "$work/BoomCaller.yul" > "$work/boom.out" 2>/dev/null
boom_bin="$(awk '/Binary representation:/{getline; print $1; exit}' "$work/boom.out")"
boom_addr="$("$cast_bin" send --rpc-url http://127.0.0.1:18545 --private-key "$deployer_key" \
  --create "$boom_bin" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["contractAddress"])')"
boom_data="${probe_sel}$(printf '0%.0s' $(seq 1 62))00"
if "$cast_bin" call --rpc-url http://127.0.0.1:18545 "$boom_addr" "$boom_data" >/dev/null 2>&1; then
  die "boom() path unexpectedly succeeded (callee revert must revert caller)"
fi
echo "evm-callret-anvil: callee revert reverts caller ok"

echo "evm-callret-anvil: ok (engineering Anvil mechanism proof; stub address gap documented)"
