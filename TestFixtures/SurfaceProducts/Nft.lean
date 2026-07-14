import Examples.Product.Nft
import ProofForge.Contract.Nft.EvmSurface

namespace TestFixtures.SurfaceProducts.Nft

def contract : ProofForge.Frontend.Surface.SurfaceContract :=
  ProofForge.Contract.Nft.EvmSurface.materialize Examples.Product.Nft.spec

end TestFixtures.SurfaceProducts.Nft
