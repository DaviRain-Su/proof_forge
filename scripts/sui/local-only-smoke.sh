#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

BUILD_DIR="${1:-build/sui/counter-local-only}"

rm -rf "$BUILD_DIR"
lake env proof-forge build --target move-sui --fixture counter -o "$BUILD_DIR"

env -u SUI_FULLNODE_URL -u SUI_CLIENT_CONFIG sui move build --path "$BUILD_DIR"
env -u SUI_FULLNODE_URL -u SUI_CLIENT_CONFIG sui move test --path "$BUILD_DIR"

echo "sui-local-only: ok"
