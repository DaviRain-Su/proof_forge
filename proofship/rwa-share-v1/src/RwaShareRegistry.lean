import ProofForgeV2

namespace Proofship

open ProofForgeV2.Language

-- ProofShip · AI-RWA first vertical — hand-written golden template (rwa-share-v1).
-- Onchain share registry with transfer policy:
--   owner-gated issuance (issued <= totalSupply via checked arithmetic),
--   allowlist-gated transfers, per-tx cap, rolling 1000-block window cap.
-- EVM deploy file: NO invariant/proof declarations (EVM build fails closed on
-- nonempty invariants; the proof twin lives separately per plan §4.4).
-- Constructs used here are all pinned by shipped fixtures:
--   Principal state/param + context.caller (CallerCheck, vault-v1 spike),
--   Map Principal UInt64 / Map Principal Bool (vault-v1, ProbeMapBool*),
--   context.blockHeight (BlockHeightCheck), if/match Option (MiniAmm),
--   bare assert + revert Named() (vault-v1; NOTE: `error X()` needs parens).
program RwaShareRegistry where
  state owner : Principal
  state totalSupply : UInt64
  state issued : UInt64
  state balance : Map Principal UInt64
  -- Allowlist flag: 1 = allowed, 0/absent = blocked.
  -- NOTE: EVM Plan requires map VALUE type UInt64 (Map Principal Bool fails
  -- closed), so the flag is UInt64 rather than Bool.
  state allowlist : Map Principal UInt64
  state maxPerTx : UInt64
  state windowCap : UInt64
  state windowStart : UInt64
  state windowSpent : UInt64

  event Issued(amount : UInt64)
  event Transferred(amount : UInt64)

  error NotAllowed()
  error InsufficientBalance()

  init(supply : UInt64, perTx : UInt64, window : UInt64) do
    owner := context.caller
    totalSupply := supply
    issued := 0
    balance := Map.empty()
    allowlist := Map.empty()
    maxPerTx := perTx
    windowCap := window
    windowStart := context.blockHeight
    windowSpent := 0

  -- Owner-only: set transfer allowlist membership (ok: 1 = allow, 0 = block).
  -- NOTE: S1 gate does not admit Bool params, so the flag is UInt64.
  entry setAllow(who : Principal, ok : UInt64) : UInt64 do
    assert context.caller == owner
    assert ok <= 1
    allowlist[who] := ok
    return ok

  -- Owner-only: issue new shares (never beyond totalSupply; checked add reverts
  -- on overflow, so `issued + amount <= totalSupply` is a full conservation gate).
  entry issue(to : Principal, amount : UInt64) : UInt64 do
    assert context.caller == owner
    assert issued + amount <= totalSupply
    match balance[to] with
    | Option.some(v) => do
      balance[to] := v + amount
      issued := issued + amount
      emit Issued(amount)
      return issued
    | _ => do
      balance[to] := amount
      issued := issued + amount
      emit Issued(amount)
      return issued

  -- Holder → allowlisted recipient, per-tx cap + rolling window cap.
  -- Window resets after 1000 blocks from windowStart.
  entry transfer(to : Principal, amount : UInt64) : UInt64 do
    assert amount <= maxPerTx
    match allowlist[to] with
    | Option.some(flag) => do
      assert flag == 1
      if windowStart + 1000 <= context.blockHeight then
        windowStart := context.blockHeight
        windowSpent := 0
      assert windowSpent + amount <= windowCap
      match balance[context.caller] with
      | Option.some(bal) => do
        assert amount <= bal
        match balance[to] with
        | Option.some(tb) => do
          balance[context.caller] := bal - amount
          balance[to] := tb + amount
          windowSpent := windowSpent + amount
          emit Transferred(amount)
          return windowSpent
        | _ => do
          balance[context.caller] := bal - amount
          balance[to] := amount
          windowSpent := windowSpent + amount
          emit Transferred(amount)
          return windowSpent
      | _ => do
        revert InsufficientBalance()
    | _ => do
      revert NotAllowed()

  view balanceOf(who : Principal) : UInt64 do
    match balance[who] with
    | Option.some(v) => do
      return v
    | _ => do
      return 0

  view isAllowed(who : Principal) : Bool do
    match allowlist[who] with
    | Option.some(flag) => do
      return flag == 1
    | _ => do
      return false

  view issuedTotal() : UInt64 do
    return issued

  view policy() : UInt64 do
    return maxPerTx

end Proofship
