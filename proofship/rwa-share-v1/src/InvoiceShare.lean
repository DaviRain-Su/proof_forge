import ProofForgeV2

namespace Proofship

open ProofForgeV2.Language

-- AI-generated variant (few-shot 01): tokenized invoice shares.
-- Same template family as golden RwaShareRegistry: renamed program/state,
-- window = 600 blocks. Deploy-time policy values arrive as constructor args.
program InvoiceShare where
  state issuer : Principal
  state maxSupply : UInt64
  state sharesIssued : UInt64
  state shares : Map Principal UInt64
  state allowed : Map Principal UInt64
  state perTxLimit : UInt64
  state windowLimit : UInt64
  state windowOpenedAt : UInt64
  state windowMoved : UInt64

  event SharesIssued(amount : UInt64)
  event SharesMoved(amount : UInt64)

  error Blocked()
  error NotEnoughShares()

  init(supply : UInt64, perTx : UInt64, window : UInt64) do
    issuer := context.caller
    maxSupply := supply
    sharesIssued := 0
    shares := Map.empty()
    allowed := Map.empty()
    perTxLimit := perTx
    windowLimit := window
    windowOpenedAt := context.blockHeight
    windowMoved := 0

  entry setAllowed(who : Principal, ok : UInt64) : UInt64 do
    assert context.caller == issuer
    assert ok <= 1
    allowed[who] := ok
    return ok

  entry issueShares(to : Principal, amount : UInt64) : UInt64 do
    assert context.caller == issuer
    assert sharesIssued + amount <= maxSupply
    match shares[to] with
    | Option.some(v) => do
      shares[to] := v + amount
      sharesIssued := sharesIssued + amount
      emit SharesIssued(amount)
      return sharesIssued
    | _ => do
      shares[to] := amount
      sharesIssued := sharesIssued + amount
      emit SharesIssued(amount)
      return sharesIssued

  entry moveShares(to : Principal, amount : UInt64) : UInt64 do
    assert amount <= perTxLimit
    match allowed[to] with
    | Option.some(flag) => do
      assert flag == 1
      if windowOpenedAt + 600 <= context.blockHeight then
        windowOpenedAt := context.blockHeight
        windowMoved := 0
      assert windowMoved + amount <= windowLimit
      match shares[context.caller] with
      | Option.some(bal) => do
        assert amount <= bal
        match shares[to] with
        | Option.some(tb) => do
          shares[context.caller] := bal - amount
          shares[to] := tb + amount
          windowMoved := windowMoved + amount
          emit SharesMoved(amount)
          return windowMoved
        | _ => do
          shares[context.caller] := bal - amount
          shares[to] := amount
          windowMoved := windowMoved + amount
          emit SharesMoved(amount)
          return windowMoved
      | _ => do
        revert NotEnoughShares()
    | _ => do
      revert Blocked()

  view sharesOf(who : Principal) : UInt64 do
    match shares[who] with
    | Option.some(v) => do
      return v
    | _ => do
      return 0

  view canReceive(who : Principal) : Bool do
    match allowed[who] with
    | Option.some(flag) => do
      return flag == 1
    | _ => do
      return false

  view issued() : UInt64 do
    return sharesIssued

  view limits() : UInt64 do
    return perTxLimit

end Proofship
