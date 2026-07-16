#!/usr/bin/env bash
# PF-P3-02: six-gate promotion smoke for wasm-cosmwasm (Counter fragment).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.foundry/bin:${HOME}/.elan/bin:${HOME}/.cargo/bin:${PATH}"

OUT="${PROOF_FORGE_COSMWASM_PROMOTION_OUT:-build/cosmwasm-promotion}"
rm -rf "$OUT"
mkdir -p "$OUT"

fail() { echo "cosmwasm-promotion: $*" >&2; exit 1; }
ok() { echo "cosmwasm-promotion: ok — $*"; }

lake build proof-forge >/dev/null

# --- Gate 1: declared product source loaded ---
lake env proof-forge build --target wasm-cosmwasm --root . \
  -o "$OUT/counter" \
  --artifact-output "$OUT/counter/artifact.json" \
  Examples/Product/Counter.lean \
  || fail "gate1: Counter product source build failed"

ART="$OUT/counter/artifact.json"
[[ -f "$ART" ]] || fail "gate1: missing artifact.json"
python3 - "$ART" <<'PY' || fail "gate1: source identity"
import json, sys
art = json.loads(open(sys.argv[1]).read())
assert art.get("target") == "wasm-cosmwasm", art.get("target")
sm = art.get("sourceModule") or art.get("fixture") or ""
blob = json.dumps(art).lower()
assert "counter" in sm.lower() or "counter" in blob, (sm, list(art.keys())[:20])
print("sourceModule/fixture ok:", sm or "(in blob)")
PY
ok "gate1 input identity"

# --- Gate 2: no NEAR wrapper swap ---
[[ ! -e "$OUT/counter/proof-forge-near.ts" ]] || fail "gate2: wrote NEAR wrapper for CosmWasm"
[[ -f "$OUT/counter/proof-forge-cosmwasm.ts" ]] || fail "gate2: missing proof-forge-cosmwasm.ts"
if grep -Fq "near-api-js" "$OUT/counter/proof-forge-cosmwasm.ts"; then
  fail "gate2: CosmWasm wrapper imports near-api-js"
fi
ok "gate2 CosmWasm sidecars (no NEAR swap)"

# --- Gate 3: HostBridge.cosmWasm materialization ---
python3 - "$ART" <<'PY' || fail "gate3 materialization"
import json, sys
art = json.loads(open(sys.argv[1]).read())
mat = art.get("materialization") or {}
assert mat.get("targetId") == "wasm-cosmwasm", mat
assert mat.get("hostBridge") == "cosmwasm", mat
print("hostBridge=cosmwasm")
PY
WAT=""
for c in "$OUT/counter/counter.wat" "$OUT/counter/Counter.wat"; do
  [[ -f "$c" ]] && WAT="$c" && break
done
[[ -n "$WAT" ]] || WAT="$(find "$OUT/counter" -name '*.wat' | head -n1 || true)"
[[ -n "$WAT" && -f "$WAT" ]] || fail "gate3: missing WAT"
grep -Fq 'db_read' "$WAT" || fail "gate3: WAT missing db_read"
grep -Fq 'db_write' "$WAT" || fail "gate3: WAT missing db_write"
! grep -Fq 'promise_create' "$WAT" || fail "gate3: WAT must not import NEAR promise_create"
! grep -Fq 'storage_read' "$WAT" || fail "gate3: WAT must not use NEAR storage_read"
! grep -Fq 'interface_version_8' "$WAT" || fail "gate3: product path must not use spike region adapter"
ok "gate3 HostBridge.cosmWasm EmitWat"

# --- Gate 4: toolchain validation (wat2wasm) ---
WASM=""
for c in "$OUT/counter/counter.wasm" "$OUT/counter/Counter.wasm"; do
  [[ -f "$c" ]] && WASM="$c" && break
done
if [[ -z "$WASM" || ! -f "$WASM" ]]; then
  if command -v wat2wasm >/dev/null 2>&1; then
    WASM="$OUT/counter/counter.wasm"
    wat2wasm "$WAT" -o "$WASM" || fail "gate4: wat2wasm failed"
  else
    fail "gate4: no wasm artifact and wat2wasm missing"
  fi
fi
[[ -s "$WASM" ]] || fail "gate4: empty wasm"
ok "gate4 final wasm present ($WASM)"

# --- Gate 5: offline-host Counter lifecycle ---
HOST=(cargo run --quiet --manifest-path runtime/offline-host/Cargo.toml -- run)
out="$("${HOST[@]}" "$WAT" initialize get increment get 2>&1)" || fail "gate5 offline-host failed: $out"
python3 - "$out" <<'PY' || fail "gate5: Counter lifecycle values"
import re, sys
text = sys.argv[1]
nums = [int(x) for x in re.findall(r"return_u64=(\d+)", text)]
print("parsed returns:", nums)
print(text)
if 0 in nums and 1 in nums and nums.index(0) < nums.index(1):
    print("lifecycle 0→1 ok")
else:
    raise SystemExit(f"unexpected Counter returns: {nums}")
PY
ok "gate5 offline-host Counter lifecycle"

# --- Gate 6: registry / CLI / README agreement ---
python3 - <<'PY' || fail "gate6 docs/registry"
from pathlib import Path
import subprocess
reg = Path("ProofForge/Target/Registry.lean").read_text()
assert 'id := "wasm-cosmwasm"' in reg
assert "counterMvp" in reg or "Counter MVP" in reg
readme = Path("README.md").read_text()
assert "wasm-cosmwasm" in readme
out = subprocess.check_output(["lake", "env", "proof-forge", "--list-targets"], text=True)
assert "wasm-cosmwasm" in out, out
print("registry+CLI+README agree on id")
PY
ok "gate6 surface agreement"

echo "cosmwasm-promotion: ok (six gates for Counter fragment)"
