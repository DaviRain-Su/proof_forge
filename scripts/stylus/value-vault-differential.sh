#!/usr/bin/env bash
set -euo pipefail

for run in 1 2 3; do
  echo "stylus-value-vault-differential: run ${run}/3"
  lake env lean --run Tests/Stylus/ValueVaultDifferential.lean
  wat2wasm build/stylus/value-vault-differential/context.wat \
    -o build/stylus/value-vault-differential/context.wasm
  wat2wasm build/stylus/value-vault-differential/authorization.wat \
    -o build/stylus/value-vault-differential/authorization.wasm
done

cargo test --manifest-path runtime/stylus-host/Cargo.toml
RUSTUP_TOOLCHAIN=1.91.0 CARGO_TARGET_DIR=build/stylus/cargo-target \
  cargo test --manifest-path build/stylus/value-vault-differential/authorization-rust/Cargo.toml \
  --features stylus-test
