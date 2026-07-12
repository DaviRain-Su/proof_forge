import ProofForge.Contract.Stdlib.NearFungibleToken

namespace ProofForge.Tests.NearFtSecurity

open ProofForge.IR

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def requireEntrypoint (name : String) : IO Entrypoint := do
  let some entrypoint := ProofForge.Contract.Stdlib.NearFungibleToken.module.entrypoints.find?
      (fun entrypoint => entrypoint.name == name)
    | throw <| IO.userError s!"NearFungibleToken missing `{name}`"
  pure entrypoint

def main : IO Unit := do
  let module := ProofForge.Contract.Stdlib.NearFungibleToken.module
  let stateIds := module.state.map (fun state => state.id)
  for required in #["initialized", "mintAuthority", "nextTransferId",
      "pendingAmounts", "pendingActive"] do
    require (stateIds.contains required) s!"NearFungibleToken missing security state `{required}`"
  for forbidden in #["_ftPendingSender", "_ftPendingReceiver", "_ftPendingAmount"] do
    require (!stateIds.contains forbidden) s!"NearFungibleToken retained global callback state `{forbidden}`"

  let init <- requireEntrypoint "init"
  let initIr := reprStr init.body
  require (initIr.contains "already initialized") "init must reject repeated initialization"
  require (initIr.contains "mintAuthority") "init must bind the mint authority"

  let mint <- requireEntrypoint "ft_mint"
  require ((reprStr mint.body).contains "not mint authority") "ft_mint must authorize its caller"

  let transferCall <- requireEntrypoint "ft_transfer_call"
  let transferIr := reprStr transferCall.body
  require (transferIr.contains "nextTransferId") "ft_transfer_call must allocate a transfer id"
  require (transferIr.contains "pendingActive") "ft_transfer_call must persist keyed callback state"
  require (transferIr.contains "nearPromiseThen" && transferIr.contains "transferId")
    "ft_transfer_call must pass its transfer id to the callback"

  let resolver <- requireEntrypoint "ft_resolve_transfer"
  require (resolver.params == #[("transfer_id", .u64), ("sender", .hash), ("receiver", .hash)])
    "ft_resolve_transfer must receive the transfer id and immutable callback identities"
  let resolverIr := reprStr resolver.body
  require (resolverIr.contains "callback must be private")
    "ft_resolve_transfer must require predecessor == current account"
  require (resolverIr.contains "pending transfer missing")
    "ft_resolve_transfer must consume one active transfer exactly once"
  require (resolverIr.contains "pendingAmounts")
    "ft_resolve_transfer must load the original amount by transfer id"
  require (resolverIr.contains "refund")
    "ft_resolve_transfer must compute a bounded refund"
  IO.println "near-ft-security: ok"

end ProofForge.Tests.NearFtSecurity

def main : IO Unit := ProofForge.Tests.NearFtSecurity.main
