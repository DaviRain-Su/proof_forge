#!/usr/bin/env bash
# Real-NEAR-VM U128 scalar round-trip for the ProofForge wasm-near backend.
#
# Renders the U128StorageScalarProbe IR fixture (write u128(7), read it back,
# return it) through EmitWat, compiles the WAT to Wasm, and executes it on the
# *unmodified upstream* NEAR VM (near-vm-runner 0.37 / Wasmtime). The return
# must be the 16-byte little-endian Borsh U128 encoding of 7
# (`07000000000000000000000000000000`).
#
# This continuously verifies the U128 storage read/write + return path on the
# real VM — the foundation for NEP-141 U128 token amounts. It guards against
# the class of regression where the U128 helpers (`__pf_read_u128`,
# `__pf_write_u128`, `__pf_return_u128`) are referenced by the lowering but not
# emitted into the module.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "vm-u128-scalar: missing required tool '$1'" >&2
    exit 1
  }
}
require_cmd cargo
require_cmd wat2wasm
require_cmd lake

OUT_DIR="build/wasm-near"
WAT="$OUT_DIR/emitwat-u128.wat"
WASM="$OUT_DIR/emitwat-u128.wasm"

echo "=== building + rendering U128StorageScalarProbe ==="
lake build ProofForge.Backend.WasmHost.EmitWat ProofForge.IR.Examples.U128StorageScalarProbe >/dev/null
lake env lean --run Tests/Backend/Wasm/EmitWatU128.lean >/dev/null
test -s "$WAT"
wat2wasm "$WAT" -o "$WASM"
test -s "$WASM"

echo "=== U128 scalar round-trip + assignOp + comparison on real NEAR VM ==="
fail() { echo "vm-u128-scalar: $*" >&2; exit 1; }

run_case() {
  local method="$1" expected="$2" label="$3"
  local line
  line="$(cargo run --quiet --manifest-path tools/near-vm-runner/Cargo.toml -- "$WASM" "$method")"
  echo "$line"
  grep -qiE 'ABORTED|failed|LinkError' <<<"$line" && fail "$label rejected by real NEAR VM"
  grep -qF "call $method: return_hex=$expected" <<<"$line" \
    || fail "$label did not return $expected (got: $(grep -F "return_hex=" <<<"$line"))"
}

run_case storage_roundtrip "07000000000000000000000000000000" "u128 read/write round-trip"
run_case storage_lifecycle  "0c000000000000000000000000000000" "u128 scalar assignOp add (7 + 5 = 12)"
run_case storage_ge         "01"                                "u128 ge comparison (12 >= 10)"
run_case storage_letbind    "0c000000000000000000000000000000" "u128 two-word local (let-bind + assertEq + ge)"

echo "vm-u128-scalar: ok (U128 storage read/write + assignOp + Borsh return + comparison + two-word locals on real NEAR VM)"
