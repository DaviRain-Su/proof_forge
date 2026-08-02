#!/usr/bin/env bash
# Engineering: build Token NEAR (dense Map pilot) + wat2wasm / wasm-interp smoke.
# Not formal Reference↔NEAR sandbox; skips cleanly when tools are missing.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cli="$root/.lake/build/bin/proof-forge-next"
out="$root/build/v2/token-near"
if [[ ! -x "$cli" ]]; then
  echo "near-token-wasm: building proof-forge-next..." >&2
  (cd "$root" && lake build proof_forge_next) || {
    echo "near-token-wasm: skipped: lake build failed" >&2; exit 0
  }
fi
# CLI rejects pre-existing -o paths (PF-OUTPUT-COLLISION); remove and let it create.
rm -rf "$out"
echo "near-token-wasm: build Examples/Token.lean --target near" >&2
(cd "$root" && lake env "$cli" build \
  Examples/Token.lean --module Examples.Token --target near -o build/v2/token-near) || {
  echo "near-token-wasm: skipped: Token NEAR build failed" >&2; exit 0
}
# Sanity: Map pilot leaves present in plan text when plan is emitted.
if [[ -f "$out/Token.near-plan" ]] || [[ -f "$out/Token.wat" ]]; then
  plan_or_wat=$(ls "$out"/Token.* 2>/dev/null | head -1 || true)
  echo "near-token-wasm: artifacts under $out ($(ls "$out" | tr '\n' ' '))" >&2
fi
echo "near-token-wasm: wat2wasm / wasm-interp acceptance (engineering only)" >&2
exec bash "$root/scripts/near_wasm_acceptance.sh" "$out"
