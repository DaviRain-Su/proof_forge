#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

cargo --version >/dev/null
mkdir -p build/wasm-near

lake env lean --run Tests/EmitWatSmoke.lean
lake env lean --run Tests/EmitWatScalar.lean
lake env lean --run Tests/EmitWatFeatures.lean
lake env lean --run Tests/EmitWatArith.lean
lake env lean --run Tests/EmitWatHash.lean
lake env lean --run Tests/EmitWatContext.lean
lake env lean --run Tests/EmitWatMap.lean
lake env lean --run Tests/EmitWatHashmap.lean
lake env lean --run Tests/EmitWatPath.lean
lake env lean --run Tests/EmitWatEvent.lean
lake env lean --run Tests/EmitWatParams.lean
lake env lean --run Tests/EmitWatControl.lean
lake env lean --run Tests/EmitWatArray.lean
lake env lean --run Tests/EmitWatStruct.lean
lake env lean --run Tests/EmitWatAlloc.lean
lake env lean --run Tests/EmitWatOwnership.lean
lake env lean --run Tests/EmitWatChainSemantics.lean

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

echo "near-emitwat-ci: ok"
