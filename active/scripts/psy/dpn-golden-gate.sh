#!/usr/bin/env bash
# Z1.1: pin/diff normalized DPN bytecode goldens.
#
# Prefer checked-in goldens under Examples/Backend/Psy/dpn/.
# When dargo rebuild artifacts exist under build/psy/dargo-*/, re-normalize and
# diff so drift fails closed. Without rebuild artifacts, validate golden shape only.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

GOLDEN_DIR="Examples/Backend/Psy/dpn"
fail() { echo "psy-dpn-goldens: FAIL: $1" >&2; exit 1; }
note() { echo "psy-dpn-goldens: $1"; }

command -v python3 >/dev/null 2>&1 || fail "python3 required"
[ -d "$GOLDEN_DIR" ] || fail "missing $GOLDEN_DIR"

declare -a FIXTURES=(
  "Counter:build/psy/dargo-counter/target/proof_forge_counter.json"
  "ArithmeticProbe:build/psy/dargo-arithmetic/target/proof_forge_arithmetic.json"
  "AssertProbe:build/psy/dargo-assert/target/proof_forge_assert.json"
)

checked=0
diffed=0
for entry in "${FIXTURES[@]}"; do
  name="${entry%%:*}"
  artifact="${entry#*:}"
  golden="$GOLDEN_DIR/${name}.golden.dpn.json"
  [ -f "$golden" ] || fail "missing golden $golden"
  python3 scripts/psy/normalize-dpn-json.py --check "$golden" \
    || fail "golden shape invalid: $golden"
  # Structural minimums
  python3 - "$golden" "$name" <<'PY' || fail "golden content checks failed for $name"
import json, sys
from pathlib import Path
path, name = sys.argv[1], sys.argv[2]
data = json.loads(Path(path).read_text())
assert isinstance(data, list) and data, f"{name}: empty"
for m in data:
    assert "name" in m and "method_id" in m and "definitions" in m
    assert isinstance(m["definitions"], list)
print(f"ok structure {name} methods={len(data)}")
PY
  checked=$((checked + 1))

  if [ -f "$artifact" ]; then
    note "diff rebuild artifact for $name"
    norm="$ROOT/build/psy/dpn-goldens/${name}.normalized.json"
    mkdir -p "$(dirname "$norm")"
    python3 scripts/psy/normalize-dpn-json.py "$artifact" -o "$norm"
    if ! diff -u "$golden" "$norm" >/tmp/psy-dpn-golden-diff.out; then
      cat /tmp/psy-dpn-golden-diff.out >&2
      fail "DPN golden drift for $name (rebuild vs checked-in)"
    fi
    note "match $name"
    diffed=$((diffed + 1))
  else
    note "no rebuild artifact for $name ($artifact) — golden shape-only check"
  fi
done

note "summary checked=$checked diffed=$diffed"
echo "=== psy-dpn-goldens: PASS ==="
