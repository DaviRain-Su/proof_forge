#!/usr/bin/env bash
# Real-NEAR-VM conformance smoke for the ProofForge wasm-near target.
#
# Emits the Counter fixture through the legacy and canonical pipelines,
# compiles each WAT to Wasm, and executes both on the *unmodified upstream*
# NEAR VM (near-vm-runner, Wasmtime backend). This proves ProofForge's EmitWat
# output is accepted, linked, and executed by the real NEAR Protocol VM — not
# only by ProofForge's own offline host.
#
# Counter is the conformance fixture because it needs no Borsh constructor
# input: `initialize` zero-initializes, `increment` mutates persistent storage
# (exercising real storage-eviction accounting), and `get` returns the value.
# After initialize + increment*2 the counter must read 2 (little-endian u64
# 0x02 → return_hex 0200000000000000).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "vm-conformance-smoke: missing required tool '$1'" >&2
    exit 1
  }
}
require_cmd wat2wasm
require_cmd cargo

TMP="$(mktemp -d "${TMPDIR:-/tmp}/pf-near-vmconf.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

emit_counter() {
  local pipeline="$1" out_dir="$2"
  lake env lean --run Tests/Canonical/Emit.lean -- \
    --pipeline "$pipeline" --target wasm-near --fixture counter \
    --out "$out_dir" >/dev/null
  test -s "$out_dir/contract.wat"
  wat2wasm "$out_dir/contract.wat" -o "$out_dir/contract.wasm"
  test -s "$out_dir/contract.wasm"
}

# Run the Counter on the real NEAR VM and assert the observable trace.
# Expects get == 2 (return_hex 0200000000000000) with no abort or failure.
assert_counter_confirms() {
  local label="$1" wasm="$2"
  local out
  out="$(cargo run --quiet --manifest-path tools/near-vm-runner/Cargo.toml -- \
    "$wasm" initialize increment increment get)"

  if grep -qiE 'ABORTED|failed' <<<"$out"; then
    echo "vm-conformance-smoke: $label aborted on real NEAR VM:" >&2
    echo "$out" >&2
    exit 1
  fi

  local get_line
  get_line="$(grep -F 'call get:' <<<"$out")"
  if [[ -z "$get_line" ]]; then
    echo "vm-conformance-smoke: $label produced no get trace" >&2
    echo "$out" >&2
    exit 1
  fi
  if ! grep -qF 'return_hex=0200000000000000' <<<"$get_line"; then
    echo "vm-conformance-smoke: $label get did not return 2 (LE u64): $get_line" >&2
    exit 1
  fi
  if ! grep -qF '4 methods executed successfully on real NEAR VM' <<<"$out"; then
    echo "vm-conformance-smoke: $label did not report 4 successful methods" >&2
    exit 1
  fi
  echo "vm-conformance-smoke: $label ok ($(awk -F'gas=' '/call get:/{print $2}' <<<"$out" | head -1) gas for get)"
}

echo "=== emitting + compiling legacy counter ==="
emit_counter legacy "$TMP/legacy-counter"
echo "=== emitting + compiling canonical counter ==="
emit_counter canonical "$TMP/core-counter"

assert_counter_confirms "legacy-counter" "$TMP/legacy-counter/contract.wasm"
assert_counter_confirms "core-counter" "$TMP/core-counter/contract.wasm"

echo "vm-conformance-smoke: ok (legacy + canonical Counter execute on real NEAR VM)"
