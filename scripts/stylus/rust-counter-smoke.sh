#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$ROOT/build/stylus/rust/Counter"
export CARGO_TARGET_DIR="$ROOT/build/stylus/cargo-target"
CARGO=(rustup run 1.91.0 cargo)
export RUSTC="$(rustup which --toolchain 1.91.0 rustc)"
export RUSTDOC="$(rustup which --toolchain 1.91.0 rustdoc)"
cd "$ROOT"

lake build proof-forge
rm -rf "$OUT"
lake env lean --run Tests/Stylus/GenerateCounter.lean "$OUT"

cmp "$OUT/Cargo.toml" Tests/fixtures/stylus/counter/Cargo.toml.golden
grep -Fxq 'stylus-sdk = "=0.10.8"' "$OUT/Cargo.toml"
scripts/stylus/check-toolchain.sh

"${CARGO[@]}" test --manifest-path "$OUT/Cargo.toml" --features stylus-test
"${CARGO[@]}" build --manifest-path "$OUT/Cargo.toml" --target wasm32-unknown-unknown --release

if "${CARGO[@]}" stylus --version >/dev/null 2>&1; then
  "${CARGO[@]}" stylus check --manifest-path "$OUT/Cargo.toml"
else
  echo "stylus-rust-counter: SKIP cargo stylus check (cargo-stylus 0.10.8 not installed)"
fi
echo "stylus-rust-counter: ok"
