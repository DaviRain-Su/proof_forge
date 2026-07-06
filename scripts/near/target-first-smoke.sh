#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

OUT_ROOT="${PROOF_FORGE_NEAR_TARGET_FIRST_OUT:-build/wasm-near-target-first}"
COUNTER_DIR="$OUT_ROOT/counter-emit"
CONTEXT_DIR="$OUT_ROOT/context-build"
TIMESTAMP_DIR="$OUT_ROOT/timestamp-build"
EPOCH_DIR="$OUT_ROOT/epoch-build"
RANDOM_DIR="$OUT_ROOT/random-seed-build"
STORAGE_DIR="$OUT_ROOT/storage-deposit-build"
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
grep -Fq "export type NearViewOptions" "$COUNTER_DIR/proof-forge-near.ts"
grep -Fq "export async function get(options: NearViewOptions = {}): Promise<bigint>" "$COUNTER_DIR/proof-forge-near.ts"
grep -Fq "account.viewFunction({" "$COUNTER_DIR/proof-forge-near.ts"
grep -Fq "...options" "$COUNTER_DIR/proof-forge-near.ts"
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

lake env proof-forge build --target wasm-near --root . -o "$TIMESTAMP_DIR" \
  Tests/ContractSource/NearTimestamp.lean

python3 scripts/near/validate-emitwat-metadata.py \
  "$TIMESTAMP_DIR/proof-forge-artifact.json" \
  --expected-fixture neartimestamp \
  --expected-module NearTimestamp \
  --expected-entrypoints now \
  --expected-source-kind contract-sdk
python3 scripts/sdk/validate-sdk-schema.py \
  "$TIMESTAMP_DIR/proof-forge-sdk.json" \
  --expect-schema proof-forge.sdk-schema.v0 \
  --expect-ir portable-ir-v0 \
  --expect-target wasm-near
python3 scripts/sdk/validate-sdk-artifact-refs.py \
  --require-relative \
  --reject-absolute \
  "$TIMESTAMP_DIR/proof-forge-sdk.json"

out="$("${HOST[@]}" "$TIMESTAMP_DIR/neartimestamp.wat" now --block-timestamp 123456789)"
echo "$out"
assert_contains "$out" "call 1:now: return_hex=15cd5b0700000000 return_u64=123456789" "contract_source timestamp"

lake env proof-forge build --target wasm-near --root . -o "$EPOCH_DIR" \
  Tests/ContractSource/NearEpochHeight.lean

python3 scripts/near/validate-emitwat-metadata.py \
  "$EPOCH_DIR/proof-forge-artifact.json" \
  --expected-fixture nearepochheight \
  --expected-module NearEpochHeight \
  --expected-entrypoints epoch \
  --expected-source-kind contract-sdk
python3 scripts/sdk/validate-sdk-schema.py \
  "$EPOCH_DIR/proof-forge-sdk.json" \
  --expect-schema proof-forge.sdk-schema.v0 \
  --expect-ir portable-ir-v0 \
  --expect-target wasm-near
python3 scripts/sdk/validate-sdk-artifact-refs.py \
  --require-relative \
  --reject-absolute \
  "$EPOCH_DIR/proof-forge-sdk.json"

out="$("${HOST[@]}" "$EPOCH_DIR/nearepochheight.wat" epoch --epoch-height 321)"
echo "$out"
assert_contains "$out" "call 1:epoch: return_hex=4101000000000000 return_u64=321" "contract_source epoch height"

lake env proof-forge build --target wasm-near --root . -o "$RANDOM_DIR" \
  Tests/ContractSource/NearRandomSeed.lean

python3 scripts/near/validate-emitwat-metadata.py \
  "$RANDOM_DIR/proof-forge-artifact.json" \
  --expected-fixture nearrandomseed \
  --expected-module NearRandomSeed \
  --expected-entrypoints seed \
  --expected-source-kind contract-sdk
python3 scripts/sdk/validate-sdk-schema.py \
  "$RANDOM_DIR/proof-forge-sdk.json" \
  --expect-schema proof-forge.sdk-schema.v0 \
  --expect-ir portable-ir-v0 \
  --expect-target wasm-near
python3 scripts/sdk/validate-sdk-artifact-refs.py \
  --require-relative \
  --reject-absolute \
  "$RANDOM_DIR/proof-forge-sdk.json"

SEED_HEX="000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
out="$("${HOST[@]}" "$RANDOM_DIR/nearrandomseed.wat" seed --random-seed-hex "$SEED_HEX")"
echo "$out"
assert_contains "$out" "call 1:seed: return_hex=$SEED_HEX return_len=32" "contract_source random seed"

lake env proof-forge build --target wasm-near --root . -o "$STORAGE_DIR" \
  Tests/ContractSource/NearStorageDeposit.lean

python3 scripts/near/validate-emitwat-metadata.py \
  "$STORAGE_DIR/proof-forge-artifact.json" \
  --expected-fixture nearstoragedeposit \
  --expected-module NearStorageDeposit \
  --expected-entrypoints init,storage_balance_bounds,storage_balance_of,storage_deposit \
  --expected-source-kind contract-sdk
python3 scripts/sdk/validate-sdk-schema.py \
  "$STORAGE_DIR/proof-forge-sdk.json" \
  --expect-schema proof-forge.sdk-schema.v0 \
  --expect-ir portable-ir-v0 \
  --expect-target wasm-near
python3 scripts/sdk/validate-sdk-artifact-refs.py \
  --require-relative \
  --reject-absolute \
  "$STORAGE_DIR/proof-forge-sdk.json"

ACCOUNT_HASH="000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
out="$("${HOST[@]}" "$STORAGE_DIR/nearstoragedeposit.wat" \
  init storage_balance_bounds storage_balance_of storage_deposit storage_balance_of \
  --attached-deposit 7 \
  --inputs-hex ",,$ACCOUNT_HASH,$ACCOUNT_HASH,$ACCOUNT_HASH")"
echo "$out"
assert_contains "$out" "call 1:storage_balance_bounds: return_hex=0100000000000000 return_u64=1" "storage bounds"
assert_contains "$out" "call 1:storage_balance_of: return_hex=0000000000000000 return_u64=0" "initial storage balance"
assert_contains "$out" "call 1:storage_balance_of: return_hex=0700000000000000 return_u64=7" "updated storage balance"

echo "near-target-first: ok"
