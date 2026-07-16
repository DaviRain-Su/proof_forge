/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Official Ownable + ERC-20 composition. Prefer `import ProofForge.Contract.Stdlib.OwnableERC20`
(or `compose OwnableERC20;`) over importing both `Ownable` and `ERC20` in one module.
-/
import ProofForge.Contract.Compose
import ProofForge.Contract.Stdlib.Compose.Specs

namespace ProofForge.Contract.Stdlib.OwnableERC20

def spec : ProofForge.Contract.ContractSpec :=
  ProofForge.Contract.Stdlib.Compose.Specs.ownableErc20Spec

def module : ProofForge.IR.Module :=
  spec.module

end ProofForge.Contract.Stdlib.OwnableERC20
