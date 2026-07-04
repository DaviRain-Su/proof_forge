/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

UUPS upgrade mixin for implementation contracts deployed behind an ERC-1967 proxy.
Writes the implementation pointer and exposes `upgradeTo` guarded by `owner`.
-/
import ProofForge.Contract.Source

namespace ProofForge.Contract.Stdlib.UUPSUpgradeable

open ProofForge.Contract.Source

def «owner» : ScalarRef :=
  ProofForge.Contract.Surface.slot "owner" .u64

def eip1967Implementation : ScalarRef :=
  ProofForge.Contract.Surface.eip1967Implementation

contract_mixin UUPSUpgradeableMixin do
  use ProofForge.Contract.Surface.scalar «owner»
  use ProofForge.Contract.Surface.scalar eip1967Implementation

  event Upgraded

  entry upgradeTo (newImpl : .address) do
    guard_owner «owner»;
    do ProofForge.Contract.Surface.requireNonZero (ProofForge.Contract.Surface.ref newImpl) "zero implementation";
    eip1967Implementation := newImpl;
    emit Upgraded indexed #[
      fieldAsName "implementation" newImpl
    ] data #[];

contract_source UUPSUpgradeable do
  use mixin

end ProofForge.Contract.Stdlib.UUPSUpgradeable
