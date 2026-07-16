import Examples.Product.Counter

namespace ProofForge.Contract.Examples.Counter

def spec : ProofForge.Contract.ContractSpec :=
  Examples.Product.Counter.spec

def module : ProofForge.IR.Module :=
  spec.module

end ProofForge.Contract.Examples.Counter
