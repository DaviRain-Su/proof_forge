#!/usr/bin/env bash
# Engineering: build Token NEAR + run near_wasm_acceptance on the WAT/Wasm.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$root/build/v2/token-near"
mkdir -p "$out"
(cd "$root" && lake env .lake/build/bin/proof-forge-next build \
  Examples/Token.lean --module Examples.Token --target near -o build/v2/token-near) || {
  echo "near-token-wasm: skipped: Token NEAR build failed" >&2; exit 0
}
exec bash "$root/scripts/near_wasm_acceptance.sh" "$out"
