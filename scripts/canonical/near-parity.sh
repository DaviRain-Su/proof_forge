#!/usr/bin/env bash
set -euo pipefail

# NEAR canonical parity script: runs both legacy and canonical pipelines
# for the Counter and ValueVault fixtures.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_BASE="$ROOT/build/canonical/near"
mkdir -p "$OUT_BASE"

FIXTURES="counter value-vault"

for fixture in $FIXTURES; do
  echo "=== Emitting legacy $fixture ==="
  lake env lean --run Tests/Canonical/Emit.lean -- \
    --pipeline legacy --target wasm-near --fixture "$fixture" \
    --out "$OUT_BASE/legacy-$fixture"

  echo "=== Emitting canonical $fixture ==="
  lake env lean --run Tests/Canonical/Emit.lean -- \
    --pipeline canonical --target wasm-near --fixture "$fixture" \
    --out "$OUT_BASE/core-$fixture"
done

# Compile both WAT paths with wat2wasm when available.
if command -v wat2wasm &> /dev/null; then
  for fixture in $FIXTURES; do
    for pipeline in legacy core; do
      WAT_FILE="$OUT_BASE/$pipeline-$fixture/contract.wat"
      test -s "$WAT_FILE"
      echo "=== Compiling $pipeline $fixture WAT ==="
      wat2wasm "$WAT_FILE" -o "$OUT_BASE/$pipeline-$fixture/contract.wasm"
      test -s "$OUT_BASE/$pipeline-$fixture/contract.wasm"
    done
  done
else
  echo "SKIP: wat2wasm not installed; WAT files were emitted"
fi

HOST=(cargo run --quiet --manifest-path runtime/offline-host/Cargo.toml -- run)

observable_trace() {
  grep -E '^(call |  log:)' | sed -E 's/ heap_next=.*$//'
}

echo "=== Running Counter offline-host parity ==="
legacy_counter="$(${HOST[@]} "$OUT_BASE/legacy-counter/contract.wasm" initialize get increment get)"
core_counter="$(${HOST[@]} "$OUT_BASE/core-counter/contract.wasm" initialize get increment get)"
test "$(printf '%s\n' "$legacy_counter" | observable_trace)" = \
  "$(printf '%s\n' "$core_counter" | observable_trace)"

echo "=== Running ValueVault offline-host parity ==="
VAULT_CALLS=(initialize deposit charge_fee release snapshot get_balance get_net_value)
VAULT_INPUTS="6400000000000000,1900000000000000,0a00000000000000f401000000000000,0500000000000000,,,"
legacy_vault="$(${HOST[@]} "$OUT_BASE/legacy-value-vault/contract.wasm" "${VAULT_CALLS[@]}" --inputs-hex "$VAULT_INPUTS" --block-index 77)"
core_vault="$(${HOST[@]} "$OUT_BASE/core-value-vault/contract.wasm" "${VAULT_CALLS[@]}" --inputs-hex "$VAULT_INPUTS" --block-index 77)"
test "$(printf '%s\n' "$legacy_vault" | observable_trace)" = \
  "$(printf '%s\n' "$core_vault" | observable_trace)"

echo "=== Running ValueVault revert parity ==="
set +e
${HOST[@]} "$OUT_BASE/legacy-value-vault/contract.wasm" initialize release \
  --inputs-hex "6400000000000000,c800000000000000" >/dev/null 2>&1
legacy_rc=$?
${HOST[@]} "$OUT_BASE/core-value-vault/contract.wasm" initialize release \
  --inputs-hex "6400000000000000,c800000000000000" >/dev/null 2>&1
core_rc=$?
set -e
test "$legacy_rc" -eq 0
test "$core_rc" -ne 0
echo "canonical checked arithmetic rejects the legacy NEAR wrapping-underflow gap"

echo "=== NEAR canonical parity check complete ==="
