#!/usr/bin/env bash
set -euo pipefail

for run in 1 2 3; do
  echo "stylus-counter-differential: run ${run}/3"
  lake env lean --run Tests/Stylus/CounterDifferential.lean
  wat2wasm build/stylus/counter-differential/counter.wat \
    -o build/stylus/counter-differential/counter.wasm
done

cargo test --manifest-path runtime/stylus-host/Cargo.toml
