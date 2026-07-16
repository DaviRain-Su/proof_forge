#!/usr/bin/env bash
# B1.1: validate benchmark result schema fixtures.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

VALIDATOR=scripts/benchmarks/validate-result-schema.py
FIXTURES=benchmarks/schema/fixtures

fail() { echo "benchmark-schema-smoke: FAIL: $1" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || fail "python3 not on PATH"
[ -f "$VALIDATOR" ] || fail "missing $VALIDATOR"
[ -d "$FIXTURES" ] || fail "missing $FIXTURES"

echo "=== benchmark schema: accept valid fixtures ==="
python3 "$VALIDATOR" \
  "$FIXTURES/valid-counter-evm-proofforge.json" \
  "$FIXTURES/valid-counter-solana-native.json" \
  "$FIXTURES/valid-skip-near.json" \
  || fail "valid fixtures rejected"

echo "=== benchmark schema: reject invalid cost key ==="
if python3 "$VALIDATOR" "$FIXTURES/invalid-bad-cost-key.json" >/tmp/benchmark-schema-invalid.out 2>/tmp/benchmark-schema-invalid.err; then
  fail "invalid fixture accepted"
fi
grep -q "not allowed for target" /tmp/benchmark-schema-invalid.err \
  || fail "expected cost-key diagnostic; got: $(cat /tmp/benchmark-schema-invalid.err)"

echo "=== benchmark-schema-smoke: PASS ==="
