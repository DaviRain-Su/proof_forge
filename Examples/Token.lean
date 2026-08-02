import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- NS-1 fungible token (Map UInt64→UInt64 balances + supply).
-- Account keys are UInt64 ids (not Principal — Principal Map/state is still
-- target-gated outside EVM T10 leaf storage). Transfer/mint use Map IndexGet/Set.
-- Dense Map UInt64→UInt64 pilot (capacity-8 occ/key/val, pure-expr expansion)
-- on EVM + Solana + NEAR + Noir:
--   * EVM: deployable Yul/bin (solc when locked)
--   * Solana: default plan profile (deployable=false); pure-expr Map exceeds
--     SBPF 4 KiB frame under solana-sbpf-elf-v1 — ELF stays opt-in for non-Map
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
