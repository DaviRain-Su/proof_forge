#!/usr/bin/env bash
# TokenSpec modules must fail closed on the ContractSpec route and point to --token.
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

set +e
err="$(lake env proof-forge build --target wasm-near --root . \
  -o "$OUT/FungibleToken.bare" Examples/Product/FungibleToken.lean 2>&1)"
status=$?
set -e

[[ "$status" -ne 0 ]] || fail "bare TokenSpec build unexpectedly succeeded"
echo "$err" | grep -Fq "not ContractSpec" || \
  fail "bare TokenSpec diagnostic did not identify the ContractSpec mismatch: $err"
echo "$err" | grep -Fq -- "--token" || \
  fail "bare TokenSpec diagnostic did not recommend --token: $err"
[[ ! -e "$OUT/FungibleToken.bare" ]] || \
  fail "bare TokenSpec build wrote an artifact despite failing"

echo "token-spec-routing: ok"
