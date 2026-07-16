#!/usr/bin/env bash
# Real-NEAR-VM caller-AccountId-keyed U128 map round-trip (Phase 3 NEP-141
# interop gate — Landing 2 context path).
#
# Renders the CallerAccountIdMapProbe IR fixture — a string-keyed
# Map<string, u128> keyed by the RAW predecessor account id (NOT a Borsh param
# and NOT sha256) — through EmitWat, compiles the WAT to Wasm, and executes
# `map_roundtrip` (write u128(100) at the caller's AccountId, read it back,
# return) on the *unmodified upstream* NEAR VM (near-vm-runner 0.37 / Wasmtime).
# The runner sets `predecessor_account_id = "proof-forge.testnet"`. The return
# must be the 16-byte little-endian Borsh U128 of 100
# (`64000000000000000000000000000000`).
#
# Continuously verifies the `__pf_ctx_account_id` host path (raw
# `predecessor_account_id` staged at `ACCT_ID_BUF` + length at `ACCT_ID_LEN`,
# no sha256) plus the variable-length string-keyed map read/write path on the
# real VM. Identity is no longer hash-truncated.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "vm-caller-account-id-map: missing required tool '$1'" >&2
    exit 1
  }
}
require_cmd cargo
require_cmd wat2wasm
require_cmd lake

OUT_DIR="build/wasm-near"
WAT="$OUT_DIR/emitwat-caller-account-id-map.wat"
WASM="$OUT_DIR/emitwat-caller-account-id-map.wasm"
EXPECTED="64000000000000000000000000000000"

echo "=== building + rendering CallerAccountIdMapProbe ==="
lake build ProofForge.Backend.WasmHost.EmitWat ProofForge.IR.Examples.CallerAccountIdMapProbe >/dev/null
lake env lean --run Tests/Backend/Wasm/EmitWatCallerAccountIdMap.lean >/dev/null
test -s "$WAT"
wat2wasm "$WAT" -o "$WASM"
test -s "$WASM"

echo "=== caller-AccountId-keyed U128 map round-trip on real NEAR VM ==="
out="$(cargo run --quiet --manifest-path tools/near-vm-runner/Cargo.toml -- "$WASM" map_roundtrip)"
echo "$out"

fail() { echo "vm-caller-account-id-map: $*" >&2; exit 1; }
grep -qiE 'ABORTED|failed|LinkError' <<<"$out" && fail "real NEAR VM rejected the caller-account-id module"
grep -qF "call map_roundtrip: return_hex=$EXPECTED" <<<"$out" \
  || fail "caller-account-id round-trip did not return 16-byte LE of 100 (got: $(grep -F 'return_hex=' <<<"$out"))"
grep -qF '1 methods executed successfully on real NEAR VM' <<<"$out" \
  || fail "did not report 1 successful method"

echo "vm-caller-account-id-map: ok (raw predecessor_account_id string-keyed U128 map round-trip on real NEAR VM)"