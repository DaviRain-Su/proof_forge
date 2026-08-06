import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- NS-1 fungible token (Map UInt64→UInt64 balances + supply).
-- Account keys are UInt64 ids (not Principal — shared admits Map Principal UInt64
-- but every materializer still only lowers Map UInt64 UInt64; T10/T12 Principal
-- is scalar storage only). Transfer/mint use Map IndexGet/Set.
-- Dense Map UInt64→UInt64 pilot (capacity-8 occ/key/val, pure-expr expansion)
-- on EVM + Solana + NEAR + Noir:
--   * EVM: locked-solc finalization (creation bytecode may exceed EIP-3860)
--   * Solana: default plan profile; MapMini opt-in ELF + Mollusk available
--   * NEAR: deployable WAT/Wasm (wat2wasm when present)
--   * Noir: source relations + multi-leaf public inputs (source-only maturity)
-- Engineering runtime smokes (not formal): scripts/evm_token_anvil_smoke.sh,
-- scripts/near_token_wasm_smoke.sh, runtime-tests/solana/fixtures/MapMini.lean.
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
