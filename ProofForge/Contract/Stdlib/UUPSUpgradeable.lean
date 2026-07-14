/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

UUPS upgrade mixin for implementation contracts deployed behind an ERC-1967 proxy.
Writes the implementation pointer and exposes `upgradeTo` guarded by `owner`.
-/
import ProofForge.Contract.Source.Legacy

namespace ProofForge.Contract.Stdlib.UUPSUpgradeable

open ProofForge.Contract.Source.Legacy

def «owner» : ScalarRef :=
  ProofForge.Contract.Source.Legacy.slot "owner" .hash

def eip1967Implementation : ScalarRef :=
  ProofForge.Contract.Source.Legacy.eip1967Implementation

contract_mixin UUPSUpgradeableMixin do
  use ProofForge.Contract.Source.Legacy.scalar «owner»
  use ProofForge.Contract.Source.Legacy.scalar eip1967Implementation

  event Upgraded abi #[
    ("implementation", "address")
  ]

  entry upgradeTo (newImpl : .address) do
    do ProofForge.Contract.Source.Legacy.requireOwnerHash «owner»;
    do ProofForge.Contract.Source.Legacy.requireNonZero (ProofForge.Contract.Source.Legacy.ref newImpl) "zero implementation";
    eip1967Implementation := newImpl;
    emit Upgraded indexed #[
      fieldAsName "implementation" newImpl
    ] data #[];

contract_source UUPSUpgradeable do
  use mixin

end ProofForge.Contract.Stdlib.UUPSUpgradeable
