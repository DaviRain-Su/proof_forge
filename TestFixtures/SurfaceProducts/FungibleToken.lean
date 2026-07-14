import Examples.Product.FungibleToken
import ProofForge.Contract.Token.EvmSurface

namespace TestFixtures.SurfaceProducts.FungibleToken

def contract := ProofForge.Contract.Token.EvmSurface.materialize
  Examples.Product.FungibleToken.spec

end TestFixtures.SurfaceProducts.FungibleToken
