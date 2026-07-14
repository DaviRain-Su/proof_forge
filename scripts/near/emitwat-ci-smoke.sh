#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

cargo --version >/dev/null
mkdir -p build/wasm-near

lake env lean --run Tests/Backend/Wasm/EmitWatSmoke.lean
lake env lean --run Tests/Backend/Wasm/EmitWatScalar.lean
lake env lean --run Tests/Backend/Wasm/EmitWatFeatures.lean
lake env lean --run Tests/Backend/Wasm/EmitWatArith.lean
lake env lean --run Tests/Backend/Wasm/EmitWatHash.lean
lake env lean --run Tests/Backend/Wasm/EmitWatContext.lean
lake build ProofForge.IR.Examples.NearCrosscallProbe
lake env lean --run Tests/Backend/Wasm/WasmNearPlan.lean
lake env lean --run Tests/Backend/Wasm/EmitWatMap.lean
lake env lean --run Tests/Backend/Wasm/EmitWatHashmap.lean
lake env lean --run Tests/Backend/Wasm/EmitWatPath.lean
lake env lean --run Tests/Backend/Wasm/EmitWatEvent.lean
lake env lean --run Tests/Backend/Wasm/EmitWatParams.lean
lake env lean --run Tests/Backend/Wasm/EmitWatControl.lean
lake env lean --run Tests/Backend/Wasm/EmitWatArray.lean
lake env lean --run Tests/Backend/Wasm/EmitWatStruct.lean
lake env lean --run Tests/Backend/Wasm/EmitWatAlloc.lean
lake env lean --run Tests/Backend/Wasm/EmitWatOwnership.lean
lake env lean --run Tests/Backend/Wasm/EmitWatValueVault.lean

HOST=(cargo run --quiet --manifest-path runtime/offline-host/Cargo.toml -- run)

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if ! grep -Fq "$needle" <<<"$haystack"; then
    echo "near-emitwat-ci: expected ${label} to contain: ${needle}" >&2
    echo "$haystack" >&2
    exit 1
  fi
}

out="$("${HOST[@]}" build/wasm-near/emitwat-counter.wat initialize get increment get)"
echo "$out"
assert_contains "$out" "call 1:get: return_hex=0000000000000000 return_u64=0" "counter initial get"
assert_contains "$out" "call 1:get: return_hex=0100000000000000 return_u64=1" "counter increment get"

out="$("${HOST[@]}" build/wasm-near/emitwat-features.wat init bump bump getN getFlag)"
echo "$out"
assert_contains "$out" "call 1:getN: return_hex=0a000000 return_u32=10" "features getN"
assert_contains "$out" "call 1:getFlag: return_hex=00 return_bool=false" "features getFlag"

out="$("${HOST[@]}" build/wasm-near/emitwat-arith.wat u32_arithmetic --input-hex 0200000003000000)"
echo "$out"
assert_contains "$out" "call 1:u32_arithmetic: return_hex=0100000000000000 return_u64=1" "arith"

out="$("${HOST[@]}" build/wasm-near/emitwat-hash-storage.wat array_lifecycle)"
echo "$out"
assert_contains "$out" "call 1:array_lifecycle: return_hex=370000000000000042000000000000004d000000000000005800000000000000 return_len=32" "hash array path"

out="$("${HOST[@]}" build/wasm-near/emitwat-deposit.wat depositProbe --attached-deposit 42)"
echo "$out"
assert_contains "$out" "call 1:depositProbe: return_hex=2a00000000000000 return_u64=42" "attached deposit"

out="$("${HOST[@]}" build/wasm-near/emitwat-context.wat blockTimestamp --block-timestamp 777)"
echo "$out"
assert_contains "$out" "call 1:blockTimestamp: return_hex=0903000000000000 return_u64=777" "block timestamp"

out="$("${HOST[@]}" build/wasm-near/emitwat-context.wat epochHeight --epoch-height 88)"
echo "$out"
assert_contains "$out" "call 1:epochHeight: return_hex=5800000000000000 return_u64=88" "epoch height"

SEED_HEX="000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
out="$("${HOST[@]}" build/wasm-near/emitwat-context.wat randomSeed --random-seed-hex "$SEED_HEX")"
echo "$out"
assert_contains "$out" "call 1:randomSeed: return_hex=$SEED_HEX return_len=32" "random seed"

out="$("${HOST[@]}" build/wasm-near/emitwat-path-assign.wat path_assign_lifecycle)"
echo "$out"
assert_contains "$out" "call 1:path_assign_lifecycle: return_hex=1e00000000000000 return_u64=30" "path assign"

