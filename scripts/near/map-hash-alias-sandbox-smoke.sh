#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$ROOT/build/near-map-hash-alias"

if [[ -z "${NEAR_SANDBOX_BIN_PATH:-}" ]]; then
  if command -v near-sandbox >/dev/null 2>&1; then
    export NEAR_SANDBOX_BIN_PATH="$(command -v near-sandbox)"
  elif [[ -x "$HOME/.local/bin/near-sandbox" ]]; then
    export NEAR_SANDBOX_BIN_PATH="$HOME/.local/bin/near-sandbox"
  else
    echo "near-map-hash-alias-sandbox: near-sandbox is required" >&2
    exit 1
  fi
fi
[[ -x "$NEAR_SANDBOX_BIN_PATH" ]] || {
  echo "near-map-hash-alias-sandbox: invalid NEAR_SANDBOX_BIN_PATH" >&2
  exit 1
}

rm -rf "$OUT"
mkdir -p "$OUT"
lake build ProofForge.Backend.WasmHost.EmitWat >/dev/null
lake env lean --run Tests/NearMapHashAlias.lean "$OUT/alias.wat" >/dev/null
wat2wasm "$OUT/alias.wat" -o "$OUT/alias.wasm"

cargo run --quiet \
  --manifest-path "$ROOT/scripts/near/sandbox-peer-smoke/Cargo.toml" \
  --bin map_hash_alias
