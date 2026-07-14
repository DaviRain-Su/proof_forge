import Examples.Product.Nft
import ProofForge.Frontend.Materialize.Evm.Nft

namespace TestFixtures.SurfaceProducts.Nft

def contract : ProofForge.Frontend.Surface.SurfaceContract :=
  ProofForge.Frontend.Materialize.Evm.Nft.materialize Examples.Product.Nft.spec

end TestFixtures.SurfaceProducts.Nft
