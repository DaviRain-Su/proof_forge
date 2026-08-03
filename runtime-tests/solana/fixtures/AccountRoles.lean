import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

program AccountRoles where
  requires extension solana.cpi.accounts version "1.0.0"
    digest "sha256:df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020"

  state value : UInt64

  init(initial : UInt64) do
    value := initial

  entry route(payer : Principal, authority : Principal,
      recipient : Principal, lamports : UInt64) : UInt64 do
    call solana.system.transfer(payer, recipient, lamports)
    call solana.companion.invoke(authority, lamports)
    return value

  view inspect() : UInt64 do
    return value

end Examples
