import Examples.Product.FungibleToken
import ProofForge.Contract.Token.EvmSurface

namespace Examples.Product.Canonical.FungibleToken

def contract := ProofForge.Contract.Token.EvmSurface.materialize
  Examples.Product.FungibleToken.spec

end Examples.Product.Canonical.FungibleToken
