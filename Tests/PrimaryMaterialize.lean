/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Materialization + crosscall mapping for every implemented registry target
(EVM · Solana · Wasm family · Psy · Aleo).
-/
import ProofForge.IR.Examples.Counter
import ProofForge.Target.CrosscallMaterialize
import ProofForge.Target.Materialize
import ProofForge.Target.Registry

open ProofForge.Target
open ProofForge.Target.Materialize
open ProofForge.Target.CrosscallMaterialize

def require (cond : Bool) (msg : String) : IO Unit :=
  if cond then pure () else throw (IO.userError msg)

def main : IO Unit := do
  -- Explicit v1 fixture coverage for target families not yet migrated to Core.
  -- The Product Counter route is covered by `portable-counter-multi-target`.
  let counter := ProofForge.IR.Examples.Counter.module

  -- Primary three
  let evmR := forEvm counter
  let solR := forSolana counter {}
  let nearR := forWasmNear counter
  require (evmR.mode == .autoPortable) "EVM auto-portable"
  require (solR.mode == .autoPortable) "Solana auto-portable"
  require (nearR.mode == .autoPortable) "NEAR auto-portable"
  require (evmR.storageBinding == "contract-global") "EVM binding"
  require (solR.storageBinding == "account-data") "Solana binding"
  require (nearR.storageBinding == "host-key-value") "NEAR binding"
  require (nearR.hostBridge? == some "near") "NEAR host"

  -- Other Wasm hosts
  let cosmwasmR := forWasmCosmWasm counter
  require (cosmwasmR.targetId == "wasm-cosmwasm") "CosmWasm id"
  require (cosmwasmR.hostBridge? == some "cosmwasm") "CosmWasm host"
  require (cosmwasmR.layoutKind == "cosmwasm-storage") "CosmWasm layout"
  require (cosmwasmR.mode == .autoPortable) "CosmWasm auto-portable"

  -- ZK
  let psyR := forPsyDpn counter
  let aleoR := forAleoLeo counter
  require (psyR.storageBinding == "circuit-mapping") "Psy circuit"
  require (aleoR.storageBinding == "circuit-mapping") "Aleo circuit"
  require (psyR.layoutKind == "psy-circuit-storage") "Psy layout"
  require (aleoR.layoutKind == "leo-mapping-storage") "Aleo layout"

  -- Every active registry profile yields a report
  let reports := reportsForAllImplemented counter
  require (reports.size == all.size)
    s!"expected report per active target, got {reports.size} vs {all.size}"
  for profile in all do
    match forImplementedProfile profile counter with
    | none => throw (IO.userError s!"missing materialize for {profile.id}")
    | some r =>
        require (r.targetId == profile.id) s!"targetId mismatch for {profile.id}"
        require (r.mode == .autoPortable)
          s!"Shared Counter should be auto-portable on {profile.id}"

  -- Crosscall materialization table for all implemented targets
  let xcalls := CrosscallMaterialize.reportsForAllImplemented
  require (xcalls.size == all.size) "crosscall report per target"
  let evmX := forProfile evm
  let solX := forProfile solanaSbpfAsm
  let nearX := forProfile wasmNear
  let cosmwasmX := forProfile wasmCosmWasm
  let psyX := forProfile psyDpn
  let aleoX := forProfile aleoLeo
  require (evmX.nativeForm == .evmCall) "EVM crosscall form"
  require (solX.nativeForm == .solanaCpi) "Solana crosscall form"
  require (nearX.nativeForm == .nearPromise) "NEAR crosscall form"
  require (cosmwasmX.nativeForm == .cosmWasmMsg) "CosmWasm crosscall form (deferred spike)"
  require (psyX.nativeForm == .zkCircuitCall) "Psy crosscall form"
  require (aleoX.nativeForm == .zkCircuitCall) "Aleo crosscall form"
  -- Soroban host-adapter profile (constant, not in Registry.all / list-targets).
  let sorobanR := forWasmStellarSoroban counter
  require (sorobanR.targetId == "wasm-stellar-soroban") "Soroban materialize id"
  require (sorobanR.hostBridge? == some "soroban") "Soroban host bridge"
  require (sorobanR.layoutKind == "soroban-storage") "Soroban layout"
  require (sorobanR.mode == .autoPortable) "Soroban Counter auto-portable"
  let sorobanX := forProfile wasmStellarSoroban
  require (sorobanX.nativeForm == .sorobanInvoke) "Soroban crosscall form"
  require (sorobanX.nativeForm.id == "soroban-invoke") "Soroban form id"
  require (sorobanX.asyncSupport == "sync-host-invoke") "Soroban async model"
  require (sorobanX.nativeForm != NativeForm.nearPromise)
    "Soroban must not alias NEAR promise"
  require (!(moduleUsesPortableCrosscall counter))
    "Counter fixture should not use portable crosscall nodes"

  IO.println s!"implemented-materialize: ok ({reports.size} targets + crosscall map + soroban adapter)"
