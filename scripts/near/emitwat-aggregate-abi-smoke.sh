#!/usr/bin/env bash
# Validate aggregate Borsh returns as executable WAT and exact host bytes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

OUT="build/emitwat-aggregate-abi"
HOST=(cargo run --quiet --manifest-path runtime/offline-host/Cargo.toml -- run)

fail() {
  echo "emitwat-aggregate-abi: $*" >&2
  exit 1
}

command -v wat2wasm >/dev/null 2>&1 || fail "wat2wasm not on PATH"

rm -rf "$OUT"
lake build ProofForge.Backend.WasmHost.EmitWat
lake env lean --run Tests/Backend/Wasm/EmitWatAggregateAbi.lean

for name in struct-return fixed-array-return hash-array-return; do
  wat="$OUT/$name.wat"
  [[ -s "$wat" ]] || fail "missing generated $wat"
  wat2wasm "$wat" -o "$OUT/$name.wasm" || fail "$name WAT validation failed"
done

pair_out="$("${HOST[@]}" "$OUT/struct-return.wat" make \
  --inputs-hex 07000000000000000900000000000000)"
echo "$pair_out"
grep -Fq "return_hex=07000000000000000900000000000000 return_len=16" <<<"$pair_out" || \
  fail "struct return bytes do not match Borsh Pair(7, 9)"

array_out="$("${HOST[@]}" "$OUT/fixed-array-return.wat" zeros)"
echo "$array_out"
grep -Fq "return_hex=00000000000000000100000000000000 return_len=16" <<<"$array_out" || \
  fail "fixedArray<U64,2> return bytes do not match [0, 1]"

hash_out="$("${HOST[@]}" "$OUT/hash-array-return.wat" roots)"
echo "$hash_out"
expected_hashes="01000000000000000200000000000000030000000000000004000000000000000500000000000000060000000000000007000000000000000800000000000000"
grep -Fq "return_hex=$expected_hashes return_len=64" <<<"$hash_out" || \
  fail "fixedArray<Hash,2> return copied pointers instead of 64 payload bytes"

echo "emitwat-aggregate-abi: ok (wat2wasm + exact offline-host Borsh returns)"
