#!/usr/bin/env bash
# PF-P0-07: check fails closed for the same fixture-only source cases as build.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.elan/bin:${PATH}"

lake build proof-forge >/dev/null

fail() { echo "check-l2-parity: $*" >&2; exit 1; }

# Fixture-only targets: check and build must both reject source with same category.
for target in psy-dpn aleo-leo; do
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

# Supported primary + CosmWasm Counter MVP: check Counter succeeds (no artifact write).
for target in evm solana-sbpf-asm wasm-near wasm-cosmwasm; do
  set +e
  out="$(lake env proof-forge check --target "$target" --root . Examples/Product/Counter.lean 2>&1)"
  st=$?
  set -e
  [[ "$st" -eq 0 ]] || fail "check should pass for $target Counter: $out"
  echo "check-l2-parity: $target Counter check ok"
done

# CosmWasm product path: ValueVault fails closed on host-runtime gaps (like Soroban).
# Build and check must both fail; diagnostics share a non-success category (not silent ok).
set +e
cw_b="$(lake env proof-forge build --target wasm-cosmwasm --root . -o /tmp/pf-check-b-cw-vv \
  Examples/Product/ValueVault.lean 2>&1)"
cw_bst=$?
cw_c="$(lake env proof-forge check --target wasm-cosmwasm --root . \
  Examples/Product/ValueVault.lean 2>&1)"
cw_cst=$?
set -e
[[ "$cw_bst" -ne 0 ]] || fail "cosmwasm build should fail-closed for ValueVault"
[[ "$cw_cst" -ne 0 ]] || fail "cosmwasm check should fail-closed for ValueVault"
echo "$cw_b" | grep -Eqi 'HostRuntime|env\.block|capability|unsupported|preflight|backend' \
  || fail "cosmwasm build ValueVault missing host/capability diagnostic: $cw_b"
echo "$cw_c" | grep -Eqi 'HostRuntime|env\.block|capability|unsupported|preflight|backend' \
  || fail "cosmwasm check ValueVault missing host/capability diagnostic: $cw_c"
echo "check-l2-parity: wasm-cosmwasm ValueVault fail-closed (build+check)"

echo "check-l2-parity: ok"
