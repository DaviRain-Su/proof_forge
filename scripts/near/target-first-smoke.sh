#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

OUT_ROOT="${PROOF_FORGE_NEAR_TARGET_FIRST_OUT:-build/wasm-near-target-first}"
COUNTER_DIR="$OUT_ROOT/counter-emit"
CONTEXT_DIR="$OUT_ROOT/context-build"
HOST=(cargo run --quiet --manifest-path runtime/offline-host/Cargo.toml -- run)

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if ! grep -Fq "$needle" <<<"$haystack"; then
    echo "near-target-first: expected ${label} to contain: ${needle}" >&2
    echo "$haystack" >&2
    exit 1
  fi
}

rm -rf "$OUT_ROOT"

lake env proof-forge check --target wasm-near --fixture counter --format wat
lake env proof-forge emit --target wasm-near --fixture counter --format wat -o "$COUNTER_DIR"

python3 scripts/near/validate-emitwat-metadata.py \
  "$COUNTER_DIR/proof-forge-artifact.json" \
  --expected-fixture counter \
  --expected-module Counter \
  --expected-entrypoints initialize,increment,get
python3 scripts/sdk/validate-sdk-schema.py \
  "$COUNTER_DIR/proof-forge-sdk.json" \
  --expect-schema proof-forge.sdk-schema.v0 \
  --expect-ir portable-ir-v0 \
  --expect-target wasm-near
python3 scripts/sdk/validate-sdk-artifact-refs.py \
  --require-relative \
  --reject-absolute \
  "$COUNTER_DIR/proof-forge-sdk.json"
test -s "$COUNTER_DIR/Counter.contract-spec.json"
test -s "$COUNTER_DIR/proof-forge-near.ts"
test -s "$COUNTER_DIR/proof-forge-client.ts"
grep -Fq "account.viewFunction({ contractId, methodName: \"get\", args: {} })" "$COUNTER_DIR/proof-forge-near.ts"
grep -Fq "account.functionCall({" "$COUNTER_DIR/proof-forge-near.ts"

out="$("${HOST[@]}" "$COUNTER_DIR/counter.wat" initialize get increment get)"
echo "$out"
assert_contains "$out" "call 1:get: return_hex=0000000000000000 return_u64=0" "counter initial get"
assert_contains "$out" "call 1:get: return_hex=0100000000000000 return_u64=1" "counter increment get"

lake env proof-forge check --target wasm-near --fixture context --format wat
lake env proof-forge build --target wasm-near --fixture context --format wat -o "$CONTEXT_DIR"

python3 scripts/near/validate-emitwat-metadata.py \
  "$CONTEXT_DIR/proof-forge-artifact.json" \
  --expected-fixture context \
  --expected-module ContextProbe \
  --expected-entrypoints sum_context
python3 scripts/sdk/validate-sdk-schema.py \
  "$CONTEXT_DIR/proof-forge-sdk.json" \
  --expect-schema proof-forge.sdk-schema.v0 \
  --expect-ir portable-ir-v0 \
  --expect-target wasm-near
python3 scripts/sdk/validate-sdk-artifact-refs.py \
  --require-relative \
  --reject-absolute \
  "$CONTEXT_DIR/proof-forge-sdk.json"

echo "near-target-first: ok"
