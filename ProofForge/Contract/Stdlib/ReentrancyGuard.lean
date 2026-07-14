/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Reusable reentrancy **lock-state** mixin for `contract_source` composition.

## Product boundary (portable hosts)

| Host | Materialization | Semantics note |
|------|-----------------|----------------|
| **EVM** | scalar lock + acquire/release guards | Primary product meaning: CEI-style reentrancy lock |
| **Solana** | program account scalar + assert | Same IR lock; not Anchor mutex — authors still design CPI safety |
| **NEAR** | storage scalar + unreachable/panic | Same IR lock; host reentrancy differs from EVM call stack |
| **Soroban** | `_get`/`_put` scalar | Same IR lock; pair with host `require_auth` when needed |

The portable guarantee is **lock bit + require-unlocked**, not full
chain-equivalent reentrancy theory. Prefer this mixin when the business rule is
“do not re-enter this critical section”; do not claim EVM-identical call-stack
semantics on Wasm/Solana.
-/
import ProofForge.Contract.Source

namespace ProofForge.Contract.Stdlib.ReentrancyGuard

open ProofForge.Contract.Source

def lock : ScalarRef :=
  ProofForge.Contract.Source.slot "lock" .u64

contract_mixin ReentrancyGuardMixin do
  use ProofForge.Contract.Source.scalar lock

  entry acquire do
    do ProofForge.Contract.Source.acquireLock lock;

  entry release do
    do ProofForge.Contract.Source.releaseLock lock;

  query locked returns(.u64) do
    return lock;

contract_source ReentrancyGuard do
  use mixin

end ProofForge.Contract.Stdlib.ReentrancyGuard
