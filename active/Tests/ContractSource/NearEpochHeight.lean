/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Minimal NEAR epoch-height fixture for target-first EmitWat smoke tests.
-/
import ProofForge.Contract.Source

namespace Tests.ContractSource.NearEpochHeight

open ProofForge.Contract.Source

contract_source NearEpochHeight do
  query epoch returns(.u64) do
    return epochHeight;

end Tests.ContractSource.NearEpochHeight
