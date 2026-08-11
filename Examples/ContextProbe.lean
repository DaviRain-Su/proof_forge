import ProofForgeV2
namespace Examples
open ProofForgeV2.Language
-- P3 partial: DPN ExecutionContext ids (not EVM msg.sender / block.number).
-- Language: expression-position `call pf.context.*()` → DPN getUserId/…
-- Official simulate defaults: user_id=1, contract_id=1, checkpoint_id=100, nonce=0.
-- context.caller / context.blockHeight remain Plan FC on Psy.
program ContextProbe where
  state last : UInt64

  init() do
    last := 0

  entry snapUser() : UInt64 do
    let u : UInt64 := call pf.context.userId()
    last := u
    return u

  entry snapContract() : UInt64 do
    let c : UInt64 := call pf.context.contractId()
    last := c
    return c

  entry snapCheckpoint() : UInt64 do
    let k : UInt64 := call pf.context.checkpointId()
    last := k
    return k

  entry snapNonce() : UInt64 do
    let n : UInt64 := call pf.context.nonce()
    last := n
    return n

  entry snapCallerContract() : UInt64 do
    let c : UInt64 := call pf.context.callerContractId()
    last := c
    return c

  entry snapUserPk() : UInt64 do
    let h : UInt64 := call pf.context.userPublicKeyHash()
    last := h
    return h

  entry snapSessionRoot() : UInt64 do
    let r : UInt64 := call pf.context.sessionProofTreeRoot()
    last := r
    return r

  view get() : UInt64 do
    return last
end Examples
