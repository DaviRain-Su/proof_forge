/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Target-neutral ReentrancyGuard lock-state policy shared across target plans.

This file is the only Product authoring source. It normalizes directly from
`AuthoredContract` to checked Canonical Core and target-owned plans.
-/
import ProofForge.Contract.Source

namespace Examples.Product.ReentrancyGuard

open ProofForge.Contract.Source

contract_source ReentrancyGuard do
  state lock : .u64

  entry acquire do
    do requireEq lock (u64 0) "reentrant call";
    lock := u64 1;

  entry release do
    do requireNe lock (u64 0) "lock not held";
    lock := u64 0;

  query locked returns(.u64) do
    return lock;

end Examples.Product.ReentrancyGuard
