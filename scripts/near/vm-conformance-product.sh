#!/usr/bin/env bash
# Real-NEAR-VM conformance smoke for the *product author source*.
#
# Sibling of vm-conformance-smoke.sh. That gate emits the IR fixture via the
# internal Emit.lean harness (legacy + canonical). This gate closes the real
# product loop:
#
#   Examples/Product/Counter.lean  (contract_source DSL — the authoring surface)
#     -> public CLI: `proof-forge build --target wasm-near`
#     -> EmitWat -> counter.wat -> wat2wasm -> counter.wasm
#     -> *unmodified upstream* NEAR VM (near-vm-runner / Wasmtime)
#
# After initialize + increment*2 the counter must read 2 (little-endian u64
# 0x02 -> return_hex 0200000000000000). Proving the product source — not just
# the minimal IR fixture — produces NEAR-VM-executable Wasm.
#
# WAT parity between this product output and the IR-fixture golden is already
# asserted by `scripts/portable/counter-multi-target.sh`; this gate focuses on
# real-VM execution from the product source.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "vm-conformance-product: missing required tool '$1'" >&2
    exit 1
  }
}
require_cmd wat2wasm
require_cmd cargo

# Allow callers (e.g. downstream wrappers) to substitute a prebuilt binary.
if [[ -n "${PROOF_FORGE_BIN:-}" ]]; then
  proof_forge=("$PROOF_FORGE_BIN")
else
  proof_forge=(lake env proof-forge)
fi

SOURCE="${PORTABLE_COUNTER_SOURCE:-Examples/Product/Counter.lean}"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/pf-near-vmconf-product.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

echo "=== building proof-forge ==="
(cd "$ROOT" && lake build proof-forge >/dev/null)

echo "=== compiling product source via public CLI (wasm-near) ==="
"${proof_forge[@]}" build --target wasm-near --root . \
  -o "$TMP/near" \
  --artifact-output "$TMP/Counter.near-artifact.json" \
  "$SOURCE"
# The CLI's writeWatPackage runs wat2wasm internally and fails hard if it is
# missing (PF-P0-08), so counter.wasm IS the real deploy artifact — run that
# directly rather than re-assembling the WAT ourselves.
test -s "$TMP/near/counter.wasm"

# Run the product-source Counter on the real NEAR VM and assert the trace.
# Expects get == 2 (return_hex 0200000000000000) with no abort or failure.
echo "=== executing product counter on real NEAR VM ==="
out="$(cargo run --quiet --manifest-path tools/near-vm-runner/Cargo.toml -- \
  "$TMP/near/counter.wasm" initialize increment increment get)"

if grep -qiE 'ABORTED|failed' <<<"$out"; then
  echo "vm-conformance-product: product Counter aborted on real NEAR VM:" >&2
  echo "$out" >&2
  exit 1
fi

get_line="$(grep -F 'call get:' <<<"$out")"
if [[ -z "$get_line" ]]; then
  echo "vm-conformance-product: produced no get trace" >&2
  echo "$out" >&2
  exit 1
fi
if ! grep -qF 'return_hex=0200000000000000' <<<"$get_line"; then
  echo "vm-conformance-product: get did not return 2 (LE u64): $get_line" >&2
  echo "$out" >&2
  exit 1
fi
if ! grep -qF '4 methods executed successfully on real NEAR VM' <<<"$out"; then
  echo "vm-conformance-product: did not report 4 successful methods" >&2
  echo "$out" >&2
  exit 1
fi

echo "vm-conformance-product: ok (product Counter from CLI executes on real NEAR VM; get=2, $(awk -F'gas=' '/call get:/{print $2}' <<<"$out" | head -1) gas for get)"
