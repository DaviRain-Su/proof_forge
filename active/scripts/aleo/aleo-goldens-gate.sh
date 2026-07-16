#!/usr/bin/env bash
# Z2.1: pin/diff Counter Aleo Instructions golden.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
GOLDEN="Examples/Backend/Aleo/Counter.golden.aleo"
fail() { echo "aleo-aleo-goldens: FAIL: $1" >&2; exit 1; }
note() { echo "aleo-aleo-goldens: $1"; }

[ -f "$GOLDEN" ] || fail "missing $GOLDEN"
[ -s "$GOLDEN" ] || fail "empty golden"
grep -q 'program counter.aleo;' "$GOLDEN" || fail "missing program header"
grep -q 'finalize initialize:' "$GOLDEN" || fail "missing finalize initialize"
grep -q 'get.or_use count' "$GOLDEN" || fail "missing get.or_use"
grep -q 'constructor:' "$GOLDEN" || fail "missing constructor"

# Optional: rebuild via leo and diff when leo present
if command -v leo >/dev/null 2>&1; then
  note "leo present — rebuild golden source and diff instructions"
  PKG="build/aleo/z2-golden-check"
  rm -rf "$PKG"
  mkdir -p "$PKG/src"
  cp Examples/Backend/Aleo/Counter.golden.leo "$PKG/src/main.leo"
  printf '%s\n' '{"program":"counter.aleo","version":"0.1.0","description":"","license":"Apache-2.0"}' > "$PKG/program.json"
  (cd "$PKG" && leo build >/dev/null)
  [ -f "$PKG/build/main.aleo" ] || fail "leo build did not emit main.aleo"
  if ! diff -u "$GOLDEN" "$PKG/build/main.aleo"; then
    fail "leo rebuild drifted from Counter.golden.aleo (update golden if intentional)"
  fi
  note "leo rebuild matches golden"
else
  note "leo absent — shape-only golden check"
fi
echo "=== aleo-aleo-goldens: PASS ==="
