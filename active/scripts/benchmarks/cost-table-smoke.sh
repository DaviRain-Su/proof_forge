#!/usr/bin/env bash
# B1.6: render Counter cost/artifact markdown from existing matrix rows.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

DIR="${PROOF_FORGE_BENCH_OUT:-build/benchmarks}"
OUT="${PROOF_FORGE_BENCH_TABLE:-docs/generated/benchmark-counter.md}"

fail() { echo "benchmark-cost-table: FAIL: $1" >&2; exit 1; }

if ! ls "$DIR"/bm-counter_*.json >/dev/null 2>&1; then
  echo "benchmark-cost-table: missing rows — running just benchmark-counter"
  just benchmark-counter || fail "benchmark-counter failed"
fi

python3 scripts/benchmarks/render-cost-table.py --dir "$DIR" -o "$OUT" \
  || fail "render failed"
[ -s "$OUT" ] || fail "empty $OUT"
grep -q 'bm-counter' "$OUT" || fail "table missing bm-counter section"
# Expanded scenarios (B1.7+) are optional in the snapshot when runners have been executed.
if ls "$DIR"/bm-value-vault_*.json >/dev/null 2>&1; then
  grep -q 'bm-value-vault' "$OUT" || fail "table missing bm-value-vault section"
fi
if ls "$DIR"/bm-ownable_*.json >/dev/null 2>&1; then
  grep -q 'bm-ownable' "$OUT" || fail "table missing bm-ownable section"
fi
grep -q 'No cross-chain score' "$OUT" || fail "missing non-goal rule"

echo "=== benchmark-cost-table: PASS ($OUT) ==="
