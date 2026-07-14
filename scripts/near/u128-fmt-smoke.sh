#!/usr/bin/env bash
# U128 decimal formatter smoke for the ProofForge wasm-near backend.
#
# Renders the U128FmtProbe IR fixture (emits a JSON event with two u128 fields:
# `simple` = 100, `big` = 18446744073709551615*2 = 36893488147419103230, the
# latter exercising the high word of the divmod10) through EmitWat, and runs it
# in runtime/offline-host, capturing the event log. Asserts both decimals
# appear verbatim — proving `__pf_fmt_u128` / `__pf_u128_divmod10` (the JSON
# U128 primitive shared by events, crosscall args, and Phase 4 view returns).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "u128-fmt-smoke: missing '$1'" >&2; exit 1; }; }
require_cmd cargo
require_cmd wat2wasm
require_cmd lake

OUT_DIR="build/wasm-near"
WAT="$OUT_DIR/emitwat-u128-fmt.wat"
WASM="$OUT_DIR/emitwat-u128-fmt.wasm"

echo "=== building + rendering U128FmtProbe ==="
lake build ProofForge.Backend.WasmHost.EmitWat ProofForge.IR.Examples.U128FmtProbe >/dev/null
lake env lean --run Tests/Backend/Wasm/EmitWatU128Fmt.lean >/dev/null
test -s "$WAT"
wat2wasm "$WAT" -o "$WASM"
test -s "$WASM"

echo "=== U128 decimal format via offline-host event log ==="
out="$(cargo run --quiet --manifest-path runtime/offline-host/Cargo.toml -- run "$WASM" emitFmt)"
echo "$out"

fail() { echo "u128-fmt-smoke: $*" >&2; exit 1; }
grep -qF '"simple":100' <<<"$out" || fail "u128 100 did not format as '100'"
grep -qF '"big":36893488147419103230' <<<"$out" \
  || fail "u128 high-word value did not format as '36893488147419103230'"

echo "u128-fmt-smoke: ok (U128 decimal formatter handles lo-word and high-word values)"
