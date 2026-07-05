#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

BUILD_DIR="${1:-build/sui/counter}"

rm -rf "$BUILD_DIR"
lake env proof-forge emit --target move-sui --fixture counter --format sui -o "$BUILD_DIR"

for file in \
  Move.toml \
  sources/counter.move \
  tests/counter_tests.move \
  proof-forge-sdk.json \
  proof-forge-client.ts \
  proof-forge-artifact.json
do
  test -f "$BUILD_DIR/$file"
done

grep -E 'name = "counter"|proof_forge|Sui' "$BUILD_DIR/Move.toml" >/dev/null
! grep -q AptosFramework "$BUILD_DIR/Move.toml"
grep -E 'module proof_forge::counter|struct Counter has key|id: UID|TxContext|increment|value|get' \
  "$BUILD_DIR/sources/counter.move" >/dev/null
grep -E '#\[test\]|test_scenario|initialize|increment|assert!|value|get' \
  "$BUILD_DIR/tests/counter_tests.move" >/dev/null

echo "sui-build-examples: ok"
