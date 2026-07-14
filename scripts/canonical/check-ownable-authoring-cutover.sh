#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

fail() {
  printf 'ownable-authoring-cutover: %s\n' "$1" >&2
  exit 1
}

product=Examples/Product/Ownable.lean

rg -q '^import ProofForge\.Contract\.Source$' "$product" ||
  fail 'Product Ownable does not import the direct Source frontend'
rg -q '^contract_source Ownable do$' "$product" ||
  fail 'Product Ownable does not declare one direct contract_source'
if rg -n 'Source\.Legacy|Contract\.Stdlib\.Ownable|^def (spec|module)\b' "$product" >/dev/null; then
  rg -n 'Source\.Legacy|Contract\.Stdlib\.Ownable|^def (spec|module)\b' "$product" >&2
  fail 'Product Ownable still contains a Legacy, stdlib-facade, or v1 export'
fi

retired_alias='Examples\.Product\.Ownable\.(spec|module)\b'
if rg -n "$retired_alias" ProofForge Tests Examples scripts justfile >/dev/null; then
  rg -n "$retired_alias" ProofForge Tests Examples scripts justfile >&2
  fail 'retired Product Ownable ContractSpec/IR.Module alias is still referenced'
fi

retired_wrapper=Examples/Backend/Evm/Contracts/stdlib/Ownable.lean
if [[ -e "$retired_wrapper" ]]; then
  fail "obsolete EVM compatibility wrapper still exists: $retired_wrapper"
fi

if rg -n '^Examples/Product/Ownable\.lean:' \
    scripts/portable/product-contract-spec-allowlist.txt >/dev/null; then
  fail 'Product Ownable remains in the ContractSpec compatibility allowlist'
fi

printf 'ownable-authoring-cutover: ok\n'
