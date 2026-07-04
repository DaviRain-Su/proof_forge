/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Reusable reentrancy lock primitive authored with `contract_source`.
-/
import ProofForge.Contract.Source

namespace ReentrancyGuard

open ProofForge.Contract.Source

contract_source ReentrancyGuard do
  state lock : .u64

  entry acquire do
    do ProofForge.Contract.Surface.acquireLock lock;

  entry release do
    do ProofForge.Contract.Surface.releaseLock lock;

  query locked returns(.u64) do
    return lock;

end ReentrancyGuard
