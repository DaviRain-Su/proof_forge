#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

fail() {
  printf 'counter-authoring-cutover: %s\n' "$1" >&2
  exit 1
}

retired_alias='(ProofForge\.Contract\.Examples|Examples\.Product)\.Counter\.(spec|module)\b'

if rg -n "$retired_alias" \
    ProofForge Tests Examples scripts justfile >/dev/null; then
  rg -n "$retired_alias" ProofForge Tests Examples scripts justfile >&2
  fail 'retired Counter ContractSpec/IR.Module alias is still referenced'
fi

for retired in \
  Examples/Backend/Evm/Contracts/Counter.lean \
  Examples/Backend/Solana/Counter.lean
do
  if [[ -e "$retired" ]]; then
    fail "obsolete backend wrapper still exists: $retired"
  fi
done

alias_file=ProofForge/Contract/Examples/Counter.lean
rg -q '^import Examples\.Product\.Counter$' "$alias_file" ||
  fail 'Counter alias does not import the Product source'
rg -q '^def contract : ProofForge\.Frontend\.Authored\.AuthoredContract :=' "$alias_file" ||
  fail 'Counter alias does not export AuthoredContract'
if rg -n '^def (spec|module)\b' "$alias_file" >/dev/null; then
  fail 'Counter alias reintroduced a retired compatibility export'
fi

evm_probe=Examples/Backend/Evm/Contracts/CounterConstructorProbe.lean
rg -q '^def contract : ProofForge\.Frontend\.Authored\.AuthoredContract :=' "$evm_probe" ||
  fail 'EVM constructor probe does not reuse the direct AuthoredContract'
rg -q '^def evmConstructor : ProofForge\.Backend\.Evm\.Plan\.ConstructorConfigPlan := \{' "$evm_probe" ||
  fail 'EVM constructor probe does not declare a target-owned constructor attachment'
if rg -n 'materialization|constructorParams :=|constructorBindings :=' "$evm_probe" >/dev/null; then
  fail 'EVM constructor probe leaked target constructor data into shared authoring/Core materialization'
fi

printf 'counter-authoring-cutover: ok\n'
