#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

fail() {
  printf 'reentrancy-guard-authoring-cutover: %s\n' "$1" >&2
  exit 1
}

product=Examples/Product/ReentrancyGuard.lean

rg -q '^import ProofForge\.Contract\.Source$' "$product" ||
  fail 'Product ReentrancyGuard does not import the direct Source frontend'
rg -q '^contract_source ReentrancyGuard do$' "$product" ||
  fail 'Product ReentrancyGuard does not declare one direct contract_source'
if rg -n 'Source\.Legacy|Contract\.Stdlib\.ReentrancyGuard|^def (spec|module)\b' "$product" >/dev/null; then
  rg -n 'Source\.Legacy|Contract\.Stdlib\.ReentrancyGuard|^def (spec|module)\b' "$product" >&2
  fail 'Product ReentrancyGuard still contains a Legacy, stdlib-facade, or v1 export'
fi

retired_alias='Examples\.Product\.ReentrancyGuard\.(spec|module)\b'
if rg -n "$retired_alias" ProofForge Tests Examples scripts justfile >/dev/null; then
  rg -n "$retired_alias" ProofForge Tests Examples scripts justfile >&2
  fail 'retired Product ReentrancyGuard ContractSpec/IR.Module alias is still referenced'
fi

for retired in \
  ProofForge/Contract/Stdlib/ReentrancyGuard.lean \
  Examples/Backend/Evm/Contracts/stdlib/ReentrancyGuard.lean
do
  if [[ -e "$retired" ]]; then
    fail "obsolete Legacy implementation or compatibility wrapper still exists: $retired"
  fi
done

if rg -n 'Examples/Product/ReentrancyGuard\.lean:|ProofForge/Contract/Stdlib/ReentrancyGuard\.lean:' \
    scripts/portable/product-contract-spec-allowlist.txt >/dev/null; then
  fail 'ReentrancyGuard remains in the ContractSpec compatibility allowlist'
fi

printf 'reentrancy-guard-authoring-cutover: ok\n'
