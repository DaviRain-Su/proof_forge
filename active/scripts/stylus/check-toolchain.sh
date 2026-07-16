#!/usr/bin/env bash
set -euo pipefail

RUST_PIN="1.91.0"
STYLUS_PIN="0.10.8"
strict="${PROOF_FORGE_STYLUS_STRICT:-0}"

rust_version="$(rustup run "$RUST_PIN" rustc --version 2>/dev/null | awk '{print $2}')"
if [[ "$rust_version" != "$RUST_PIN" ]]; then
  if [[ "$strict" == "1" ]]; then
    echo "stylus-toolchain: expected rustc $RUST_PIN, found $rust_version" >&2
    exit 1
  fi
  echo "stylus-toolchain: WARN expected rustc $RUST_PIN, found $rust_version"
fi

rustup target list --installed --toolchain "$RUST_PIN" | grep -Fxq wasm32-unknown-unknown || {
  echo "stylus-toolchain: missing wasm32-unknown-unknown" >&2
  exit 1
}

if rustup run "$RUST_PIN" cargo stylus --version >/dev/null 2>&1; then
  stylus_version="$(rustup run "$RUST_PIN" cargo stylus --version | awk '{print $2}')"
  [[ "$stylus_version" == "$STYLUS_PIN" ]] || {
    echo "stylus-toolchain: expected cargo-stylus $STYLUS_PIN, found $stylus_version" >&2
    exit 1
  }
  echo "stylus-toolchain: cargo-stylus $stylus_version"
else
  if [[ "$strict" == "1" ]]; then
    echo "stylus-toolchain: cargo-stylus $STYLUS_PIN is required" >&2
    exit 1
  fi
  echo "stylus-toolchain: SKIP cargo-stylus $STYLUS_PIN is not installed"
fi