out="$("${HOST[@]}" build/wasm-near/emitwat-path-index.wat index_path_lifecycle)"
echo "$out"
assert_contains "$out" "call 1:index_path_lifecycle: return_hex=0f00000000000000 return_u64=15" "index path assign"

out="$("${HOST[@]}" build/wasm-near/emitwat-scalar-struct-path.wat scalar_struct_path_lifecycle)"
echo "$out"
assert_contains "$out" "call 1:scalar_struct_path_lifecycle: return_hex=3000000000000000 return_u64=48" "scalar struct path"

out="$("${HOST[@]}" build/wasm-near/emitwat-array-struct.wat array_struct_lifecycle)"
echo "$out"
assert_contains "$out" "call 1:array_struct_lifecycle: return_hex=1e00000000000000 return_u64=30" "array struct fields"

out="$("${HOST[@]}" build/wasm-near/emitwat-array-struct.wat array_struct_path_lifecycle)"
echo "$out"
assert_contains "$out" "call 1:array_struct_path_lifecycle: return_hex=1e00000000000000 return_u64=30" "array struct path"

for fixture in emitwat-alloc-reset emitwat-alloc-minimal emitwat-alloc-near; do
  out="$("${HOST[@]}" "build/wasm-near/${fixture}.wat" sum_literal --repeat 2)"
  echo "$out"
  assert_contains "$out" "call 1:sum_literal: return_hex=3c00000000000000 return_u64=60" "${fixture} call 1"
  assert_contains "$out" "call 2:sum_literal: return_hex=3c00000000000000 return_u64=60" "${fixture} call 2"
done

out="$("${HOST[@]}" build/wasm-near/emitwat-release-minimal.wat release_then_sum --repeat 2)"
echo "$out"
assert_contains "$out" "call 1:release_then_sum: return_hex=3c00000000000000 return_u64=60" "release call 1"
assert_contains "$out" "call 2:release_then_sum: return_hex=3c00000000000000 return_u64=60" "release call 2"

value_vault_inputs="6400000000000000,,1900000000000000,,6400000000000000fa00000000000000,,,1700000000000000,,,"
out="$("${HOST[@]}" build/wasm-near/emitwat-value-vault.wat \
  initialize get_balance deposit get_balance charge_fee get_balance get_net_value \
  release get_balance snapshot get_net_value \
  --inputs-hex "$value_vault_inputs")"
echo "$out"
assert_contains "$out" "call 1:initialize: return=<none>" "value vault initialize"
assert_contains "$out" "call 1:get_balance: return_hex=6400000000000000 return_u64=100" "value vault initial balance"
assert_contains "$out" "call 1:deposit: return=<none>" "value vault deposit"
assert_contains "$out" "call 1:get_balance: return_hex=7d00000000000000 return_u64=125" "value vault deposited balance"
assert_contains "$out" "call 1:charge_fee: return=<none>" "value vault charge fee"
assert_contains "$out" "call 1:get_balance: return_hex=df00000000000000 return_u64=223" "value vault charged balance"
assert_contains "$out" "call 1:get_net_value: return_hex=dd00000000000000 return_u64=221" "value vault charged net value"
assert_contains "$out" "call 1:release: return=<none>" "value vault release"
assert_contains "$out" "call 1:get_balance: return_hex=c800000000000000 return_u64=200" "value vault released balance"
assert_contains "$out" "call 1:snapshot: return_hex=c800000000000000 return_u64=200" "value vault snapshot"
assert_contains "$out" "call 1:get_net_value: return_hex=c600000000000000 return_u64=198" "value vault final net value"
assert_contains "$out" 'log: EVENT_JSON:{"standard":"proof_forge","version":"1.0.0","event":"VaultInitialized","data":[{"initial":100,"checkpoint":0}]}' "value vault initialized log"
assert_contains "$out" 'log: EVENT_JSON:{"standard":"proof_forge","version":"1.0.0","event":"ValueDeposited","data":[{"amount":25,"balance":125,"operations":2}]}' "value vault deposited log"
assert_contains "$out" 'log: EVENT_JSON:{"standard":"proof_forge","version":"1.0.0","event":"ValueCharged","data":[{"gross":100,"fee":2,"net":98,"balance":223}]}' "value vault charged log"
assert_contains "$out" 'log: EVENT_JSON:{"standard":"proof_forge","version":"1.0.0","event":"ValueReleased","data":[{"amount":23,"balance":200,"released":23}]}' "value vault released log"
assert_contains "$out" 'log: EVENT_JSON:{"standard":"proof_forge","version":"1.0.0","event":"ValueSnapshot","data":[{"balance":200,"released":23,"fees":2,"checkpoint":0}]}' "value vault snapshot log"

echo "near-emitwat-ci: ok"
