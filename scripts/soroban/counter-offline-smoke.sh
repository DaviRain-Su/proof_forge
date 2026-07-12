#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

OUT="build/soroban/counter-offline"
WAT="$OUT/counter.wat"
HOST=(cargo run --quiet --manifest-path runtime/offline-host/Cargo.toml -- run)

mkdir -p "$OUT"

echo "=== B3: Build Counter for Soroban ==="
lake env proof-forge build --target wasm-stellar-soroban --root . \
  -o "$OUT" Examples/Product/Counter.lean > /dev/null 2>&1

if [[ ! -f "$WAT" ]]; then
  echo "soroban-counter-offline: FAIL: no WAT produced" >&2
  exit 1
fi

echo "=== Verify WAT uses Soroban host imports ==="
if ! grep -q '"_get"' "$WAT"; then
  echo "soroban-counter-offline: FAIL: WAT missing _get import" >&2
  exit 1
fi
if ! grep -q '"_put"' "$WAT"; then
  echo "soroban-counter-offline: FAIL: WAT missing _put import" >&2
  exit 1
fi
if ! grep -q '"set_return_data"' "$WAT"; then
  echo "soroban-counter-offline: FAIL: WAT missing set_return_data import" >&2
  exit 1
fi
if grep -q '"storage_read"' "$WAT"; then
  echo "soroban-counter-offline: FAIL: WAT contains NEAR storage_read" >&2
  exit 1
fi
if grep -q '"value_return"' "$WAT"; then
  echo "soroban-counter-offline: FAIL: WAT contains NEAR value_return" >&2
  exit 1
fi
echo "WAT imports: _get/_put/set_return_data (Soroban native)"

echo "=== Offline-host lifecycle: initialize -> increment x3 -> get ==="
OUT_RAW="$("${HOST[@]}" "$WAT" initialize increment increment increment get 2>&1)"
echo "$OUT_RAW"

echo "=== Verify state ==="
if ! echo "$OUT_RAW" | grep -q "return_u64=3"; then
  echo "soroban-counter-offline: FAIL: expected return_u64=3 after 3 increments" >&2
  exit 1
fi

echo "soroban-counter-offline: ok (init->increment x3->get returns 3, Soroban native imports verified)"