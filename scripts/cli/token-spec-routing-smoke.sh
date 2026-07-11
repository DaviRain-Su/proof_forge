#!/usr/bin/env bash
# TokenSpec modules: bare build on non-NEAR targets must fail closed and point to --token.
# On wasm-near, P0-NEAR-1 auto-detection makes bare build succeed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

OUT="${PROOF_FORGE_TOKEN_SPEC_ROUTING_OUT:-build/cli/token-spec-routing}"
rm -rf "$OUT"
mkdir -p "$OUT"

fail() {
  echo "token-spec-routing: $*" >&2
  exit 1
}

lake build proof-forge >/dev/null

# --- EVM: bare TokenSpec build must fail and recommend --token ---
set +e
err="$(lake env proof-forge build --target evm --root . \
  -o "$OUT/FungibleToken.bare" Examples/Product/FungibleToken.lean 2>&1)"
status=$?
set -e

[[ "$status" -ne 0 ]] || fail "bare TokenSpec EVM build unexpectedly succeeded"
echo "$err" | grep -Fq "not ContractSpec" || \
  fail "bare TokenSpec EVM diagnostic did not identify the ContractSpec mismatch: $err"
echo "$err" | grep -Fq -- "--token" || \
  fail "bare TokenSpec EVM diagnostic did not recommend --token: $err"
[[ ! -e "$OUT/FungibleToken.bare" ]] || \
  fail "bare TokenSpec EVM build wrote an artifact despite failing"

# --- NEAR: bare TokenSpec build succeeds via P0-NEAR-1 auto-detection ---
set +e
err2="$(lake env proof-forge build --target wasm-near --root . \
  -o "$OUT/FungibleToken.near" Examples/Product/FungibleToken.lean 2>&1)"
status2=$?
set -e

if [[ "$status2" -ne 0 ]]; then
  echo "token-spec-routing: NEAR auto-detect not ready yet (expected after P0-NEAR-1): $err2" >&2
  exit 1
fi
[[ -e "$OUT/FungibleToken.near" ]] || \
  fail "NEAR TokenSpec auto-detect build did not produce an artifact"

echo "token-spec-routing: ok"