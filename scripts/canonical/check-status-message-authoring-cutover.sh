#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

fail() {
  printf 'status-message-authoring-cutover: %s\n' "$1" >&2
  exit 1
}

product=Examples/Product/StatusMessage.lean

rg -q '^import ProofForge\.Contract\.Source$' "$product" ||
  fail 'Product StatusMessage does not import the direct Source frontend'
rg -q '^contract_source StatusMessage do$' "$product" ||
  fail 'Product StatusMessage does not declare one direct contract_source'
if rg -n 'Source\.Legacy|^def (spec|module)\b' "$product" >/dev/null; then
  rg -n 'Source\.Legacy|^def (spec|module)\b' "$product" >&2
  fail 'Product StatusMessage still contains Legacy syntax or a v1 export'
fi

if rg -n 'Examples\.Product\.StatusMessage\.(spec|module)\b' \
    ProofForge Tests Examples scripts justfile >/dev/null; then
  rg -n 'Examples\.Product\.StatusMessage\.(spec|module)\b' \
    ProofForge Tests Examples scripts justfile >&2
  fail 'retired Product StatusMessage ContractSpec/IR.Module alias is still referenced'
fi

if [[ -e TestFixtures/SurfaceProducts/StatusMessage.lean ]]; then
  fail 'duplicate Surface StatusMessage source still exists'
fi

if rg -n 'Examples/Product/StatusMessage\.lean:' \
    scripts/portable/product-contract-spec-allowlist.txt >/dev/null; then
  fail 'StatusMessage remains in the ContractSpec compatibility allowlist'
fi

printf 'status-message-authoring-cutover: ok\n'
