#!/usr/bin/env bash
# Aleo promotion-readiness audit. This intentionally remains non-zero while
# full portable Counter cannot preserve its getter ABI on Leo 4.0.2.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.foundry/bin:${HOME}/.elan/bin:${HOME}/.cargo/bin:${PATH}"

fail() { echo "aleo-promotion: $*" >&2; exit 1; }
ok() { echo "aleo-promotion: ok — $*"; }

command -v leo >/dev/null || fail "leo CLI not on PATH"

# Honest negative witness for full Counter.
bash scripts/aleo/counter-smoke.sh || fail "counter fail-closed witness failed"
ok "full Counter getter fails closed"

# Executable positive witness uses the supported pure fragment.
bash scripts/aleo/pure-math-smoke.sh || fail "PureMath sourcegen/build/test failed"
ok "PureMath sourcegen/build/test"

# Gate 2: product source fail-closed
set +e
err="$(lake env proof-forge build --target aleo-leo --root . \
  -o build/aleo-promotion-reject Examples/Product/Counter.lean 2>&1)"
st=$?
set -e
[[ "$st" -ne 0 ]] || fail "gate2: product Counter must fail-closed"
echo "$err" | grep -Eqi 'source input is not supported|not supported|fixture' \
  || fail "gate2: expected diagnostic, got: $err"
ok "gate2 product source fail-closed"

# Gate 6
python3 - <<'PY' || fail "gate6"
from pathlib import Path
import subprocess
assert 'id := "aleo-leo"' in Path("ProofForge/Target/Registry.lean").read_text()
assert "aleo-leo" in Path("README.md").read_text()
out = subprocess.check_output(["lake","env","proof-forge","--list-targets"], text=True)
assert "aleo-leo" in out
print("ok")
PY
ok "gate6 surface"

fail "promotion incomplete: Leo 4.0.2 cannot preserve Counter get() -> U64 across final"
