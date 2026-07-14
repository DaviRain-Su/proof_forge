import Examples.Product.Nft
import ProofForge.Contract.Nft.EvmSurface

namespace Examples.Product.Canonical.Nft

def contract : ProofForge.Frontend.Surface.SurfaceContract :=
  ProofForge.Contract.Nft.EvmSurface.materialize Examples.Product.Nft.spec

end Examples.Product.Canonical.Nft
