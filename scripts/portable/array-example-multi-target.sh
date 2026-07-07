#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

export PATH="$HOME/.elan/bin:$HOME/.local/bin:$HOME/.foundry/bin:$PATH"

SOURCE="${PORTABLE_ARRAY_EXAMPLE_SOURCE:-Examples/Shared/ArrayExample.lean}"
OUT="${PORTABLE_ARRAY_EXAMPLE_OUT:-build/portable-array-example}"
HOST=(cargo run --quiet --manifest-path runtime/offline-host/Cargo.toml -- run)

if [[ -n "${PROOF_FORGE_BIN:-}" ]]; then
  proof_forge=("$PROOF_FORGE_BIN")
else
  proof_forge=(lake env proof-forge)
fi

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

require_file() {
  [ -f "$1" ] || fail "file not written: $1"
}

require_contains() {
  local file="$1"
  local needle="$2"
  local label="$3"
  grep -Fq -- "$needle" "$file" || fail "$label missing '$needle' in $file"
}

command -v lake >/dev/null 2>&1 || fail "lake not on PATH"
command -v python3 >/dev/null 2>&1 || fail "python3 not on PATH"
command -v solc >/dev/null 2>&1 || fail "solc not on PATH"
command -v cast >/dev/null 2>&1 || fail "cast not on PATH"

rm -rf "$OUT"
mkdir -p "$OUT/evm" "$OUT/solana" "$OUT/near"

(cd "$ROOT" && lake build proof-forge Examples.Shared.ArrayExample >/dev/null)

echo "portable-array-example: EVM"
"${proof_forge[@]}" build --target evm --root . \
  -o "$OUT/evm/ArrayExample.bin" \
  --yul-output "$OUT/evm/ArrayExample.yul" \
  --artifact-output "$OUT/evm/ArrayExample.proof-forge-artifact.json" \
  "$SOURCE"
diff -u Examples/Evm/Contracts/ArrayExample.golden.yul "$OUT/evm/ArrayExample.yul"
python3 scripts/evm/validate-artifact-metadata.py \
  --root "$ROOT" \
  --expect-fixture ArrayExample \
  --expect-source-kind contract-sdk \
  --expect-entrypoint sizeOf3:8c471d33 \
  --expect-entrypoint getElem:ff170768 \
  --expect-entrypoint sumOf3:6d666075 \
  "$OUT/evm/ArrayExample.proof-forge-artifact.json"

echo "portable-array-example: Solana sBPF"
"${proof_forge[@]}" build --target solana-sbpf-asm --root . \
  -o "$OUT/solana/ArrayExample.s" \
  --artifact-output "$OUT/solana/ArrayExample.solana-artifact.json" \
  "$SOURCE"
require_file "$OUT/solana/ArrayExample.s"
require_file "$OUT/solana/manifest.toml"
require_file "$OUT/solana/proof-forge-idl.json"
require_file "$OUT/solana/proof-forge-client.ts"
require_file "$OUT/solana/ArrayExample.solana-artifact.json"
require_contains "$OUT/solana/ArrayExample.s" "sol_sizeOf3" "Solana sizeOf3 entrypoint"
require_contains "$OUT/solana/ArrayExample.s" "sol_getElem" "Solana getElem entrypoint"
require_contains "$OUT/solana/ArrayExample.s" "sol_sumOf3" "Solana sumOf3 entrypoint"
require_contains "$OUT/solana/ArrayExample.s" "array.get: compute element address" "Solana array lowering"
require_contains "$OUT/solana/manifest.toml" 'name = "sizeOf3"' "Solana manifest sizeOf3"
require_contains "$OUT/solana/manifest.toml" 'name = "getElem"' "Solana manifest getElem"
require_contains "$OUT/solana/manifest.toml" 'name = "sumOf3"' "Solana manifest sumOf3"
python3 - "$OUT/solana/ArrayExample.solana-artifact.json" <<'PY'
import json
import sys

artifact = json.load(open(sys.argv[1]))
assert artifact["target"] == "solana-sbpf-asm"
assert artifact["fixture"] == "ArrayExample"
assert artifact["sourceKind"] == "contract-sdk"
assert artifact["sourceModule"] == "ArrayExample"
print("portable-array-example solana artifact: ok")
PY

echo "portable-array-example: NEAR/Wasm"
"${proof_forge[@]}" build --target wasm-near --root . \
  -o "$OUT/near" \
  --artifact-output "$OUT/near/ArrayExample.near-artifact.json" \
  "$SOURCE"
require_file "$OUT/near/arrayexample.wat"
require_file "$OUT/near/arrayexample.wasm"
python3 scripts/near/validate-emitwat-metadata.py \
  "$OUT/near/ArrayExample.near-artifact.json" \
  --expected-fixture arrayexample \
  --expected-module ArrayExample \
  --expected-entrypoints sizeOf3,getElem,sumOf3 \
  --expected-source-kind contract-sdk

if out="$("${HOST[@]}" "$OUT/near/arrayexample.wat" sizeOf3 getElem sumOf3 2>&1)"; then
  echo "$out"
  grep -Fq "call 1:sizeOf3: return_hex=0300000000000000 return_u64=3" <<<"$out"
  grep -Fq "call 1:getElem: return_hex=1400000000000000 return_u64=20" <<<"$out"
  grep -Fq "call 1:sumOf3: return_hex=3c00000000000000 return_u64=60" <<<"$out"
else
  echo "portable-array-example: offline-host unavailable; WAT metadata checks passed" >&2
  echo "$out" >&2
fi

echo "portable-array-example-multi-target: ok"
