#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$ROOT/build/near-ft-security"

rm -rf "$OUT"
lake build proof-forge ProofForge.Contract.Stdlib.NearFungibleToken >/dev/null
lake env proof-forge build --target wasm-near --root . -o "$OUT" \
  Examples/Backend/WasmNear/FungibleToken.lean >/dev/null
test -s "$OUT/nearfungibletoken.wasm"

cargo run --quiet \
  --manifest-path "$ROOT/scripts/near/sandbox-peer-smoke/Cargo.toml" \
  --bin ft_security
