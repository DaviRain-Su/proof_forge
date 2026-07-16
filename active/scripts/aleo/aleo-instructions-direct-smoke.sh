#!/usr/bin/env bash
# Z2.3: Counter IR → Aleo Instructions direct emit matches golden.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.elan/bin:${PATH}"
OUT="${PROOF_FORGE_ALEO_DIRECT_OUT:-build/aleo/z2-direct}"
GOLDEN="Examples/Backend/Aleo/Counter.golden.aleo"
mkdir -p "$OUT"
fail() { echo "aleo-instructions-direct: FAIL: $1" >&2; exit 1; }
note() { echo "aleo-instructions-direct: $1"; }

note "emit --format aleo"
lake env proof-forge emit --target aleo-leo --fixture counter --format aleo \
  -o "$OUT/Counter.aleo" || fail "emit failed"
[ -s "$OUT/Counter.aleo" ] || fail "empty output"
diff -u "$GOLDEN" "$OUT/Counter.aleo" || fail "direct .aleo != golden"

# Leo sourcegen still works
note "emit --format leo still available"
lake env proof-forge emit --target aleo-leo --fixture counter --format leo \
  -o "$OUT/Counter.leo" || fail "leo emit failed"
[ -s "$OUT/Counter.leo" ] || fail "empty leo"

note "ok"
echo "=== aleo-instructions-direct: PASS ==="
