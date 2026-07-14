/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Minimal NEAR random-seed fixture for target-first EmitWat smoke tests.
-/
import ProofForge.Contract.Source.Legacy

namespace Tests.ContractSource.NearRandomSeed

open ProofForge.Contract.Source.Legacy

contract_source NearRandomSeed do
  query seed returns(.hash) do
    return randomSeed;

end Tests.ContractSource.NearRandomSeed
