/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Minimal UUPS proxy shell: ERC-1967 implementation slot plus delegatecall fallback.
Pair with an implementation mixin such as `UUPSUpgradeable`.
-/
import ProofForge.Contract.Source

namespace ProofForge.Contract.Stdlib.UUPSProxy

open ProofForge.Contract.Source

def eip1967Implementation : ScalarRef :=
  ProofForge.Contract.Surface.eip1967Implementation

contract_source UUPSProxy do
  upgrade_policy_authority admin;
  proxy_pattern_uups;

  use ProofForge.Contract.Surface.scalar eip1967Implementation

  entry init (impl : .address) do
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref impl) "zero implementation";
    eip1967Implementation := impl;

end ProofForge.Contract.Stdlib.UUPSProxy
