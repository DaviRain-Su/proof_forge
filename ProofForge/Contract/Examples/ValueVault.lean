import Examples.Shared.ValueVault

namespace ProofForge.Contract.Examples.ValueVault

def spec : ProofForge.Contract.ContractSpec :=
  Examples.Shared.ValueVault.spec

def module : ProofForge.IR.Module :=
  spec.module

end ProofForge.Contract.Examples.ValueVault
