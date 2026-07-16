#!/usr/bin/env bash
# PF-P3-02: six-gate promotion smoke for psy-dpn (Counter fixture fragment).
# Full dargo execute is optional when dargo is absent (honest experimental).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.foundry/bin:${HOME}/.elan/bin:${HOME}/.cargo/bin:${PATH}"

OUT="${PROOF_FORGE_PSY_PROMOTION_OUT:-build/psy-promotion}"
rm -rf "$OUT"
mkdir -p "$OUT"

fail() { echo "psy-promotion: $*" >&2; exit 1; }
ok() { echo "psy-promotion: ok — $*"; }

lake build proof-forge >/dev/null

# Gate 1: fixture emit
lake env proof-forge emit --target psy-dpn --fixture counter -o "$OUT/counter.psy" \
  || fail "gate1: emit fixture counter failed"
[[ -s "$OUT/counter.psy" ]] || fail "gate1: empty .psy"
ok "gate1 fixture counter .psy"

# Gate 2: product fail-closed
set +e
err="$(lake env proof-forge build --target psy-dpn --root . \
  -o "$OUT/reject" Examples/Product/Counter.lean 2>&1)"
st=$?
set -e
[[ "$st" -ne 0 ]] || fail "gate2: product Counter must fail-closed"
echo "$err" | grep -Eqi 'source input is not supported|not supported|fixture' \
  || fail "gate2: expected diagnostic"
ok "gate2 product source fail-closed"

# Gate 3: IR package structure (psy source non-empty + diagnostics)
just psy-diagnostics >/dev/null || fail "gate3: psy-diagnostics failed"
ok "gate3 psy diagnostics + package"

# Gate 4: toolchain — dargo if present, else document honest skip of final stage
if command -v dargo >/dev/null 2>&1; then
  just psy-smoke counter || fail "gate4/5: psy-smoke counter failed"
  ok "gate4/5 dargo psy-smoke counter"
else
  ok "gate4/5 dargo absent — final execute deferred (experimental honesty)"
fi

# Gate 6
python3 - <<'PY' || fail "gate6"
from pathlib import Path
import subprocess
assert 'id := "psy-dpn"' in Path("ProofForge/Target/Registry.lean").read_text()
assert "psy-dpn" in Path("README.md").read_text()
out = subprocess.check_output(["lake","env","proof-forge","--list-targets"], text=True)
assert "psy-dpn" in out
print("ok")
PY
ok "gate6 surface"

echo "psy-promotion: ok (Counter fixture six-gate; dargo optional)"
