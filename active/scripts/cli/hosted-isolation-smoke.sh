#!/usr/bin/env bash
# PF-P3-03: ContractLoader must not claim hosted isolation via local elaboration.
#
# - With PROOF_FORGE_HOSTED_ISOLATION=1, product Counter build fails closed.
# - Without the flag, trusted local Counter build still succeeds.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.elan/bin:${HOME}/.foundry/bin:${HOME}/.local/bin:${PATH}"

fail() { echo "hosted-isolation: $*" >&2; exit 1; }

lake build proof-forge >/dev/null

OUT="${PROOF_FORGE_HOSTED_ISOLATION_OUT:-build/hosted-isolation-smoke}"
rm -rf "$OUT"
mkdir -p "$OUT"

# Gate 1: hosted mode refuses local elaboration (not an isolation boundary).
set +e
err="$(
  PROOF_FORGE_HOSTED_ISOLATION=1 \
    lake env proof-forge build --target wasm-near --root . \
      -o "$OUT/hosted-refused" \
      Examples/Product/Counter.lean 2>&1
)"
st=$?
set -e
[[ "$st" -ne 0 ]] || fail "hosted mode must refuse Counter build; got exit 0"
echo "$err" | grep -Fq "hosted isolation is not ready" \
  || fail "missing hosted-isolation diagnostic: $err"
echo "$err" | grep -Fq "PF-P3-03" \
  || fail "missing PF-P3-03 marker: $err"
echo "hosted-isolation: gate1 refuse under PROOF_FORGE_HOSTED_ISOLATION=1 ok"

# Gate 1b: TokenSpec uses the same trusted-local frontend and must not bypass
# the hosted-isolation refusal.
set +e
token_err="$(
  PROOF_FORGE_HOSTED_ISOLATION=1 \
    lake env proof-forge build --target solana-sbpf-asm --token --root . \
      -o "$OUT/hosted-token-refused.json" \
      Examples/Product/FungibleToken.lean 2>&1
)"
token_st=$?
set -e
[[ "$token_st" -ne 0 ]] || fail "hosted mode must refuse TokenSpec build; got exit 0"
echo "$token_err" | grep -Fq "hosted isolation is not ready" \
  || fail "TokenSpec bypassed hosted-isolation diagnostic: $token_err"
echo "hosted-isolation: gate1b TokenSpec refuse ok"
PROOF_FORGE_HOSTED_ISOLATION=1 \
  lake env lean --run Tests/HostedTokenIsolation.lean >/dev/null \
  || fail "TokenLoader shared frontend boundary regression"

# Gate 2: trusted local path still works when the flag is unset.
unset PROOF_FORGE_HOSTED_ISOLATION || true
set +e
ok="$(
  lake env proof-forge build --target wasm-near --root . \
    -o "$OUT/local-ok" \
    Examples/Product/Counter.lean 2>&1
)"
st=$?
set -e
[[ "$st" -eq 0 ]] || fail "trusted local Counter build failed: $ok"
[[ -f "$OUT/local-ok/counter.wat" || -f "$OUT/local-ok/counter.wasm" ]] \
  || fail "expected NEAR Counter wat/wasm under $OUT/local-ok (got: $(ls -la "$OUT/local-ok" 2>/dev/null || true))"
echo "hosted-isolation: gate2 trusted local Counter build ok"

# Gate 3: pure Lean pins for truthy/falsy + message stability.
lake env lean --run Tests/HostedIsolation.lean >/dev/null
echo "hosted-isolation: gate3 HostedIsolation pins ok"

# Gate 4: artifact metadata records the lean-toolchain pin (PF-P3-03 provenance).
pin="$(tr -d '[:space:]' < lean-toolchain)"
[[ -n "$pin" ]] || fail "lean-toolchain pin empty"
art="$OUT/local-ok/proof-forge-artifact.json"
[[ -f "$art" ]] || fail "missing artifact metadata $art"
python3 - "$art" "$pin" <<'PY'
import json, sys
art, pin = sys.argv[1], sys.argv[2]
data = json.load(open(art))
# Prefer nested artifactBundle.toolchain; fall back to flat toolchain object.
tools = []
bundle = data.get("artifactBundle") or {}
if isinstance(bundle, dict):
    source = bundle.get("source") or {}
    if source.get("leanElaborated") is not True:
        raise SystemExit(f"contract source must record leanElaborated=true: {source!r}")
    tools = bundle.get("toolchain") or []
if not tools:
    tools = data.get("toolchain") or []
# toolchain may be list of objects or a map
found = False
if isinstance(tools, list):
    for t in tools:
        if isinstance(t, dict) and t.get("tool") == "lean":
            expected = pin.rsplit(":", 1)[-1]
            if expected.startswith("v"):
                expected = expected[1:]
            if (t.get("declaredVersion") == pin
                    and t.get("observedVersion") == expected
                    and t.get("version") == t.get("observedVersion")):
                found = True
                break
elif isinstance(tools, dict):
    lean = tools.get("lean") or tools.get("Lean")
    if lean and pin in str(lean):
        found = True
if not found:
    raise SystemExit(f"lean pin {pin!r} not found in artifact toolchain: {tools!r}")
print(f"hosted-isolation: gate4 declared/observed Lean recorded ({pin})")
PY

echo "hosted-isolation: ok (PF-P3-03 fail-closed gate + lean pin provenance)"
