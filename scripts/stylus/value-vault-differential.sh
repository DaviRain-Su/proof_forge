#!/usr/bin/env bash
set -euo pipefail

for run in 1 2 3; do
  echo "stylus-value-vault-differential: run ${run}/3"
  lake env lean --run Tests/Stylus/ValueVaultDifferential.lean
  wat2wasm build/stylus/value-vault-differential/context.wat \
    -o build/stylus/value-vault-differential/context.wasm
done

cargo test --manifest-path runtime/stylus-host/Cargo.toml
