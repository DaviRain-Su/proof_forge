#!/usr/bin/env bash
# Z1.4: Counter IR → DPN JSON direct emit matches checked-in golden.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.elan/bin:${PATH}"

OUT="${PROOF_FORGE_PSY_DPN_DIRECT_OUT:-build/psy/dpn-direct}"
mkdir -p "$OUT"
GOLDEN="Examples/Backend/Psy/dpn/Counter.golden.dpn.json"

fail() { echo "psy-dpn-direct: FAIL: $1" >&2; exit 1; }
note() { echo "psy-dpn-direct: $1"; }

[ -f "$GOLDEN" ] || fail "missing golden $GOLDEN"

note "emit --target psy-dpn --fixture counter --format dpn-json"
lake env proof-forge emit --target psy-dpn --fixture counter --format dpn-json \
  -o "$OUT/Counter.dpn.json" \
  || fail "emit dpn-json failed"
[ -s "$OUT/Counter.dpn.json" ] || fail "empty output"

python3 scripts/psy/normalize-dpn-json.py "$OUT/Counter.dpn.json" -o "$OUT/Counter.normalized.json"
if ! diff -u "$GOLDEN" "$OUT/Counter.normalized.json"; then
  fail "direct DPN JSON does not match Counter.golden.dpn.json"
fi

# Also ensure .psy path still works (sourcegen remains available)
note "emit .psy still available"
lake env proof-forge emit --target psy-dpn --fixture counter --format psy \
  -o "$OUT/Counter.psy" || fail "emit .psy failed"
[ -s "$OUT/Counter.psy" ] || fail "empty .psy"

note "ok (Counter DPN direct emit == golden; .psy sourcegen retained)"
echo "=== psy-dpn-direct: PASS ==="
