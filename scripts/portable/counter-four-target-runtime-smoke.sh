#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

export PATH="$HOME/.foundry/bin:$PATH"

scripts/portable/counter-four-target-sdk.sh

CAST="${CAST:-$HOME/.foundry/bin/cast}" \
  cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario counter
scripts/sui/counter-smoke.sh build/sdk/move-sui

echo "counter-four-target-runtime-smoke: ok"
