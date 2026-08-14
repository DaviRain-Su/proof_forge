import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- EXT-CRYPTO EVM leaf fixture. Mutating entry uses the exact
-- UInt256×4→UInt256 pf.crypto.ecdsaRecoverSecp256k1 binding (ecrecover
-- precompile 0x01). Recover failure returns the zero word (native EVM).
-- Not imported by Examples.lean (host-optional Anvil companion fixture).
program EcdsaRecoverCheck where
  state last : UInt256

  init() do
    last := 0

  entry recover(hash : UInt256, v : UInt256, r : UInt256, s : UInt256) : UInt256 do
    let a : UInt256 := call pf.crypto.ecdsaRecoverSecp256k1(hash, v, r, s)
    last := a
    return a

  view get() : UInt256 do
    return last

end Examples
