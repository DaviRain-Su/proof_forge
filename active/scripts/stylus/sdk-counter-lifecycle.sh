#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$ROOT/build/stylus/sdk-lifecycle/Counter"
export CARGO_TARGET_DIR="$ROOT/build/stylus/cargo-target"
export RUSTC="$(rustup which --toolchain 1.91.0 rustc)"
export RUSTDOC="$(rustup which --toolchain 1.91.0 rustdoc)"
cd "$ROOT"

rm -rf "$OUT"
lake env lean --run Tests/Stylus/GenerateCounter.lean "$OUT"
mkdir -p "$OUT/tests"
cp Tests/fixtures/stylus/counter/tests/lifecycle.rs "$OUT/tests/lifecycle.rs"
rustup run 1.91.0 cargo test --manifest-path "$OUT/Cargo.toml" --features stylus-test
echo "stylus-sdk-counter-lifecycle: ok"
