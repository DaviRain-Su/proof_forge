#!/usr/bin/env bash
# E1.4: EVM upgrade-policy honesty on the product build path.
#
# - The backend-only UUPS proxy transport must build without claiming a product policy.
# - authority + UUPS must fail closed until keyRef is enforced by runtime.
# - governance must fail closed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.elan/bin:${HOME}/.foundry/bin:${HOME}/.local/bin:${PATH}"

OUT_DIR="${PROOF_FORGE_UPGRADE_HONESTY_OUT:-build/evm-upgrade-policy-honesty}"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

fail() {
  echo "upgrade-policy-honesty: FAIL: $1" >&2
  exit 1
}

command -v lake >/dev/null 2>&1 || fail "lake not on PATH"
lake build proof-forge >/dev/null

echo "=== E1.4: backend-only UUPS proxy transport ==="
lake env proof-forge build --target evm --root . \
  --evm-constructor-arg "implementation=0x0000000000000000000000000000000000001001" \
  --evm-constructor-arg "admin=0x1234567890123456789012345678901234567890" \
  --yul-output "$OUT_DIR/UUPSProxy.yul" \
  -o "$OUT_DIR/UUPSProxy.bin" \
  Examples/Backend/Evm/Contracts/stdlib/UUPSProxy.lean \
  || fail "UUPSProxy build failed"

test -s "$OUT_DIR/UUPSProxy.bin" || fail "missing UUPSProxy.bin"
# Contract-spec must not claim an authority policy that runtime does not enforce.
SPEC="$(find "$OUT_DIR" -name '*contract-spec.json' | head -n1)"
test -s "$SPEC" || fail "missing contract-spec"
python3 - "$SPEC" <<'PY' || fail "UUPSProxy contract-spec upgrade fields"
import json, sys
from pathlib import Path
spec = json.loads(Path(sys.argv[1]).read_text())
up = spec.get("upgradePolicy")
px = spec.get("proxyPattern") or {}
if up is not None:
    raise SystemExit(f"upgradePolicy expected null for backend-only spike, got {up!r}")
if px.get("kind") != "uups":
    raise SystemExit(f"proxyPattern.kind expected uups, got {px!r}")
if spec.get("entrypoints"):
    raise SystemExit(f"UUPS proxy runtime must expose no initializer entrypoints, got {spec['entrypoints']!r}")
print("backend-only uups contract-spec: ok")
PY

echo "=== E1.4: negative authority + UUPS product policy ==="
set +e
neg_out=$(lake env proof-forge build --target evm --root . \
  -o "$OUT_DIR/BadUpgradeAuth.bin" \
  Tests/Backend/Evm/BadUpgradeAuth.lean 2>&1)
neg_ec=$?
set -e
if [[ "$neg_ec" -eq 0 ]]; then
  fail "BadUpgradeAuth unexpectedly built (must fail closed)"
fi
echo "$neg_out" | grep -Fq 'does not materialize `authority`' \
  || fail "diagnostic missing unsupported authority explanation; got: $neg_out"

echo "=== E1.4: unit matrix (Tests/UpgradePolicy.lean) ==="
lake env lean --run Tests/UpgradePolicy.lean \
  || fail "Tests/UpgradePolicy.lean failed"

echo "=== E1.4: atomic deployment and attacker-first regression ==="
scripts/evm/uups-atomic-init-smoke.sh \
  || fail "atomic UUPS deployment smoke failed"

echo "upgrade-policy-honesty: ok"
