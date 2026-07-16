#!/usr/bin/env bash
set -euo pipefail

# Validate that unsupported or malformed wasm-near IR shapes fail before Rust
# source generation with stable, explicit diagnostics, and that valid modules
# render near-sdk-rs source.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cd "$ROOT"
lake build proof-forge >/dev/null
lake env lean --run Tests/Backend/Wasm/WasmNearDiagnostics.lean
