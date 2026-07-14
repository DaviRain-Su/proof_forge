#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

fail() {
  printf 'pausable-authoring-cutover: %s\n' "$1" >&2
  exit 1
}

product=Examples/Product/Pausable.lean

rg -q '^import ProofForge\.Contract\.Source$' "$product" ||
  fail 'Product Pausable does not import the direct Source frontend'
rg -q '^contract_source Pausable do$' "$product" ||
  fail 'Product Pausable does not declare one direct contract_source'
if rg -n 'Source\.Legacy|Contract\.Stdlib\.Pausable|^def (spec|module)\b' "$product" >/dev/null; then
  rg -n 'Source\.Legacy|Contract\.Stdlib\.Pausable|^def (spec|module)\b' "$product" >&2
  fail 'Product Pausable still contains a Legacy, stdlib-facade, or v1 export'
fi

retired_alias='Examples\.Product\.Pausable\.(spec|module)\b'
if rg -n "$retired_alias" ProofForge Tests Examples scripts justfile >/dev/null; then
  rg -n "$retired_alias" ProofForge Tests Examples scripts justfile >&2
  fail 'retired Product Pausable ContractSpec/IR.Module alias is still referenced'
fi

for retired in \
  ProofForge/Contract/Stdlib/Pausable.lean \
  Examples/Backend/Evm/Contracts/stdlib/Pausable.lean
do
  if [[ -e "$retired" ]]; then
    fail "obsolete Legacy implementation or compatibility wrapper still exists: $retired"
  fi
done

if rg -n 'Examples/Product/Pausable\.lean:|ProofForge/Contract/Stdlib/Pausable\.lean:' \
    scripts/portable/product-contract-spec-allowlist.txt >/dev/null; then
  fail 'Pausable remains in the ContractSpec compatibility allowlist'
fi

printf 'pausable-authoring-cutover: ok\n'
