#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

BUILD_DIR="${1:-build/sui/counter}"

if [[ ! -f "$BUILD_DIR/Move.toml" ]]; then
  rm -rf "$BUILD_DIR"
  lake env proof-forge build --target move-sui --fixture counter -o "$BUILD_DIR"
fi

sui move build --path "$BUILD_DIR"
sui move test --path "$BUILD_DIR"

echo "sui-counter-smoke: ok"
