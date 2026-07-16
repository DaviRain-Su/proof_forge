#!/usr/bin/env bash
# PF-P2-03 / PF-P2-02: near-sandbox real peer + initialize storage smoke.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.local/bin:${HOME}/.cargo/bin:${HOME}/.elan/bin:${PATH}"

if ! command -v near-sandbox >/dev/null 2>&1; then
  if [[ -x "${HOME}/.near/near-sandbox-2.13.0/near-sandbox" ]]; then
    export PATH="${HOME}/.local/bin:${PATH}"
    mkdir -p "${HOME}/.local/bin"
    ln -sfn "${HOME}/.near/near-sandbox-2.13.0/near-sandbox" "${HOME}/.local/bin/near-sandbox"
  else
    echo "sandbox-peer-smoke: near-sandbox not on PATH; install NEAR sandbox binary" >&2
    exit 127
  fi
fi
export NEAR_SANDBOX_BIN_PATH="${NEAR_SANDBOX_BIN_PATH:-$(command -v near-sandbox)}"

# Ensure PeerOracle.wasm exists
if [[ ! -f Examples/Backend/WasmNear/fixtures/PeerOracle.wasm ]]; then
  if ! command -v wat2wasm >/dev/null 2>&1; then
    echo "sandbox-peer-smoke: need wat2wasm to build PeerOracle.wasm" >&2
    exit 127
  fi
  wat2wasm Examples/Backend/WasmNear/fixtures/PeerOracle.wat \
    -o Examples/Backend/WasmNear/fixtures/PeerOracle.wasm
fi

# Build the smoke binary (release for faster runtime)
cargo build --release --manifest-path scripts/near/sandbox-peer-smoke/Cargo.toml
exec ./scripts/near/sandbox-peer-smoke/target/release/proof-forge-near-sandbox-peer-smoke
