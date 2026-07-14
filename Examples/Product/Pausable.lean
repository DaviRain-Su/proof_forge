/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Target-neutral Pausable emergency-stop policy shared across target plans.

This file is the only Product authoring source. It normalizes directly from
`AuthoredContract` to checked Canonical Core and target-owned plans.
-/
import ProofForge.Contract.Source

namespace Examples.Product.Pausable

open ProofForge.Contract.Source

contract_source Pausable do
  state paused : .u64

  query paused returns(.u64) do
    return paused;

  entry pause do
    do requireEq paused (u64 0) "already paused";
    paused := u64 1;

  entry unpause do
    do requireNe paused (u64 0) "not paused";
    paused := u64 0;

end Examples.Product.Pausable
