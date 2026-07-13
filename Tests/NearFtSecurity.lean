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
  require (transferCall.params == #[("receiver_id", .string), ("amount", .u128),
      ("memo", .string), ("msg", .string)])
    "ft_transfer_call must expose the standard receiver_id/amount/memo/msg ABI"
  let transferIr := reprStr transferCall.body
  require (!transferIr.contains "receiver_idx")
    "ft_transfer_call must not expose the non-standard receiver pool index"
  require (transferIr.contains "requires exactly 1 yoctoNEAR")
    "ft_transfer_call must enforce exact one yoctoNEAR"
  require (transferIr.contains "receiver is not registered")
    "ft_transfer_call must reject unregistered receivers"
  require (transferIr.contains "sender_id" && transferIr.contains "msg")
    "ft_transfer_call must encode the standard receiver hook JSON fields"
  require (transferIr.contains "nextTransferId") "ft_transfer_call must allocate a transfer id"
  require (transferIr.contains "pendingActive") "ft_transfer_call must persist keyed callback state"
  require (transferIr.contains "nearPromiseThen" && transferIr.contains "transferId")
    "ft_transfer_call must pass its transfer id to the callback"

  let transfer <- requireEntrypoint "ft_transfer"
  require (transfer.params == #[("receiver_id", .string), ("amount", .u128),
      ("memo", .string)])
    "ft_transfer must expose optional memo in its standard ABI"
  let transferIr := reprStr transfer.body
  require (transferIr.contains "ft_transfer requires exactly 1 yoctoNEAR")
    "ft_transfer must enforce exact one yoctoNEAR"
  require (transferIr.contains "receiver is not registered")
    "ft_transfer must reject unregistered receivers"

  let resolver <- requireEntrypoint "ft_resolve_transfer"
  require (resolver.params == #[("transfer_id", .u64), ("sender", .string), ("receiver", .string)])
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
