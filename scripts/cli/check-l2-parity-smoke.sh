#!/usr/bin/env bash
# PF-P0-07: check fails closed for the same fixture-only source cases as build.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.elan/bin:${PATH}"

lake build proof-forge >/dev/null

fail() { echo "check-l2-parity: $*" >&2; exit 1; }

# Fixture-only targets: check and build must both reject source with same category.
for target in wasm-cosmwasm psy-dpn aleo-leo move-aptos move-sui wasm-cloudflare-workers; do
  set +e
  berr="$(lake env proof-forge build --target "$target" --root . -o "/tmp/pf-check-b-$target" \
    Examples/Product/ValueVault.lean 2>&1)"
  bst=$?
  cerr="$(lake env proof-forge check --target "$target" --root . \
    Examples/Product/ValueVault.lean 2>&1)"
  cst=$?
  set -e
  [[ "$bst" -ne 0 ]] || fail "build should fail for $target source"
  [[ "$cst" -ne 0 ]] || fail "check should fail for $target source"
  echo "$berr" | grep -Fq "source input is not supported" || fail "build missing phrase for $target: $berr"
  echo "$cerr" | grep -Fq "source input is not supported" || fail "check missing phrase for $target: $cerr"
  echo "check-l2-parity: $target build/check reject source"
done

# Supported primary: check Counter succeeds (no artifact write required).
for target in evm solana-sbpf-asm wasm-near; do
  set +e
  out="$(lake env proof-forge check --target "$target" --root . Examples/Product/Counter.lean 2>&1)"
  st=$?
  set -e
  [[ "$st" -eq 0 ]] || fail "check should pass for $target Counter: $out"
  echo "check-l2-parity: $target Counter check ok"
done

echo "check-l2-parity: ok"
