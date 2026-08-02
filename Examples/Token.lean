import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- NS-1 fungible token (Map UInt64→UInt64 balances + supply).
-- Account keys are UInt64 ids (not Principal — Principal Map/state is still
-- target-gated outside EVM T10 leaf storage). Transfer/mint use Map IndexGet/Set.
-- Product check/compile succeeds. EVM dense Map pilot lowers to deployable
-- Yul/bin (capacity-8 open table). Solana/NEAR/Noir Plan still FAIL-CLOSED on
-- Map state until those leaf lanes open.
program Token where
  state balances : Map UInt64 UInt64
  state supply : UInt64

  init() do
    balances := Map.empty()
    supply := 0

  entry mint(to : UInt64, amount : UInt64) : UInt64 do
    match balances[to] with
    | Option.some(v) => do
      balances[to] := v + amount
      supply := supply + amount
      return supply
    | _ => do
      balances[to] := amount
      supply := supply + amount
      return supply

  entry transfer(src : UInt64, dst : UInt64, amount : UInt64) : Bool do
    match balances[src] with
    | Option.some(fromBal) => do
      assert fromBal >= amount
      match balances[dst] with
      | Option.some(toBal) => do
        balances[src] := fromBal - amount
        balances[dst] := toBal + amount
        return true
      | _ => do
        balances[src] := fromBal - amount
        balances[dst] := amount
        return true
    | _ => do
      assert false
      return false

  view total() : UInt64 do
    return supply

  view balanceOf(who : UInt64) : UInt64 do
    match balances[who] with
    | Option.some(v) => do
      return v
    | _ => do
      return 0

end Examples
