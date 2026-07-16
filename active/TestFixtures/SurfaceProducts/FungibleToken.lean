import Examples.Product.FungibleToken
import ProofForge.Frontend.Materialize.Evm.Token

namespace TestFixtures.SurfaceProducts.FungibleToken

def contract := ProofForge.Frontend.Materialize.Evm.Token.materialize
  Examples.Product.FungibleToken.spec

end TestFixtures.SurfaceProducts.FungibleToken
