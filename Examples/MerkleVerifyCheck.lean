import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- CAP-X-MERKLE-EVM-ANVIL companion fixture. The mutating entry uses the
-- exact D=2 pf.crypto.merkleVerifyKeccak256 leaf (OpenZeppelin sorted-pair
-- keccak256 chain). Verify must live on an entry (view is PF-EFFECT-001
-- banned). Product Normalize still fail-closes Bool/Unit state, so the
-- Bool result is persisted as admitted UInt64 0/1; get() re-derives Bool.
-- Not imported by Examples.lean (host-optional Anvil companion fixture).
program MerkleVerifyCheck where
  state last : UInt64

  init() do
    last := 0

  entry verify(root : UInt256, leaf : UInt256, s0 : UInt256, s1 : UInt256) : Bool do
    let ok : Bool := call pf.crypto.merkleVerifyKeccak256(root, leaf, s0, s1)
    if ok then
      last := 1
    else
      last := 0
    return ok

  view get() : Bool do
    return last == 1

end Examples
