#!/usr/bin/env bash
# Real-NEAR-VM U128 hash-keyed map round-trip for the ProofForge wasm-near backend.
#
# Renders the U128MapProbe IR fixture (Map<hash, u128>: write u128(100) at a
# hash key, read it back, return) through EmitWat, compiles the WAT to Wasm, and
# executes it on the *unmodified upstream* NEAR VM (near-vm-runner 0.37 /
# Wasmtime). The return must be the 16-byte little-endian Borsh U128 of 100
# (`64000000000000000000000000000000`) — the shape of NEP-141 `balances`.
#
# Continuously verifies the two-word U128 map value path (hash-keyed
# `__pf_map_read_hash_u128` / `__pf_map_write_hash_u128`, the void-read +
# lo/hi reload lowering) on the real VM.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "vm-u128-map: missing required tool '$1'" >&2
    exit 1
  }
}
require_cmd cargo
require_cmd wat2wasm
require_cmd lake

OUT_DIR="build/wasm-near"
WAT="$OUT_DIR/emitwat-u128-map.wat"
WASM="$OUT_DIR/emitwat-u128-map.wasm"
EXPECTED="64000000000000000000000000000000"

echo "=== building + rendering U128MapProbe ==="
lake build ProofForge.Backend.WasmHost.EmitWat ProofForge.IR.Examples.U128MapProbe >/dev/null
lake env lean --run Tests/Backend/Wasm/EmitWatU128Map.lean >/dev/null
test -s "$WAT"
wat2wasm "$WAT" -o "$WASM"
test -s "$WASM"

echo "=== U128 hash-keyed map round-trip on real NEAR VM ==="
out="$(cargo run --quiet --manifest-path tools/near-vm-runner/Cargo.toml -- "$WASM" map_roundtrip)"
echo "$out"

fail() { echo "vm-u128-map: $*" >&2; exit 1; }
grep -qiE 'ABORTED|failed|LinkError' <<<"$out" && fail "real NEAR VM rejected the U128 map module"
grep -qF "call map_roundtrip: return_hex=$EXPECTED" <<<"$out" \
  || fail "u128 map round-trip did not return 16-byte LE of 100 (got: $(grep -F 'return_hex=' <<<"$out"))"
grep -qF '1 methods executed successfully on real NEAR VM' <<<"$out" \
  || fail "did not report 1 successful method"

echo "vm-u128-map: ok (U128 hash-keyed map value read/write + Borsh return on real NEAR VM)"
