import ProofForge.Contract.Compose
import ProofForge.Contract.Stdlib.Compose.OwnablePart
import ProofForge.Contract.Stdlib.Compose.ERC20Part

import ProofForge.Contract.Stdlib.Compose.Specs

namespace Tests.MixinComposeProbe

def composed : ProofForge.Contract.ContractSpec :=
  ProofForge.Contract.Stdlib.Compose.Specs.ownableErc20Spec

def run : IO Unit := do
  IO.println s!"entrypoints={composed.module.entrypoints.size}"
  IO.println s!"state={composed.module.state.size}"

end Tests.MixinComposeProbe

def main : IO Unit :=
  Tests.MixinComposeProbe.run
