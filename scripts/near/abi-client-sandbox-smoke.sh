#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${NEAR_ABI_CLIENT_OUT:-$ROOT/build/near-abi-client}"

if [[ -z "${NEAR_SANDBOX_BIN_PATH:-}" ]]; then
  if command -v near-sandbox >/dev/null 2>&1; then
    export NEAR_SANDBOX_BIN_PATH="$(command -v near-sandbox)"
  elif [[ -x "$HOME/.local/bin/near-sandbox" ]]; then
    export NEAR_SANDBOX_BIN_PATH="$HOME/.local/bin/near-sandbox"
  else
    echo "near-abi-client-sandbox: near-sandbox is required" >&2
    exit 1
  fi
fi
[[ -x "$NEAR_SANDBOX_BIN_PATH" ]] || {
  echo "near-abi-client-sandbox: invalid NEAR_SANDBOX_BIN_PATH" >&2
  exit 1
}

command -v wat2wasm >/dev/null 2>&1 || {
  echo "near-abi-client-sandbox: wat2wasm is required" >&2
  exit 1
}
"$ROOT/scripts/near/abi-client-smoke.sh"
lake env lean --run Tests/NearAbiSandboxFixture.lean "$OUT/echo.wat"
wat2wasm "$OUT/echo.wat" -o "$OUT/echo.wasm"

cargo run --quiet \
  --manifest-path "$ROOT/scripts/near/sandbox-peer-smoke/Cargo.toml" \
  --bin abi_client
