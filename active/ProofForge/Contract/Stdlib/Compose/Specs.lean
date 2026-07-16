/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Isolated mixin specs for the official `compose` API (see `ProofForge.Contract.Compose`).
-/
import ProofForge.Contract.Compose
import ProofForge.Contract.Stdlib.Compose.OwnablePart
import ProofForge.Contract.Stdlib.Compose.ERC20Part

namespace ProofForge.Contract.Stdlib.Compose.Specs

export ProofForge.Contract.Compose (mergeSpecs mergeMany mergeModules mergeExtension)

def ownableSpec : ProofForge.Contract.ContractSpec :=
  ProofForge.Contract.Stdlib.Compose.OwnablePart.spec

def erc20Spec : ProofForge.Contract.ContractSpec :=
  ProofForge.Contract.Stdlib.Compose.ERC20Part.spec

def ownableErc20Spec : ProofForge.Contract.ContractSpec :=
  ProofForge.Contract.Compose.mergeSpecs "OwnableERC20" ownableSpec erc20Spec

end ProofForge.Contract.Stdlib.Compose.Specs
