/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Minimal backend-only UUPS proxy shell: ERC-1967 implementation slot plus
delegatecall fallback. The implementation and administrator are constructor
arguments written atomically during deployment; the runtime intentionally has
no public initializer. The explicit `admin` constructor argument initializes the
`owner` storage slot used by `upgradeTo`, but it does not bind a portable
`UpgradePolicy.authority` `keyRef`. This fixture therefore declares no upgrade
policy. Pair it with an implementation mixin such as `UUPSUpgradeable`.
-/
import ProofForge.Contract.Source.Legacy
import ProofForge.Contract.Stdlib.UUPSUpgradeable

namespace ProofForge.Contract.Stdlib.UUPSProxy

open ProofForge.Contract.Source.Legacy

def eip1967Implementation : ScalarRef :=
  ProofForge.Contract.Source.Legacy.eip1967Implementation

def «owner» : ScalarRef :=
  ProofForge.Contract.Stdlib.UUPSUpgradeable.owner

def declareAtomicConstructor : ProofForge.Contract.Source.Legacy.ModuleM Unit := do
  ProofForge.Contract.Source.Legacy.declareConstructorParam "implementation" "address"
  ProofForge.Contract.Source.Legacy.declareConstructorParam "admin" "address"
  ProofForge.Contract.Source.Legacy.declareConstructorInitBinding
    eip1967Implementation.id "implementation" .addressWord
  ProofForge.Contract.Source.Legacy.declareConstructorInitBinding
    «owner».id "admin" .addressKeccak

contract_source UUPSProxy do
  proxy_pattern_uups;

  use ProofForge.Contract.Source.Legacy.scalar «owner»
  use ProofForge.Contract.Source.Legacy.scalar eip1967Implementation
  use declareAtomicConstructor

end ProofForge.Contract.Stdlib.UUPSProxy
