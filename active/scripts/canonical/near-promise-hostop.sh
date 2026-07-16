#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

echo "=== near-promise-hostop: catalog + handler registry ==="
lake env lean --run Tests/Canonical/NearPromiseHostOp.lean

echo "=== canonical-near-promise: NEAR plan builder ==="
lake env lean --run Tests/Backend/Wasm/CanonicalNearPromise.lean

echo "=== canonical-near-promise: WAT validation ==="
wat2wasm build/canonical/near-promise/contract.wat \
  -o build/canonical/near-promise/contract.wasm
test -s build/canonical/near-promise/contract.wasm

echo "=== canonical-near-promise: offline host ==="
out="$(cargo run --quiet --manifest-path runtime/offline-host/Cargo.toml -- run \
  build/canonical/near-promise/contract.wasm createPromise)"
grep -q 'return_u64=0' <<<"$out"
grep -q 'promise_create id=0 account=alice.near method=methodName' <<<"$out"
grep -q 'deposit=18446744073709551619 gas=1000' <<<"$out"

echo "=== wasm-near-plan ==="
just wasm-near-plan

echo "near-promise-hostop.sh: ok"
