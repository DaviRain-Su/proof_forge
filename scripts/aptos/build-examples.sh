#!/usr/bin/env bash
# Build and diff tracked Aptos Move example artifacts.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="${REPO_ROOT}/build/aptos/examples"
EXAMPLE="Counter"

cd "$REPO_ROOT"

echo "=== Aptos ${EXAMPLE} IR -> Move ==="
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
lake build proof-forge
lake env proof-forge emit --target move-aptos --fixture counter --format aptos -o "$BUILD_DIR"

for f in Move.toml sources/counter.move tests/counter_tests.move; do
  if ! diff -u "Examples/Aptos/${EXAMPLE}/golden/$(basename "$f")" "$BUILD_DIR/$f"; then
    echo "  ${EXAMPLE}: ${f} differs from golden"
    exit 1
  fi
done

echo "  ${EXAMPLE}: matches golden"
echo ""

echo "=== Aptos examples: ALL PASS ==="
