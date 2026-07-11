#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${NEAR_ABI_CLIENT_OUT:-$ROOT/build/near-abi-client}"

command -v wat2wasm >/dev/null 2>&1 || {
  echo "near-abi-client-sandbox: wat2wasm is required" >&2
  exit 1
}
command -v near-sandbox >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/near-sandbox" ]] || {
  echo "near-abi-client-sandbox: near-sandbox is required" >&2
  exit 1
}

"$ROOT/scripts/near/abi-client-smoke.sh"
lake env lean --run Tests/NearAbiSandboxFixture.lean "$OUT/echo.wat"
wat2wasm "$OUT/echo.wat" -o "$OUT/echo.wasm"

cargo run --quiet \
  --manifest-path "$ROOT/scripts/near/sandbox-peer-smoke/Cargo.toml" \
  --bin abi_client
