#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

echo "=== near-promise-hostop: catalog + handler registry ==="
lake env lean --run Tests/Canonical/NearPromiseHostOp.lean

echo "=== canonical-near-promise: NEAR plan builder ==="
lake env lean --run Tests/Backend/Wasm/CanonicalNearPromise.lean

echo "=== wasm-near-plan ==="
just wasm-near-plan

echo "near-promise-hostop.sh: ok"