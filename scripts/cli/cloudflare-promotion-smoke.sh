#!/usr/bin/env bash
# PF-P3-02: strict promotion-readiness audit for the off-chain Research
# Counter TypeScript sourcegen fragment. Passing does not change target maturity.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.foundry/bin:${HOME}/.elan/bin:${HOME}/.cargo/bin:/opt/homebrew/bin:${PATH}"

OUT="${PROOF_FORGE_CF_PROMOTION_OUT:-build/cloudflare-promotion}"
rm -rf "$OUT"
mkdir -p "$OUT"
WRANGLER_DIST="$(cd "$OUT" && pwd)/wrangler-dist"

fail() { echo "cloudflare-promotion: $*" >&2; exit 1; }
ok() { echo "cloudflare-promotion: ok — $*"; }

lake build proof-forge >/dev/null

# Gate 1: fixture emit loads Counter identity
TS="$OUT/Counter.ts"
lake env proof-forge emit --target wasm-cloudflare-workers --fixture counter --format ts -o "$TS" \
  || fail "gate1: emit fixture counter failed"
[[ -s "$TS" ]] || fail "gate1: empty TS"
grep -Eq 'function initialize|async function initialize' "$TS" || fail "gate1: missing initialize"
grep -Eq 'function get|async function get' "$TS" || fail "gate1: missing get"
grep -Eq 'function increment|async function increment' "$TS" || fail "gate1: missing increment"
ok "gate1 fixture Counter TS entrypoints"

# Gate 2: product source fail-closed
set +e
err="$(lake env proof-forge build --target wasm-cloudflare-workers --root . \
  -o "$OUT/reject" Examples/Product/Counter.lean 2>&1)"
st=$?
set -e
[[ "$st" -ne 0 ]] || fail "gate2: product Counter must fail-closed"
echo "$err" | grep -Eqi 'source input is not supported|fixture-only|not supported' \
  || fail "gate2: expected diagnostic, got: $err"
ok "gate2 product source fail-closed"

# Gate 3: package scaffolding from example (wrangler.toml + main)
cp -R Examples/Backend/CloudflareWorkers/Counter "$OUT/worker"
cp "$TS" "$OUT/worker/Counter.ts"
[[ -f "$OUT/worker/wrangler.toml" ]] || fail "gate3: missing wrangler.toml"
grep -Fq 'main' "$OUT/worker/wrangler.toml" || fail "gate3: wrangler.toml missing main"
ok "gate3 worker package layout"

# Gate 4: toolchain (wrangler dry-run when available)
if command -v wrangler >/dev/null 2>&1; then
  # A present tool that rejects the package is a failed validation, never green.
  set +e
  wrangler deploy --dry-run --outdir "$WRANGLER_DIST" --config "$OUT/worker/wrangler.toml" 2>&1 \
    | tee "$OUT/wrangler-dry-run.log"
  wr_st=${PIPESTATUS[0]}
  set -e
  [[ "$wr_st" -eq 0 ]] || fail "gate4: wrangler deploy --dry-run failed (exit $wr_st)"
  ok "gate4 wrangler deploy --dry-run"
else
  fail "gate4: wrangler not on PATH"
fi

# Gate 5: execute the generated Worker with a real Request/Response router and
# an in-memory KV implementation. This validates lifecycle behavior, not text.
cat > "$OUT/runtime-check.mjs" <<'JS'
import { pathToFileURL } from "node:url";

const modulePath = process.argv[2];
const worker = (await import(pathToFileURL(modulePath).href)).default;
const values = new Map();
const env = {
  COUNTER_KV: {
    async get(key) { return values.has(key) ? values.get(key) : null; },
    async put(key, value) { values.set(key, String(value)); },
  },
};

async function call(path, method) {
  return worker.fetch(new Request(`https://proof-forge.invalid${path}`, { method }), env, {});
}

let response = await call("/initialize", "POST");
if (response.status !== 200 || (await response.text()) !== "") throw new Error("initialize failed");
response = await call("/increment", "POST");
if (response.status !== 200 || (await response.text()) !== "") throw new Error("increment failed");
response = await call("/get", "GET");
if (response.status !== 200 || (await response.text()) !== "1") throw new Error("get did not return 1");
response = await call("/missing", "GET");
if (response.status !== 404) throw new Error("router did not return 404");
JS
runtime_js="$(find "$WRANGLER_DIST" -type f -name '*.js' -print -quit)"
[[ -n "$runtime_js" && -s "$runtime_js" ]] \
  || fail "gate5: wrangler dry-run did not produce a runnable JavaScript bundle"
node "$OUT/runtime-check.mjs" "$runtime_js" \
  || fail "gate5: generated Worker runtime lifecycle failed"
ok "gate5 generated Worker runtime lifecycle"

# Gate 6: docs/registry
python3 - <<'PY' || fail "gate6"
from pathlib import Path
import subprocess
assert 'id := "wasm-cloudflare-workers"' in Path("ProofForge/Target/Registry.lean").read_text()
assert "wasm-cloudflare-workers" in Path("README.md").read_text()
out = subprocess.check_output(["lake","env","proof-forge","--list-targets"], text=True)
assert "wasm-cloudflare-workers" in out
print("ok")
PY
ok "gate6 surface"

echo "cloudflare-promotion: ok (Counter TS Research readiness gates; maturity unchanged)"
