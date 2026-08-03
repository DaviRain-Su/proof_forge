import ProofForgeV2

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

-- C-5/T12: Principal is stored as its exact wire identity leaves
-- (len + 8×UInt64 payload words), never reinterpreted as a Solana pubkey.
program PrincipalStore where
  state owner : Principal

  init(initial : Principal) do
    owner := initial

  entry setOwner(who : Principal) : Bool do
    owner := who
    return true

  view same(a : Principal, b : Principal) : Bool do
    return a == b

  view matchesOwner(who : Principal) : Bool do
    return owner == who

end ProofForgeV2.Examples
