#!/usr/bin/env bash
# B1.5 smoke: run behavior gate on existing Counter matrix rows.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

DIR="${PROOF_FORGE_BENCH_OUT:-build/benchmarks}"
fail() { echo "benchmark-behavior-gate-smoke: FAIL: $1" >&2; exit 1; }

if ! ls "$DIR"/bm-counter_*_proofforge.json >/dev/null 2>&1 \
  || ! ls "$DIR"/bm-counter_*_native.json >/dev/null 2>&1; then
  echo "benchmark-behavior-gate-smoke: missing rows — running just benchmark-counter"
  just benchmark-counter || fail "benchmark-counter failed"
fi

# Compare all bm-* scenarios present (counter, value-vault, ownable, …).
python3 scripts/benchmarks/behavior-gate.py --dir "$DIR" \
  || fail "behavior gate failed"

echo "=== benchmark-behavior-gate-smoke: PASS ==="
