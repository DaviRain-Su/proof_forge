#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$ROOT/build/near-map-hash-alias"

rm -rf "$OUT"
mkdir -p "$OUT"
lake build ProofForge.Backend.WasmHost.EmitWat >/dev/null
lake env lean --run Tests/NearMapHashAlias.lean "$OUT/alias.wat" >/dev/null
wat2wasm "$OUT/alias.wat" -o "$OUT/alias.wasm"

cargo run --quiet \
  --manifest-path "$ROOT/scripts/near/sandbox-peer-smoke/Cargo.toml" \
  --bin map_hash_alias
