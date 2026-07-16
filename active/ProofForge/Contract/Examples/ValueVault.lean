import Examples.Product.ValueVault

namespace ProofForge.Contract.Examples.ValueVault

def spec : ProofForge.Contract.ContractSpec :=
  Examples.Product.ValueVault.spec

def module : ProofForge.IR.Module :=
  spec.module

end ProofForge.Contract.Examples.ValueVault
