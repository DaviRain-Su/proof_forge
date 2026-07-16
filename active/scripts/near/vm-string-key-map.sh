#!/usr/bin/env bash
# Real-NEAR-VM string-keyed U128 map round-trip for the ProofForge wasm-near
# backend (Phase 3 NEP-141 interop gate).
#
# Renders the StringKeyMapProbe IR fixture (Map<string, u128>: write u128(100)
# at an AccountId string key, read it back, return) through EmitWat, compiles
# the WAT to Wasm, and executes it on the *unmodified upstream* NEAR VM
# (near-vm-runner 0.37 / Wasmtime). The map key is a Borsh string parameter
# ("alice.near"), so the runner is invoked with `--input-hex`. The return must
# be the 16-byte little-endian Borsh U128 of 100
# (`64000000000000000000000000000000`) — the shape of NEP-141 `balances` keyed
# by raw AccountId string (no sha256 hashing).
#
# Continuously verifies the variable-length string-keyed map path
# (`__pf_map_buildkey_string` / `__pf_map_read_string_u128` /
# `__pf_map_write_string_u128`, runtime key length `pl + kl`, void-read +
# lo/hi reload lowering, Borsh string param decode into a `(ptr, len)` pair)
# on the real VM.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "vm-string-key-map: missing required tool '$1'" >&2
    exit 1
  }
}
require_cmd cargo
require_cmd wat2wasm
require_cmd lake

OUT_DIR="build/wasm-near"
WAT="$OUT_DIR/emitwat-string-key-map.wat"
WASM="$OUT_DIR/emitwat-string-key-map.wasm"
EXPECTED="64000000000000000000000000000000"
# Borsh string "alice.near": 4-byte LE length (10) + UTF-8 payload. The dynamic
# input decoder bounds the payload to 256 bytes and requires this exact length,
# so trailing flat-slot padding must be rejected.
INPUT_HEX="0a000000616c6963652e6e656172"

echo "=== building + rendering StringKeyMapProbe ==="
lake build ProofForge.Backend.WasmHost.EmitWat ProofForge.IR.Examples.StringKeyMapProbe >/dev/null
lake env lean --run Tests/Backend/Wasm/EmitWatStringKeyMap.lean >/dev/null
test -s "$WAT"
wat2wasm "$WAT" -o "$WASM"
test -s "$WASM"

echo "=== string-keyed U128 map round-trip on real NEAR VM ==="
out="$(cargo run --quiet --manifest-path tools/near-vm-runner/Cargo.toml -- "$WASM" map_roundtrip --input-hex "$INPUT_HEX")"
echo "$out"

fail() { echo "vm-string-key-map: $*" >&2; exit 1; }
grep -qiE 'ABORTED|failed|LinkError' <<<"$out" && fail "real NEAR VM rejected the string-key map module"
grep -qF "call map_roundtrip: return_hex=$EXPECTED" <<<"$out" \
  || fail "string-key map round-trip did not return 16-byte LE of 100 (got: $(grep -F 'return_hex=' <<<"$out"))"
grep -qF '1 methods executed successfully on real NEAR VM' <<<"$out" \
  || fail "did not report 1 successful method"

echo "vm-string-key-map: ok (string-keyed U128 map value read/write + Borsh return on real NEAR VM)"
