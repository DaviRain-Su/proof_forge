#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$ROOT/build/near-ft-security"

if [[ -z "${NEAR_SANDBOX_BIN_PATH:-}" ]]; then
  if command -v near-sandbox >/dev/null 2>&1; then
    export NEAR_SANDBOX_BIN_PATH="$(command -v near-sandbox)"
  elif [[ -x "$HOME/.local/bin/near-sandbox" ]]; then
    export NEAR_SANDBOX_BIN_PATH="$HOME/.local/bin/near-sandbox"
  else
    echo "near-ft-security-sandbox: near-sandbox is required" >&2
    exit 1
  fi
fi
[[ -x "$NEAR_SANDBOX_BIN_PATH" ]] || {
  echo "near-ft-security-sandbox: invalid NEAR_SANDBOX_BIN_PATH" >&2
  exit 1
}

rm -rf "$OUT"
lake build proof-forge ProofForge.Contract.Stdlib.NearFungibleToken >/dev/null
lake env proof-forge build --target wasm-near --root . -o "$OUT" \
  Examples/Backend/WasmNear/FungibleToken.lean >/dev/null
test -s "$OUT/nearfungibletoken.wasm"

cargo run --quiet \
  --manifest-path "$ROOT/scripts/near/sandbox-peer-smoke/Cargo.toml" \
  --bin ft_security
