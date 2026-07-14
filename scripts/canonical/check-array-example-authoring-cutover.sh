#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

fail() {
  printf 'array-example-authoring-cutover: %s\n' "$1" >&2
  exit 1
}

product=Examples/Product/ArrayExample.lean

rg -q '^import ProofForge\.Contract\.Source$' "$product" ||
  fail 'Product ArrayExample does not import the direct Source frontend'
rg -q '^contract_source ArrayExample do$' "$product" ||
  fail 'Product ArrayExample does not declare one direct contract_source'
if rg -n 'Source\.Legacy|fixedu64x3|^def (spec|module)\b' "$product" >/dev/null; then
  rg -n 'Source\.Legacy|fixedu64x3|^def (spec|module)\b' "$product" >&2
  fail 'Product ArrayExample still contains Legacy syntax or a v1 export'
fi

retired_alias='Examples\.Product\.ArrayExample\.(spec|module)\b'
if rg -n "$retired_alias" ProofForge Tests Examples scripts justfile >/dev/null; then
  rg -n "$retired_alias" ProofForge Tests Examples scripts justfile >&2
  fail 'retired Product ArrayExample ContractSpec/IR.Module alias is still referenced'
fi

for retired in \
  Examples/Backend/Evm/Contracts/ArrayExample.lean \
  TestFixtures/SurfaceProducts/ArrayExample.lean
do
  if [[ -e "$retired" ]]; then
    fail "obsolete compatibility or duplicate authoring source still exists: $retired"
  fi
done

if rg -n 'Examples/Product/ArrayExample\.lean:' \
    scripts/portable/product-contract-spec-allowlist.txt >/dev/null; then
  fail 'ArrayExample remains in the ContractSpec compatibility allowlist'
fi

printf 'array-example-authoring-cutover: ok\n'
