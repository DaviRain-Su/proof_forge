#!/usr/bin/env bash
# N1.6: budget field honesty for NEAR.
#
# Offline host must report wasmtimeFuel* only (never near_gas).
# Real nearGas is only available from near-sandbox (just near-sandbox-peer).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.elan/bin:${HOME}/.local/bin:${HOME}/.cargo/bin:${PATH}"

OUT_DIR="${PROOF_FORGE_BUDGET_HONESTY_OUT:-build/near-budget-honesty}"
HOST=(cargo run --quiet --manifest-path runtime/offline-host/Cargo.toml -- run)

fail() {
  echo "budget-honesty: FAIL: $1" >&2
  exit 1
}

command -v lake >/dev/null 2>&1 || fail "lake not on PATH"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
lake build proof-forge >/dev/null

echo "=== N1.6: offline Counter fuel fields ==="
lake env proof-forge build --target wasm-near --root . -o "$OUT_DIR" \
  Examples/Product/Counter.lean \
  || fail "Counter build failed"
WAT="$(find "$OUT_DIR" -name '*.wat' | head -n1)"
test -s "$WAT" || fail "missing WAT"

out="$("${HOST[@]}" "$WAT" initialize increment get --inputs-hex ",,")"
echo "$out"

# Required: Wasmtime fuel metrics present
grep -Fq "wasmtimeFuelCumulative=" <<<"$out" || fail "missing wasmtimeFuelCumulative"
grep -Fq "wasmtimeFuelDelta=" <<<"$out" || fail "missing wasmtimeFuelDelta"

# Forbidden: legacy near_gas mislabel (PF-P0-06 / N1.6)
if grep -Eq 'near_gas=|nearGas=' <<<"$out"; then
  fail "offline-host must not print near_gas/nearGas (Wasmtime fuel is not NEAR VM gas)"
fi

# Deltas should be positive for workful calls
if ! grep -E 'wasmtimeFuelDelta=[1-9]' <<<"$out" >/dev/null; then
  fail "expected positive wasmtimeFuelDelta on at least one call"
fi

echo "offline-host budget honesty: ok (wasmtimeFuel* only)"
echo "nearGas: only from sandbox — see just near-sandbox-peer (prints nearGas=…)"
echo "budget-honesty: ok"
