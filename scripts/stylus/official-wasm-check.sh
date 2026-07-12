#!/usr/bin/env bash
set -euo pipefail

wasm="${1:-build/stylus/counter-differential/counter.wasm}"
toolchain="${PROOF_FORGE_STYLUS_RUST:-1.91.0}"

if ! rustup run "$toolchain" cargo stylus --version >/dev/null 2>&1; then
  echo "stylus-official-check: SKIP cargo-stylus is not installed for Rust $toolchain"
  exit 0
fi

args=(stylus check "--wasm-file=$wasm")
if [[ -n "${PROOF_FORGE_STYLUS_ENDPOINT:-}" ]]; then
  args+=("--endpoint=$PROOF_FORGE_STYLUS_ENDPOINT")
fi

rustup run "$toolchain" cargo "${args[@]}"
