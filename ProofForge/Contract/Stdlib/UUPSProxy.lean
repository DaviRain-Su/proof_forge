/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Minimal backend-only UUPS proxy shell: ERC-1967 implementation slot plus
delegatecall fallback. The implementation and administrator are constructor
arguments written atomically during deployment; the runtime intentionally has
no public initializer. This transport primitive deliberately declares no
`UpgradePolicy`: ProofForge does not yet bind an authority `keyRef` to runtime
authorization. Pair with an implementation mixin such as `UUPSUpgradeable`.
-/
import ProofForge.Contract.Source
import ProofForge.Contract.Stdlib.UUPSUpgradeable

namespace ProofForge.Contract.Stdlib.UUPSProxy

open ProofForge.Contract.Source

def eip1967Implementation : ScalarRef :=
  ProofForge.Contract.Surface.eip1967Implementation

def «owner» : ScalarRef :=
  ProofForge.Contract.Stdlib.UUPSUpgradeable.owner

def declareAtomicConstructor : ProofForge.Contract.Surface.ModuleM Unit := do
  ProofForge.Contract.Surface.declareConstructorParam "implementation" "address"
  ProofForge.Contract.Surface.declareConstructorParam "admin" "address"
  ProofForge.Contract.Surface.declareConstructorInitBinding
    eip1967Implementation.id "implementation" .addressWord
  ProofForge.Contract.Surface.declareConstructorInitBinding
    «owner».id "admin" .addressKeccak

contract_source UUPSProxy do
  proxy_pattern_uups;

  use ProofForge.Contract.Surface.scalar «owner»
  use ProofForge.Contract.Surface.scalar eip1967Implementation
  use declareAtomicConstructor

end ProofForge.Contract.Stdlib.UUPSProxy
